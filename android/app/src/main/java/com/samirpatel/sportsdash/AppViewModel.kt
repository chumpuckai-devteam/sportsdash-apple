package com.samirpatel.sportsdash

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.samirpatel.sportsdash.core.iptv.IptvRepository
import com.samirpatel.sportsdash.core.iptv.describe
import com.samirpatel.sportsdash.core.matching.ChannelMatch
import com.samirpatel.sportsdash.core.matching.MatchingService
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.model.PlaylistConfig
import com.samirpatel.sportsdash.core.model.PlaylistType
import com.samirpatel.sportsdash.core.model.StreamContainer
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.core.sports.GameStatus
import com.samirpatel.sportsdash.core.sports.SportLeague
import com.samirpatel.sportsdash.core.sports.SportsRepository
import com.samirpatel.sportsdash.data.PrefsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class ScoresFilter { LIVE, UPCOMING, FINAL }

enum class GuideLayout { LIST, GRID }

data class AppUiState(
    val playlist: PlaylistConfig? = null,
    val channels: List<IptvChannel> = emptyList(),
    val groups: List<String> = emptyList(),
    val selectedGroup: String = "All",
    val searchQuery: String = "",
    val guideLayout: GuideLayout = GuideLayout.LIST,
    val isLoadingChannels: Boolean = false,
    val channelStatus: String? = null,
    val channelError: String? = null,

    val games: List<Game> = emptyList(),
    val selectedLeagueIds: Set<String> = SportLeague.DEFAULTS.map { it.id }.toSet(),
    val scoresFilter: ScoresFilter = ScoresFilter.LIVE,
    val isLoadingScores: Boolean = false,
    val scoresStatus: String? = null,
    val scoresError: String? = null,
    val scoresUpdatedAtMs: Long? = null,

    /** Stream picker opened from a scoreboard game. */
    val streamPickerGame: Game? = null,
    val streamMatches: List<ChannelMatch> = emptyList(),

    val playing: IptvChannel? = null,
    val playUrl: String? = null,
    val engineLabel: String = "VLC",
    val playerMessage: String? = null,
    /** Optional game context while watching (for ticker / hero). */
    val playingGameId: String? = null,
)

