package com.samirpatel.sportsdash

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.samirpatel.sportsdash.core.iptv.IptvRepository
import com.samirpatel.sportsdash.core.iptv.describe
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.model.PlaylistConfig
import com.samirpatel.sportsdash.core.model.PlaylistType
import com.samirpatel.sportsdash.core.model.StreamContainer
import com.samirpatel.sportsdash.data.PrefsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class AppUiState(
    val playlist: PlaylistConfig? = null,
    val channels: List<IptvChannel> = emptyList(),
    val groups: List<String> = emptyList(),
    val selectedGroup: String = "All",
    val isLoading: Boolean = false,
    val status: String? = null,
    val error: String? = null,
    val playing: IptvChannel? = null,
    val playUrl: String? = null,
    val engineLabel: String = "VLC",
)

class AppViewModel(
    private val prefs: PrefsStore,
    private val iptv: IptvRepository = IptvRepository(),
) : ViewModel() {

    private val _state = MutableStateFlow(AppUiState())
    val state: StateFlow<AppUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            prefs.playlistFlow.collect { cfg ->
                _state.update { it.copy(playlist = cfg) }
                if (cfg != null && _state.value.channels.isEmpty()) {
                    refreshChannels()
                }
            }
        }
    }

    fun saveXtream(name: String, host: String, user: String, pass: String) {
        val cfg = PlaylistConfig(
            name = name.ifBlank { "Xtream" },
            type = PlaylistType.XTREAM,
            host = host.trim(),
            username = user.trim(),
            password = pass,
        )
        viewModelScope.launch {
            prefs.savePlaylist(cfg)
            _state.update { it.copy(playlist = cfg, error = null) }
            refreshChannels()
        }
    }

    fun saveM3u(name: String, url: String) {
        val cfg = PlaylistConfig(
            name = name.ifBlank { "M3U" },
            type = PlaylistType.M3U,
            m3uUrl = url.trim(),
        )
        viewModelScope.launch {
            prefs.savePlaylist(cfg)
            _state.update { it.copy(playlist = cfg, error = null) }
            refreshChannels()
        }
    }

    fun refreshChannels() {
        val cfg = _state.value.playlist ?: return
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null, status = "Loading ${cfg.describe()}…") }
            val result = iptv.loadChannels(cfg)
            result.onSuccess { channels ->
                val groups = buildList {
                    add("All")
                    addAll(channels.mapNotNull { it.group }.distinct().sorted())
                }
                _state.update {
                    it.copy(
                        channels = channels,
                        groups = groups,
                        selectedGroup = if (it.selectedGroup in groups) it.selectedGroup else "All",
                        isLoading = false,
                        status = "${channels.size} channels",
                        error = null,
                    )
                }
            }.onFailure { e ->
                _state.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Load failed",
                        status = null,
                    )
                }
            }
        }
    }

    fun selectGroup(group: String) {
        _state.update { it.copy(selectedGroup = group) }
    }

    fun filteredChannels(): List<IptvChannel> {
        val s = _state.value
        return if (s.selectedGroup == "All") s.channels
        else s.channels.filter { it.group == s.selectedGroup }
    }

    fun play(channel: IptvChannel) {
        val candidates = iptv.playbackCandidates(channel.url, preferTs = true)
        val url = candidates.first()
        val kind = StreamContainer.detect(url)
        _state.update {
            it.copy(
                playing = channel,
                playUrl = url,
                engineLabel = "VLC · ${kind.name}",
                error = null,
            )
        }
    }

    fun stopPlayback() {
        _state.update { it.copy(playing = null, playUrl = null) }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }

    companion object {
        fun factory(context: Context): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return AppViewModel(PrefsStore(context.applicationContext)) as T
                }
            }
    }
}
