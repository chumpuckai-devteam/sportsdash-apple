package com.samirpatel.sportsdash

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.samirpatel.sportsdash.core.epg.EpgProgram
import com.samirpatel.sportsdash.core.epg.EpgRepository
import com.samirpatel.sportsdash.core.epg.nowOrNearest
import com.samirpatel.sportsdash.core.epg.nowPlaying
import com.samirpatel.sportsdash.core.epg.upNext
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
import java.io.File
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Calendar

enum class ScoresFilter { LIVE, UPCOMING, FINAL }

/** LIST = hour timeline (iOS Guide list); GRID = channel cards. */
enum class GuideLayout { LIST, GRID }

/** Synthetic Guide group — always first when shown. */
const val FAVORITES_GROUP = "★ Favorites"

fun snappedCurrentHourMs(): Long {
    val cal = Calendar.getInstance()
    cal.set(Calendar.MINUTE, 0)
    cal.set(Calendar.SECOND, 0)
    cal.set(Calendar.MILLISECOND, 0)
    return cal.timeInMillis
}

data class AppUiState(
    val playlist: PlaylistConfig? = null,
    val channels: List<IptvChannel> = emptyList(),
    /** Provider order — never alphabetically sorted. */
    val groups: List<String> = emptyList(),
    val selectedGroup: String = "",
    val searchQuery: String = "",
    val guideLayout: GuideLayout = GuideLayout.LIST,
    val isLoadingChannels: Boolean = false,
    val channelStatus: String? = null,
    val channelError: String? = null,

    val epgByChannelId: Map<String, List<EpgProgram>> = emptyMap(),
    val isLoadingEpg: Boolean = false,
    val isAutoFillingEpg: Boolean = false,
    /** Open-category short EPG status. */
    val epgStatus: String? = null,
    /** Background bulk xmltv download/parse status (always visible while working). */
    val bulkEpgStatus: String? = null,

    /** Timeline window start (epoch ms), snapped to local hour. */
    val guideWindowStartMs: Long = snappedCurrentHourMs(),

    val games: List<Game> = emptyList(),
    val selectedLeagueIds: Set<String> = SportLeague.DEFAULTS.map { it.id }.toSet(),
    val scoresFilter: ScoresFilter = ScoresFilter.LIVE,
    val isLoadingScores: Boolean = false,
    val scoresStatus: String? = null,
    val scoresError: String? = null,
    val scoresUpdatedAtMs: Long? = null,

    val streamPickerGame: Game? = null,
    val streamMatches: List<ChannelMatch> = emptyList(),

    val playing: IptvChannel? = null,
    val playUrl: String? = null,
    val engineLabel: String = "VLC",
    val playerMessage: String? = null,
    val playingGameId: String? = null,

    val showScoresTicker: Boolean = true,

    /** Channel ids starred by user (persisted). */
    val favoriteChannelIds: Set<String> = emptySet(),
)

