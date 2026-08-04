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
import com.samirpatel.sportsdash.core.ratings.MovieDetection
import com.samirpatel.sportsdash.core.ratings.MovieRating
import com.samirpatel.sportsdash.core.ratings.MovieRatingsRepository
import com.samirpatel.sportsdash.core.ratings.MovieTitleParser
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.core.sports.GameStatus
import com.samirpatel.sportsdash.core.sports.ScoreboardGrouping
import com.samirpatel.sportsdash.core.sports.SportLeague
import com.samirpatel.sportsdash.core.sports.SportScoreSection
import com.samirpatel.sportsdash.core.sports.TeamInfo
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
    /** ESPN team ids starred (iOS favoriteTeamIds parity). */
    val favoriteTeamIds: Set<String> = emptySet(),
    /** Full starred teams (logos/names) for rail + picker. */
    val favoriteTeams: List<TeamInfo> = emptyList(),
    val cleanUpNames: Boolean = true,
    /** Guide filter: movie-like now-playing only. */
    val moviesNow: Boolean = false,

    /**
     * Mini-player over tabs (iOS floating player).
     * When set with [playUrl], fullscreen is dismissed but playback continues.
     */
    val floating: Boolean = false,

    /** cacheKey → rating for Guide/Player chips. */
    val movieRatings: Map<String, MovieRating> = emptyMap(),
    val movieRatingsLoading: Set<String> = emptySet(),
    val omdbKeyPresent: Boolean = false,
    val tmdbKeyPresent: Boolean = false,
)