class AppViewModel(
    private val prefs: PrefsStore,
    private val iptv: IptvRepository = IptvRepository(),
    private val sports: SportsRepository = SportsRepository(),
    private val matching: MatchingService = MatchingService(),
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
        refreshScores()
    }

    // region Playlist / Guide

    fun saveXtream(name: String, serverUrl: String, user: String, pass: String) {
        val cfg = PlaylistConfig(
            name = name.ifBlank { "Xtream" },
            type = PlaylistType.XTREAM,
            host = serverUrl.trim(),
            username = user.trim(),
            password = pass,
        )
        viewModelScope.launch {
            prefs.savePlaylist(cfg)
            _state.update { it.copy(playlist = cfg, channelError = null, channels = emptyList()) }
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
            _state.update { it.copy(playlist = cfg, channelError = null, channels = emptyList()) }
            refreshChannels()
        }
    }

    fun refreshChannels() {
        val cfg = _state.value.playlist ?: return
        viewModelScope.launch {
            _state.update {
                it.copy(
                    isLoadingChannels = true,
                    channelError = null,
                    channelStatus = "Loading ${cfg.describe()}…",
                )
            }
            iptv.loadChannels(cfg).onSuccess { channels ->
                val groups = buildList {
                    add("All")
                    addAll(
                        channels.mapNotNull { it.group }
                            .distinct()
                            .sortedWith(String.CASE_INSENSITIVE_ORDER),
                    )
                }
                _state.update {
                    it.copy(
                        channels = channels,
                        groups = groups,
                        selectedGroup = if (it.selectedGroup in groups) it.selectedGroup else "All",
                        isLoadingChannels = false,
                        channelStatus = "${channels.size} channels · ${groups.size - 1} categories",
                        channelError = null,
                    )
                }
            }.onFailure { e ->
                _state.update {
                    it.copy(
                        isLoadingChannels = false,
                        channelError = e.message ?: "Load failed",
                        channelStatus = null,
                    )
                }
            }
        }
    }

    fun selectGroup(group: String) {
        _state.update { it.copy(selectedGroup = group) }
    }

    fun setSearchQuery(q: String) {
        _state.update { it.copy(searchQuery = q) }
    }

    fun setGuideLayout(layout: GuideLayout) {
        _state.update { it.copy(guideLayout = layout) }
    }

    fun filteredChannels(): List<IptvChannel> {
        val s = _state.value
        val base = if (s.selectedGroup == "All") s.channels
        else s.channels.filter { it.group == s.selectedGroup }
        val q = s.searchQuery.trim()
        if (q.isEmpty()) return base
        return base.filter {
            it.name.contains(q, ignoreCase = true) ||
                (it.group?.contains(q, ignoreCase = true) == true)
        }
    }

    fun play(channel: IptvChannel, gameId: String? = null) {
        val url = iptv.playbackCandidates(channel.url, preferTs = true).first()
        val kind = StreamContainer.detect(url)
        _state.update {
            it.copy(
                playing = channel,
                playUrl = url,
                engineLabel = "VLC · ${kind.name}",
                playerMessage = null,
                playingGameId = gameId,
                streamPickerGame = null,
                streamMatches = emptyList(),
            )
        }
    }

    fun stopPlayback() {
        // Clear first so UI leaves player immediately even if release races
        _state.update {
            it.copy(
                playing = null,
                playUrl = null,
                playerMessage = null,
                playingGameId = null,
            )
        }
    }

    // endregion

    // region Scores + matching

    fun refreshScores() {
        viewModelScope.launch {
            val leagues = SportLeague.ALL.filter { it.id in _state.value.selectedLeagueIds }
            if (leagues.isEmpty()) {
                _state.update {
                    it.copy(
                        games = emptyList(),
                        scoresStatus = "Select leagues in Settings",
                        isLoadingScores = false,
                    )
                }
                return@launch
            }
            _state.update {
                it.copy(isLoadingScores = true, scoresError = null, scoresStatus = "Updating scores…")
            }
            runCatching { sports.fetchGames(leagues) }
                .onSuccess { games ->
                    val live = games.count { it.isLive }
                    val up = games.count { it.isUpcoming }
                    _state.update {
                        it.copy(
                            games = games,
                            isLoadingScores = false,
                            scoresUpdatedAtMs = System.currentTimeMillis(),
                            scoresStatus = "$live live · $up upcoming · ${games.size} total",
                            scoresError = null,
                        )
                    }
                }
                .onFailure { e ->
                    _state.update {
                        it.copy(
                            isLoadingScores = false,
                            scoresError = e.message ?: "Scores failed",
                            scoresStatus = null,
                        )
                    }
                }
        }
    }

    fun setScoresFilter(filter: ScoresFilter) {
        _state.update { it.copy(scoresFilter = filter) }
    }

    fun toggleLeague(id: String) {
        _state.update { s ->
            val next = s.selectedLeagueIds.toMutableSet()
            if (!next.add(id)) next.remove(id)
            s.copy(selectedLeagueIds = next)
        }
        refreshScores()
    }

    fun filteredGames(): List<Game> {
        val s = _state.value
        return when (s.scoresFilter) {
            ScoresFilter.LIVE -> s.games.filter { it.isLive }
            ScoresFilter.UPCOMING -> s.games.filter { it.isUpcoming }
            ScoresFilter.FINAL -> s.games.filter { it.isFinal || it.status == GameStatus.FINAL }
        }
    }

    fun gamesByLeague(): Map<SportLeague, List<Game>> {
        return filteredGames()
            .groupBy { it.league }
            .toSortedMap(compareBy { it.label })
    }

    fun liveGames(): List<Game> = _state.value.games.filter { it.isLive }

    /** Tap a scoreboard game → open channel picker (or prompt to add playlist). */
    fun openStreamPicker(game: Game) {
        val channels = _state.value.channels
        if (channels.isEmpty()) {
            _state.update {
                it.copy(
                    streamPickerGame = game,
                    streamMatches = emptyList(),
                    scoresError = if (it.playlist == null) {
                        "Add an IPTV playlist in Settings to watch streams"
                    } else {
                        "No channels loaded yet — pull to refresh Guide"
                    },
                )
            }
            return
        }
        val matches = matching.matchGameToChannels(game, channels)
        _state.update {
            it.copy(
                streamPickerGame = game,
                streamMatches = matches,
                scoresError = null,
            )
        }
    }

    fun dismissStreamPicker() {
        _state.update { it.copy(streamPickerGame = null, streamMatches = emptyList()) }
    }

    fun playMatch(match: ChannelMatch, game: Game) {
        play(match.channel, gameId = game.id)
    }

    fun playFromTicker(game: Game) {
        // Prefer best match if available
        val matches = matching.matchGameToChannels(game, _state.value.channels, limit = 1)
        val best = matches.firstOrNull()
        if (best != null) {
            play(best.channel, gameId = game.id)
        } else {
            openStreamPicker(game)
        }
    }

    // endregion

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