class AppViewModel(
    private val prefs: PrefsStore,
    private val iptv: IptvRepository = IptvRepository(),
    private val sports: SportsRepository = SportsRepository(),
    private val matching: MatchingService = MatchingService(),
    private val epg: EpgRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(AppUiState())
    val state: StateFlow<AppUiState> = _state.asStateFlow()

    private var epgJob: Job? = null
    private var categoryEpgJob: Job? = null

    init {
        viewModelScope.launch {
            prefs.playlistFlow.collect { cfg ->
                _state.update { it.copy(playlist = cfg) }
                if (cfg != null && _state.value.channels.isEmpty()) {
                    refreshChannels()
                }
            }
        }
        viewModelScope.launch {
            prefs.showScoresTickerFlow.collect { show ->
                _state.update { it.copy(showScoresTicker = show) }
            }
        }
        viewModelScope.launch {
            prefs.favoriteChannelIdsFlow.collect { ids ->
                _state.update { it.copy(favoriteChannelIds = ids) }
            }
        }
        refreshScores()
    }

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
            _state.update {
                it.copy(
                    playlist = cfg,
                    channelError = null,
                    channels = emptyList(),
                    groups = emptyList(),
                    epgByChannelId = emptyMap(),
                )
            }
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
            _state.update {
                it.copy(
                    playlist = cfg,
                    channelError = null,
                    channels = emptyList(),
                    groups = emptyList(),
                    epgByChannelId = emptyMap(),
                )
            }
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
            iptv.loadChannels(cfg).onSuccess { loaded ->
                val channels = loaded.channels
                // Provider order only — no alphabetical sort
                val groups = loaded.categoryOrder
                val previous = _state.value.selectedGroup
                val selected = when {
                    previous.isNotBlank() && previous in groups -> previous
                    groups.isNotEmpty() -> groups.first()
                    else -> ""
                }
                _state.update {
                    it.copy(
                        channels = channels,
                        groups = groups,
                        selectedGroup = selected,
                        isLoadingChannels = false,
                        channelStatus = "${channels.size} channels · ${groups.size} categories",
                        channelError = null,
                        guideWindowStartMs = snappedCurrentHourMs(),
                    )
                }
                // EPG: full guide is primary (download once). Short Now/Next is optional bonus.
                reloadEpgBulkBackground()
                loadEpgForOpenCategory(force = false)
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
        // Favorites don't need short-EPG of whole playlist; still try open category
        if (group != FAVORITES_GROUP) {
            loadEpgForOpenCategory(force = false)
        }
    }

    fun setSearchQuery(q: String) {
        _state.update { it.copy(searchQuery = q) }
    }

    fun setGuideLayout(layout: GuideLayout) {
        _state.update { it.copy(guideLayout = layout) }
    }

    fun isFavorite(channelId: String): Boolean =
        channelId in _state.value.favoriteChannelIds

    fun toggleFavorite(channel: IptvChannel) {
        val id = channel.id
        val next = _state.value.favoriteChannelIds.toMutableSet()
        if (id in next) next.remove(id) else next.add(id)
        _state.update { it.copy(favoriteChannelIds = next) }
        viewModelScope.launch { prefs.setFavoriteChannelIds(next) }
    }

    fun addFavorite(channel: IptvChannel) {
        if (isFavorite(channel.id)) return
        val next = _state.value.favoriteChannelIds + channel.id
        _state.update { it.copy(favoriteChannelIds = next) }
        viewModelScope.launch { prefs.setFavoriteChannelIds(next) }
    }

    fun removeFavorite(channel: IptvChannel) {
        if (!isFavorite(channel.id)) return
        val next = _state.value.favoriteChannelIds - channel.id
        _state.update { it.copy(favoriteChannelIds = next) }
        viewModelScope.launch { prefs.setFavoriteChannelIds(next) }
    }

    /** Provider categories with Favorites pinned first. */
    fun guideCategoryGroups(): List<String> {
        val provider = _state.value.groups
        return listOf(FAVORITES_GROUP) + provider
    }

    fun shiftGuideWindowHours(deltaHours: Int) {
        _state.update {
            val cal = Calendar.getInstance()
            cal.timeInMillis = it.guideWindowStartMs
            cal.add(Calendar.HOUR_OF_DAY, deltaHours)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            it.copy(guideWindowStartMs = cal.timeInMillis)
        }
    }

    fun resetGuideWindowToNow() {
        _state.update { it.copy(guideWindowStartMs = snappedCurrentHourMs()) }
    }

    fun filteredChannels(): List<IptvChannel> {
        val s = _state.value
        return when {
            s.selectedGroup == FAVORITES_GROUP ->
                s.channels.filter { it.id in s.favoriteChannelIds }
            s.selectedGroup.isBlank() -> s.channels
            else -> s.channels.filter { it.group == s.selectedGroup }
        }
    }

    /** Dedupe clones in category (keep richer EPG) — iOS Guide parity. */
    fun guideChannels(): List<IptvChannel> {
        val channels = filteredChannels()
        val epg = _state.value.epgByChannelId
        val best = LinkedHashMap<String, IptvChannel>()
        for (ch in channels) {
            val key = ch.name.lowercase().trim().ifBlank { ch.id }
            val existing = best[key]
            if (existing == null) {
                best[key] = ch
            } else {
                val ec = epg[existing.id]?.size ?: 0
                val nc = epg[ch.id]?.size ?: 0
                if (nc > ec || (nc == ec && ch.id < existing.id)) {
                    best[key] = ch
                }
            }
        }
        return best.values.toList()
    }

    fun programsFor(channelId: String): List<EpgProgram> =
        _state.value.epgByChannelId[channelId].orEmpty()

    fun nowTitle(channelId: String): String? =
        programsFor(channelId).nowOrNearest()?.title

    fun nextTitle(channelId: String): String? {
        val list = programsFor(channelId)
        val now = System.currentTimeMillis()
        return list.upNext(now)?.title
            ?: list.nowPlaying(now)?.let { cur ->
                list.filter { it.startMs >= cur.endMs }.minByOrNull { it.startMs }?.title
            }
    }

    /** Short EPG only for open category — populates Guide/Grid fast. */
    fun loadEpgForOpenCategory(force: Boolean = false) {
        val s = _state.value
        val cfg = s.playlist ?: return
        if (cfg.type != PlaylistType.XTREAM) {
            reloadEpgBulkBackground()
            return
        }
        val channels = filteredChannels()
        if (channels.isEmpty()) return
        val missing = if (force) {
            channels
        } else {
            channels.filter { s.epgByChannelId[it.id].isNullOrEmpty() }
        }
        if (missing.isEmpty()) return

        categoryEpgJob?.cancel()
        categoryEpgJob = viewModelScope.launch {
            _state.update {
                it.copy(
                    isAutoFillingEpg = true,
                    epgStatus = "Now/Next · ${missing.size} channels in ${s.selectedGroup.ifBlank { "category" }}…",
                )
            }
            val result = epg.loadShortEpgForChannels(
                channels = missing,
                config = cfg,
                onStatus = { status ->
                    _state.update { st -> st.copy(epgStatus = status, isAutoFillingEpg = true) }
                },
                onBatch = { batch ->
                    _state.update { st ->
                        st.copy(epgByChannelId = st.epgByChannelId + batch)
                    }
                },
            )
            val catTotal = filteredChannels().size.coerceAtLeast(1)
            _state.update { st ->
                val merged = st.epgByChannelId + result.programsByChannelId
                val catCovered = filteredChannels().count { !merged[it.id].isNullOrEmpty() }
                val note = if (catCovered == 0) {
                    "Now/Next empty for this category (common for movies) — waiting on full guide…"
                } else {
                    "Now/Next · $catCovered/$catTotal in category"
                }
                st.copy(
                    epgByChannelId = merged,
                    isAutoFillingEpg = false,
                    epgStatus = note,
                )
            }
            // Ensure bulk is running so timeline can fill from xmltv
            if (_state.value.epgByChannelId.let { map ->
                    filteredChannels().count { !map[it.id].isNullOrEmpty() }
                } < catTotal / 2
            ) {
                if (!_state.value.isLoadingEpg) {
                    reloadEpgBulkBackground()
                }
            }
        }
    }

    /** Bulk xmltv (disk-cached) + fill gaps in background. */
    fun reloadEpgBulkBackground() {
        val channels = _state.value.channels
        val cfg = _state.value.playlist
        if (channels.isEmpty() || cfg == null) return
        if (epgJob?.isActive == true) return
        epgJob = viewModelScope.launch {
            _state.update {
                it.copy(
                    isLoadingEpg = true,
                    bulkEpgStatus = "Full guide: starting…",
                )
            }
            val result = epg.loadBulkThenFill(
                channels = channels,
                config = cfg,
                onStatus = { status ->
                    _state.update { st -> st.copy(bulkEpgStatus = status, isLoadingEpg = true) }
                },
                onBatch = { batch ->
                    _state.update { st ->
                        val merged = st.epgByChannelId + batch
                        val cat = filteredChannels().count { !merged[it.id].isNullOrEmpty() }
                        val catTotal = filteredChannels().size
                        st.copy(
                            epgByChannelId = merged,
                            // Refresh category line when bulk maps open group
                            epgStatus = if (catTotal > 0 && cat > 0) {
                                "Category listings · $cat/$catTotal"
                            } else {
                                st.epgStatus
                            },
                        )
                    }
                },
            )
            _state.update { st ->
                val merged = st.epgByChannelId + result.programsByChannelId
                val covered = st.channels.count { !merged[it.id].isNullOrEmpty() }
                val cat = filteredChannels().count { !merged[it.id].isNullOrEmpty() }
                val catTotal = filteredChannels().size
                st.copy(
                    epgByChannelId = merged,
                    isLoadingEpg = false,
                    bulkEpgStatus = "Full guide ready · $covered/${st.channels.size} channels",
                    epgStatus = if (catTotal > 0) {
                        "Category listings · $cat/$catTotal"
                    } else {
                        st.epgStatus
                    },
                )
            }
        }
    }

    fun reloadEpg(force: Boolean = false) {
        if (force) {
            _state.update {
                it.copy(
                    epgByChannelId = emptyMap(),
                    epgStatus = null,
                    bulkEpgStatus = null,
                )
            }
            epgJob?.cancel()
            categoryEpgJob?.cancel()
        }
        loadEpgForOpenCategory(force = true)
        reloadEpgBulkBackground()
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
        _state.update {
            it.copy(
                playing = null,
                playUrl = null,
                playerMessage = null,
                playingGameId = null,
            )
        }
    }

    fun setShowScoresTicker(show: Boolean) {
        _state.update { it.copy(showScoresTicker = show) }
        viewModelScope.launch { prefs.setShowScoresTicker(show) }
    }

    fun toggleScoresTicker() {
        setShowScoresTicker(!_state.value.showScoresTicker)
    }

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
        val matches = matching.matchGameToChannels(game, _state.value.channels, limit = 1)
        val best = matches.firstOrNull()
        if (best != null) {
            play(best.channel, gameId = game.id)
        } else {
            openStreamPicker(game)
        }
    }

    companion object {
        const val GUIDE_HOURS = 12
        const val PX_PER_HOUR = 140

        fun factory(context: Context): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    val app = context.applicationContext
                    val epgCache = File(app.cacheDir, "epg")
                    return AppViewModel(
                        prefs = PrefsStore(app),
                        epg = EpgRepository(cacheDir = epgCache),
                    ) as T
                }
            }
    }
}