class AppViewModel(
    private val prefs: PrefsStore,
    private val iptv: IptvRepository = IptvRepository(),
    private val sports: SportsRepository = SportsRepository(),
    private val matching: MatchingService = MatchingService(),
    private val epg: EpgRepository,
    private val ratingsRepo: MovieRatingsRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(AppUiState())
    val state: StateFlow<AppUiState> = _state.asStateFlow()

    private var omdbKey: String? = null
    private var tmdbKey: String? = null
    private val ratingsAttempted = mutableSetOf<String>()


    private var epgJob: Job? = null
    private var categoryEpgJob: Job? = null

    init {
        // Cold-start: restore playlist ASAP so Settings/Guide don't look "logged out"
        // after an APK update while DataStore is still warming up.
        viewModelScope.launch {
            val peeked = runCatching { prefs.peekPlaylist() }.getOrNull()
            if (peeked != null && _state.value.playlist == null) {
                _state.update { it.copy(playlist = peeked) }
                if (_state.value.channels.isEmpty()) {
                    refreshChannels()
                }
            }
            prefs.playlistFlow.collect { cfg ->
                _state.update { it.copy(playlist = cfg) }
                if (cfg != null && _state.value.channels.isEmpty()) {
                    refreshChannels()
                }
            }
        }
        viewModelScope.launch {
            // Cold-start ticker preference before first player open (FB.11).
            runCatching {
                val peeked = prefs.peekShowScoresTicker()
                _state.update { it.copy(showScoresTicker = peeked) }
            }
            prefs.showScoresTickerFlow.collect { show ->
                _state.update { it.copy(showScoresTicker = show) }
            }
        }
        viewModelScope.launch {
            prefs.favoriteChannelIdsFlow.collect { ids ->
                _state.update { it.copy(favoriteChannelIds = ids) }
            }
        }
        viewModelScope.launch {
            prefs.favoriteTeamsFlow.collect { teams ->
                _state.update {
                    it.copy(
                        favoriteTeams = teams,
                        favoriteTeamIds = teams.map { t -> t.id }.toSet().ifEmpty {
                            // keep ids if meta empty (legacy)
                            it.favoriteTeamIds
                        },
                    )
                }
            }
        }
        viewModelScope.launch {
            prefs.favoriteTeamIdsFlow.collect { ids ->
                _state.update { s ->
                    if (s.favoriteTeams.isNotEmpty()) s
                    else s.copy(favoriteTeamIds = ids)
                }
            }
        }
        viewModelScope.launch {
            prefs.cleanUpNamesFlow.collect { on ->
                _state.update { it.copy(cleanUpNames = on) }
            }
        }
        viewModelScope.launch {
            prefs.moviesNowFlow.collect { on ->
                _state.update { it.copy(moviesNow = on) }
            }
        }
        viewModelScope.launch {
            prefs.omdbKeyFlow.collect { key ->
                omdbKey = key
                _state.update { it.copy(omdbKeyPresent = !key.isNullOrBlank()) }
            }
        }
        viewModelScope.launch {
            prefs.tmdbKeyFlow.collect { key ->
                tmdbKey = key
                _state.update { it.copy(tmdbKeyPresent = !key.isNullOrBlank()) }
            }
        }
        refreshScores()
    }

    fun saveXtream(name: String, serverUrl: String, user: String, pass: String) {
        val existing = _state.value.playlist
        // Blank password = keep previously saved password (Settings never echoes it).
        val resolvedPass = when {
            pass.isNotBlank() -> pass
            existing != null &&
                existing.type == PlaylistType.XTREAM &&
                existing.password.isNotBlank() -> existing.password
            else -> pass
        }
        if (resolvedPass.isBlank()) {
            _state.update {
                it.copy(
                    channelError =
                        "Password required (or leave blank only when one is already saved)",
                )
            }
            return
        }
        val cfg = PlaylistConfig(
            id = existing?.id?.takeIf { it.isNotBlank() } ?: java.util.UUID.randomUUID().toString(),
            name = name.ifBlank { "Xtream" },
            type = PlaylistType.XTREAM,
            host = serverUrl.trim(),
            username = user.trim(),
            password = resolvedPass,
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
        val existing = _state.value.playlist
        val cfg = PlaylistConfig(
            id = existing?.id?.takeIf { it.isNotBlank() } ?: java.util.UUID.randomUUID().toString(),
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
            // Paint disk cache first (iOS cold-start parity)
            if (_state.value.channels.isEmpty()) {
                prefs.getChannelCache()?.let { (cached, cats) ->
                    if (cached.isNotEmpty()) {
                        val previous = _state.value.selectedGroup
                        val selected = when {
                            previous.isNotBlank() && (previous == FAVORITES_GROUP || previous in cats) -> previous
                            cats.isNotEmpty() -> cats.first()
                            else -> ""
                        }
                        _state.update {
                            it.copy(
                                channels = cached,
                                groups = cats,
                                selectedGroup = selected,
                                channelStatus = "Cached ${cached.size} channels · refreshing…",
                            )
                        }
                    }
                }
            }
            _state.update {
                it.copy(
                    isLoadingChannels = true,
                    channelError = null,
                    channelStatus = it.channelStatus ?: "Loading ${cfg.describe()}…",
                )
            }
            iptv.loadChannels(cfg).onSuccess { loaded ->
                val channels = loaded.channels
                val groups = loaded.categoryOrder
                val previous = _state.value.selectedGroup
                val selected = when {
                    previous.isNotBlank() && (previous == FAVORITES_GROUP || previous in groups) -> previous
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
                prefs.saveChannelCache(channels, groups)
                reloadEpgBulkBackground()
                loadEpgForOpenCategory(force = false)
                prefetchMovieRatings()
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
        prefetchMovieRatings()
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

    fun isTeamFavorite(teamId: String): Boolean =
        teamId in _state.value.favoriteTeamIds

    fun gameHasFavoriteTeam(game: Game): Boolean {
        val favs = _state.value.favoriteTeamIds
        return game.home.id in favs || game.away.id in favs
    }

    fun toggleTeamFavorite(teamId: String) {
        if (teamId.isBlank()) return
        val current = _state.value.favoriteTeams.toMutableList()
        val idx = current.indexOfFirst { it.id == teamId }
        if (idx >= 0) {
            current.removeAt(idx)
        } else {
            // Prefer rich row from live boards if present
            val fromBoard = _state.value.games.asSequence()
                .flatMap { sequenceOf(it.home, it.away) }
                .firstOrNull { it.id == teamId }
            current.add(
                fromBoard ?: TeamInfo(id = teamId, name = teamId, abbreviation = teamId.take(3)),
            )
        }
        persistFavoriteTeams(current)
    }

    fun toggleTeamFavorite(team: TeamInfo) {
        if (team.id.isBlank()) return
        val current = _state.value.favoriteTeams.toMutableList()
        val idx = current.indexOfFirst { it.id == team.id }
        if (idx >= 0) current.removeAt(idx)
        else current.add(team)
        persistFavoriteTeams(current)
    }

    private fun persistFavoriteTeams(teams: List<TeamInfo>) {
        val distinct = teams.filter { it.id.isNotBlank() }.distinctBy { it.id }
        _state.update {
            it.copy(
                favoriteTeams = distinct,
                favoriteTeamIds = distinct.map { t -> t.id }.toSet(),
            )
        }
        viewModelScope.launch { prefs.setFavoriteTeams(distinct) }
    }

    suspend fun loadTeamsForLeague(league: SportLeague): List<TeamInfo> {
        return runCatching { sports.fetchTeams(league) }.getOrDefault(emptyList())
    }

    fun sportGroupsForPicker(): List<Pair<String, List<SportLeague>>> {
        return SportLeague.ALL
            .groupBy { it.section }
            .entries
            .sortedBy { it.key }
            .map { it.key to it.value }
    }

    fun setCleanUpNames(enabled: Boolean) {
        _state.update { it.copy(cleanUpNames = enabled) }
        viewModelScope.launch { prefs.setCleanUpNames(enabled) }
    }

    fun setMoviesNow(enabled: Boolean) {
        _state.update { it.copy(moviesNow = enabled) }
        viewModelScope.launch { prefs.setMoviesNow(enabled) }
        if (enabled) prefetchMovieRatings()
    }

    fun setOmdbKey(key: String) {
        viewModelScope.launch {
            prefs.setOmdbKey(key)
            ratingsAttempted.clear()
            prefetchMovieRatings()
        }
    }

    fun setTmdbKey(key: String) {
        viewModelScope.launch {
            prefs.setTmdbKey(key)
            ratingsAttempted.clear()
            prefetchMovieRatings()
        }
    }

    fun ratingForTitle(title: String?): MovieRating? {
        if (title.isNullOrBlank()) return null
        val key = MovieTitleParser.cacheKey(title)
        return _state.value.movieRatings[key]
    }

    fun isRatingLoading(title: String?): Boolean {
        if (title.isNullOrBlank()) return false
        return MovieTitleParser.cacheKey(title) in _state.value.movieRatingsLoading
    }

    fun requestMovieRating(
        title: String?,
        category: String? = null,
        channelGroup: String? = null,
        channelName: String? = null,
        forceMovie: Boolean = false,
    ) {
        if (title.isNullOrBlank()) return
        val candidate = MovieDetection.isMovieCandidate(
            title = title,
            category = category,
            channelGroup = channelGroup,
            channelName = channelName,
            forceMovie = forceMovie,
        )
        if (!candidate) return
        val key = MovieTitleParser.cacheKey(title)
        val s = _state.value
        if (s.movieRatings[key] != null) return
        if (key in s.movieRatingsLoading) return
        if (key in ratingsAttempted) return
        if (omdbKey.isNullOrBlank() && tmdbKey.isNullOrBlank()) return

        ratingsAttempted.add(key)
        _state.update { it.copy(movieRatingsLoading = it.movieRatingsLoading + key) }
        viewModelScope.launch {
            val result = ratingsRepo.rating(
                rawTitle = title,
                isMovieHint = true,
                omdbKey = omdbKey,
                tmdbKey = tmdbKey,
            )
            _state.update { st ->
                val loading = st.movieRatingsLoading - key
                if (result != null) {
                    st.copy(
                        movieRatings = st.movieRatings + (key to result),
                        movieRatingsLoading = loading,
                    )
                } else {
                    st.copy(movieRatingsLoading = loading)
                }
            }
        }
    }

    fun prefetchMovieRatings() {
        val channels = guideChannels().take(16)
        for (ch in channels) {
            val now = programsFor(ch.id).nowOrNearest() ?: continue
            val group = ch.group ?: _state.value.selectedGroup
            val force = listOf(now.category, group, ch.name)
                .filterNotNull()
                .any {
                    val l = it.lowercase()
                    l.contains("movie") || l.contains("cinema") || l.contains("film")
                }
            requestMovieRating(
                title = now.title,
                category = now.category,
                channelGroup = group,
                channelName = ch.name,
                forceMovie = force,
            )
        }
    }

    fun displayChannelName(raw: String): String =
        com.samirpatel.sportsdash.core.util.ChannelNameCleanup.displayName(
            raw,
            enabled = _state.value.cleanUpNames,
        )

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
        var channels = filteredChannels()
        if (_state.value.moviesNow) {
            channels = channels.filter { ch ->
                val now = programsFor(ch.id).nowOrNearest()
                isMovieLike(now?.title, now?.category, ch)
            }
        }
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
                floating = false,
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
                floating = false,
            )
        }
    }

    /** Leave fullscreen; keep playing as mini overlay (iOS pop-out). */
    fun popOutPlayer() {
        if (_state.value.playing == null || _state.value.playUrl == null) return
        _state.update { it.copy(floating = true) }
    }

    fun expandFloatingPlayer() {
        _state.update { it.copy(floating = false) }
    }

    fun dismissFloatingPlayer() {
        stopPlayback()
    }

    private fun isMovieLike(title: String?, category: String?, channel: IptvChannel): Boolean {
        val blob = listOfNotNull(title, category, channel.group, channel.name)
            .joinToString(" ")
            .lowercase()
        if (blob.contains("sport") || blob.contains("news") || blob.contains("weather")) return false
        return blob.contains("movie") || blob.contains("cinema") || blob.contains("film") ||
            blob.contains("hollywood") || Regex("""\b(19|20)\d{2}\b""").containsMatchIn(blob)
    }

    fun setShowScoresTicker(show: Boolean) {
        _state.update { it.copy(showScoresTicker = show) }
        viewModelScope.launch {
            // Survive leaving player / process death (FB.11).
            kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {
                runCatching { prefs.setShowScoresTicker(show) }
            }
        }
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
        val base = when (s.scoresFilter) {
            ScoresFilter.LIVE -> s.games.filter { it.isLive }
            ScoresFilter.UPCOMING -> s.games.filter { it.isUpcoming }
            ScoresFilter.FINAL -> s.games.filter { it.isFinal || it.status == GameStatus.FINAL }
        }
        // Pin favorite-team games first (teams only — S-PARITY.FAV.2 / FAV.3).
        return pinFavoriteGames(base)
    }

    fun gamesByLeague(): Map<SportLeague, List<Game>> {
        val filtered = filteredGames()
        val buckets = filtered.groupBy { it.league }
        val ordered = linkedMapOf<SportLeague, List<Game>>()
        val leagueOrder = try {
            SportLeague.ALL + buckets.keys.filter { it !in SportLeague.ALL }.sortedBy { it.label }
        } catch (_: Throwable) {
            buckets.keys.sortedBy { it.label }
        }
        for (league in leagueOrder) {
            val list = buckets[league] ?: continue
            if (list.isEmpty() || league in ordered) continue
            ordered[league] = pinFavoriteGames(list)
        }
        return ordered
    }

    /** Sport → league shelves for collapsible Scores dashboard (iOS parity). */
    fun sportScoreSections(): List<SportScoreSection> {
        return ScoreboardGrouping.sportSections(filteredGames())
    }

    fun liveGamesForTicker(): List<Game> {
        // Favorites lead the strip so user can cycle starred teams after switching games.
        val favs = _state.value.favoriteTeamIds
        val currentId = _state.value.playingGameId
        val live = _state.value.games.filter { it.isLive }
        fun isFav(g: Game): Boolean =
            favs.isNotEmpty() && (g.home.id in favs || g.away.id in favs)
        return live.sortedWith(
            compareBy<Game> { g ->
                when {
                    isFav(g) && g.id == currentId -> 0
                    isFav(g) -> 1
                    g.id == currentId -> 2
                    else -> 3
                }
            }.thenBy { it.startTimeMs },
        )
    }

    fun liveGames(): List<Game> {
        return pinFavoriteGames(_state.value.games.filter { it.isLive })
    }

    /**
     * Variant A "My Games": games involving a starred team under the active filter.
     * Shown above the full collapsible board (not a separate favorite-games product).
     */
    fun myGamesPin(): List<Game> {
        val favs = _state.value.favoriteTeamIds
        if (favs.isEmpty()) return emptyList()
        return pinFavoriteGames(filteredGames().filter { gameHasFavoriteTeam(it) })
    }

    /** Horizontal favorite-team rail with ESPN logos when present. */
    fun favoriteTeamsRail(): List<TeamInfo> {
        val stored = _state.value.favoriteTeams
        if (stored.isNotEmpty()) {
            // Enrich logos from live board when meta lacks them
            val board = linkedMapOf<String, TeamInfo>()
            for (g in _state.value.games) {
                board.putIfAbsent(g.home.id, g.home)
                board.putIfAbsent(g.away.id, g.away)
            }
            return stored.map { t ->
                val b = board[t.id]
                if (b != null && t.logoUrl.isNullOrBlank() && !b.logoUrl.isNullOrBlank()) b else t
            }
        }
        val ids = _state.value.favoriteTeamIds
        if (ids.isEmpty()) return emptyList()
        val byId = linkedMapOf<String, TeamInfo>()
        for (g in _state.value.games) {
            if (g.home.id in ids) byId.putIfAbsent(g.home.id, g.home)
            if (g.away.id in ids) byId.putIfAbsent(g.away.id, g.away)
        }
        return ids.mapNotNull { byId[it] }
    }

    /** Favorites first, then earlier start. */
    private fun pinFavoriteGames(games: List<Game>): List<Game> {
        val favs = _state.value.favoriteTeamIds
        if (favs.isEmpty()) {
            return games.sortedBy { it.startTimeMs }
        }
        return games.sortedWith(
            compareBy<Game> { g ->
                if (g.home.id in favs || g.away.id in favs) 0 else 1
            }.thenBy { it.startTimeMs },
        )
    }

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

    /**
     * Ticker tap: always open stream picker (home/away/4K) so user can choose.
     * Auto-pick hid the menu and left users stuck if the first match failed.
     */
    fun playFromTicker(game: Game) {
        openStreamPicker(game)
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
                    val ratingsCache = File(app.cacheDir, "ratings")
                    return AppViewModel(
                        prefs = PrefsStore(app),
                        epg = EpgRepository(cacheDir = epgCache),
                        ratingsRepo = MovieRatingsRepository(cacheDir = ratingsCache),
                    ) as T
                }
            }
    }
}
