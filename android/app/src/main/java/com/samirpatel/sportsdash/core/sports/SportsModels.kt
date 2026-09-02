package com.samirpatel.sportsdash.core.sports

enum class GameStatus { LIVE, UPCOMING, FINAL, POSTPONED, UNKNOWN }

data class TeamInfo(
    val id: String,
    val name: String,
    val abbreviation: String,
    val score: Int? = null,
    val logoUrl: String? = null,
    val shortName: String? = null,
    val colorHex: String? = null,
) {
    val displayScore: String get() = score?.toString() ?: "—"
    val rowLabel: String
        get() = shortName?.takeIf { it.isNotBlank() }
            ?: name.split(" ").lastOrNull()
            ?: abbreviation
}

data class SportLeague(
    val id: String,
    val label: String,
    val sportPath: String,
    val leaguePath: String,
    val section: String,
) {
    val scoreboardUrl: String
        get() = "https://site.api.espn.com/apis/site/v2/sports/$sportPath/$leaguePath/scoreboard"

    companion object {
        val ALL: List<SportLeague> = listOf(
            SportLeague("worldcup", "World Cup", "soccer", "fifa.world", "Soccer"),
            SportLeague("ucl", "Champions League", "soccer", "uefa.champions", "Soccer"),
            SportLeague("epl", "Premier League", "soccer", "eng.1", "Soccer"),
            SportLeague("mls", "MLS", "soccer", "usa.1", "Soccer"),
            SportLeague("laliga", "La Liga", "soccer", "esp.1", "Soccer"),
            SportLeague("bundesliga", "Bundesliga", "soccer", "ger.1", "Soccer"),
            SportLeague("seriea", "Serie A", "soccer", "ita.1", "Soccer"),
            SportLeague("ligue1", "Ligue 1", "soccer", "fra.1", "Soccer"),
            SportLeague("nfl", "NFL", "football", "nfl", "Football"),
            SportLeague("ncaaf", "NCAA Football", "football", "college-football", "Football"),
            SportLeague("nba", "NBA", "basketball", "nba", "Basketball"),
            SportLeague("mlb", "MLB", "baseball", "mlb", "Baseball"),
            SportLeague("nhl", "NHL", "hockey", "nhl", "Hockey"),
            SportLeague("pga", "PGA Tour", "golf", "pga", "Golf"),
            SportLeague("lpga", "LPGA", "golf", "lpga", "Golf"),
            SportLeague("ufc", "UFC", "mma", "ufc", "Combat"),
        )

        val DEFAULTS: List<SportLeague> = listOf(
            byId("worldcup")!!,
            byId("ucl")!!,
            byId("epl")!!,
            byId("nfl")!!,
            byId("nba")!!,
            byId("mlb")!!,
            byId("nhl")!!,
        )

        fun byId(id: String): SportLeague? = ALL.find { it.id == id }
    }
}

data class Game(
    val id: String,
    val league: SportLeague,
    val home: TeamInfo,
    val away: TeamInfo,
    val status: GameStatus,
    val startTimeMs: Long,
    val statusDetail: String? = null,
    val clock: String? = null,
    val period: String? = null,
    val venue: String? = null,
    val eventName: String? = null,
    val broadcasts: List<String> = emptyList(),
) {
    val isLive get() = status == GameStatus.LIVE
    val isFinal get() = status == GameStatus.FINAL
    val isUpcoming: Boolean
        get() {
            if (status == GameStatus.UPCOMING) return true
            if (status == GameStatus.LIVE || status == GameStatus.FINAL || status == GameStatus.POSTPONED) {
                return false
            }
            return startTimeMs > System.currentTimeMillis() - 15 * 60_000L
        }

    val matchupLabel: String
        get() = "${away.abbreviation} @ ${home.abbreviation}"

    val statusLine: String
        get() {
            when {
                isFinal -> return "FINAL"
                isUpcoming -> return formatStart(startTimeMs, statusDetail)
                !statusDetail.isNullOrBlank() &&
                    statusDetail.lowercase() !in setOf("in progress", "live") -> return statusDetail
                !clock.isNullOrBlank() -> return clock
                else -> return "LIVE"
            }
        }

    companion object {
        private fun formatStart(ms: Long, detail: String?): String {
            if (ms <= 0L) return detail ?: "TBD"
            val cal = java.util.Calendar.getInstance()
            val now = java.util.Calendar.getInstance()
            cal.timeInMillis = ms
            val tf = java.text.SimpleDateFormat("h:mm a", java.util.Locale.getDefault())
            return when {
                now.get(java.util.Calendar.YEAR) == cal.get(java.util.Calendar.YEAR) &&
                    now.get(java.util.Calendar.DAY_OF_YEAR) == cal.get(java.util.Calendar.DAY_OF_YEAR) ->
                    tf.format(cal.time)
                else -> {
                    val df = java.text.SimpleDateFormat("EEE h:mm a", java.util.Locale.getDefault())
                    df.format(cal.time)
                }
            }
        }
    }
}

/** League shelf under a sport bucket (iOS LeagueShelf parity). */
data class LeagueShelf(
    val key: String,
    val title: String,
    val sportKey: String,
    val sportTitle: String,
    val games: List<Game>,
)

/** Sport bucket for collapsible Scores dashboard (iOS SportScoreSection parity). */
data class SportScoreSection(
    val sportKey: String,
    val sportTitle: String,
    val emoji: String,
    val leagues: List<LeagueShelf>,
) {
    val gameCount: Int get() = leagues.sumOf { it.games.size }
    val liveCount: Int get() = leagues.sumOf { shelf -> shelf.games.count { it.isLive } }
}

/** Pure row data for TV Netflix browse rails (one per league shelf). */
data class TvScoreRail(
    val key: String,
    val title: String,
    val emoji: String,
    val games: List<Game>,
)

/** Typed per-league result from fetch (analogous to Apple LeagueFetchResult).
 * Distinguishes legitimate successful-empty (0 games from 2xx) vs network/HTTP/parse failures.
 */
data class LeagueFetchResult(
    val league: SportLeague,
    val games: List<Game>,
    val successfulBoards: Int,
    val failedBoards: Int,
    val defaultSucceeded: Boolean,
) {
    val allBoardsFailedForLeague: Boolean get() = successfulBoards == 0 && failedBoards > 0
}

/** Aggregate fetch result (analogous to Apple ScoreboardFetchResult).
 * allBoardsFailed: total outage (preserve prior + set error)
 * hasPartialFailures: some leagues failed (merge retain prior for those leagues + warning/status)
 */
data class ScoreboardFetchResult(
    val games: List<Game>,
    val successfulBoards: Int,
    val failedBoards: Int,
    val failedLeagues: Set<SportLeague> = emptySet(),
) {
    val allBoardsFailed: Boolean get() = successfulBoards == 0 && (failedLeagues.isNotEmpty() || failedBoards > 0)
    val hasPartialFailures: Boolean get() = successfulBoards > 0 && failedLeagues.isNotEmpty()
}

/** Group games sport → league in stable [SportLeague.ALL] order (iOS ScoreboardGrouping). */
object ScoreboardGrouping {
    fun sportEmoji(sportPath: String): String = when (sportPath) {
        "football" -> "🏈"
        "basketball" -> "🏀"
        "baseball" -> "⚾"
        "hockey" -> "🏒"
        "soccer" -> "⚽"
        "tennis" -> "🎾"
        "golf" -> "⛳"
        "racing" -> "🏎️"
        "mma" -> "🥊"
        "rugby" -> "🏉"
        else -> "🏟️"
    }

    fun sportSections(
        games: List<Game>,
        favoriteTeamIds: Set<String> = emptySet(),
    ): List<SportScoreSection> {
        if (games.isEmpty()) return emptyList()
        val buckets = games.groupBy { it.league }
        val shelves = ArrayList<LeagueShelf>()
        for (league in SportLeague.ALL) {
            val list = buckets[league] ?: continue
            if (list.isEmpty()) continue
            val sorted = list.sortedWith(
                compareBy<Game> { g ->
                    if (favoriteTeamIds.isNotEmpty() &&
                        (g.home.id in favoriteTeamIds || g.away.id in favoriteTeamIds)
                    ) 0 else 1
                }
                    .thenByDescending { it.isLive }
                    .thenBy { it.startTimeMs },
            )
            shelves.add(
                LeagueShelf(
                    key = league.id,
                    title = league.label,
                    sportKey = league.sportPath,
                    sportTitle = league.section,
                    games = sorted,
                ),
            )
        }
        for ((league, list) in buckets) {
            if (shelves.any { it.key == league.id } || list.isEmpty()) continue
            val sorted = list.sortedWith(
                compareBy<Game> { g ->
                    if (favoriteTeamIds.isNotEmpty() &&
                        (g.home.id in favoriteTeamIds || g.away.id in favoriteTeamIds)
                    ) 0 else 1
                }
                    .thenByDescending { it.isLive }
                    .thenBy { it.startTimeMs },
            )
            shelves.add(
                LeagueShelf(
                    key = league.id,
                    title = league.label,
                    sportKey = league.sportPath,
                    sportTitle = league.section,
                    games = sorted,
                ),
            )
        }
        val sections = ArrayList<SportScoreSection>()
        var currentKey: String? = null
        var currentTitle = ""
        var currentEmoji = "🏟️"
        var currentLeagues = ArrayList<LeagueShelf>()
        fun flush() {
            val key = currentKey
            if (key != null && currentLeagues.isNotEmpty()) {
                sections.add(
                    SportScoreSection(
                        sportKey = key,
                        sportTitle = currentTitle,
                        emoji = currentEmoji,
                        leagues = currentLeagues.toList(),
                    ),
                )
            }
        }
        for (shelf in shelves) {
            if (currentKey != shelf.sportKey) {
                flush()
                currentKey = shelf.sportKey
                currentTitle = shelf.sportTitle
                currentEmoji = sportEmoji(shelf.sportKey)
                currentLeagues = ArrayList()
            }
            currentLeagues.add(shelf)
        }
        flush()
        return sections
    }

    /**
     * Pure grouping for UPCOMING filter (TDD).
     * Every selected league must be represented (with empty games list for "None scheduled").
     * Regular sportSections() intentionally skips empty (for Live/Final).
     * Matches Apple behavior for Upcoming empty shelves.
     */
    fun upcomingSportSections(
        games: List<Game>,
        selectedLeagueIds: Set<String>,
        favoriteTeamIds: Set<String> = emptySet(),
    ): List<SportScoreSection> {
        val buckets = games.groupBy { it.league }
        val shelves = ArrayList<LeagueShelf>()

        // First: all selected leagues in ALL order, include even if no games
        for (league in SportLeague.ALL) {
            if (league.id !in selectedLeagueIds) continue
            val list = buckets[league] ?: emptyList()
            val sorted = if (list.isNotEmpty()) {
                list.sortedWith(
                    compareBy<Game> { g ->
                        if (favoriteTeamIds.isNotEmpty() &&
                            (g.home.id in favoriteTeamIds || g.away.id in favoriteTeamIds)
                        ) 0 else 1
                    }
                        .thenByDescending { it.isLive }
                        .thenBy { it.startTimeMs },
                )
            } else emptyList()
            shelves.add(
                LeagueShelf(
                    key = league.id,
                    title = league.label,
                    sportKey = league.sportPath,
                    sportTitle = league.section,
                    games = sorted,
                ),
            )
        }

        // Any extra selected not in ALL? (should not but for completeness)
        for ((league, list) in buckets) {
            if (league.id !in selectedLeagueIds) continue
            if (shelves.any { it.key == league.id } || list.isEmpty()) continue
            val sorted = list.sortedWith(
                compareBy<Game> { g ->
                    if (favoriteTeamIds.isNotEmpty() &&
                        (g.home.id in favoriteTeamIds || g.away.id in favoriteTeamIds)
                    ) 0 else 1
                }
                    .thenByDescending { it.isLive }
                    .thenBy { it.startTimeMs },
            )
            shelves.add(
                LeagueShelf(
                    key = league.id,
                    title = league.label,
                    sportKey = league.sportPath,
                    sportTitle = league.section,
                    games = sorted,
                ),
            )
        }

        // Build sections same as sportSections (sport buckets)
        val sections = ArrayList<SportScoreSection>()
        var currentKey: String? = null
        var currentTitle = ""
        var currentEmoji = "🏟️"
        var currentLeagues = ArrayList<LeagueShelf>()
        fun flush() {
            val key = currentKey
            if (key != null && currentLeagues.isNotEmpty()) {
                sections.add(
                    SportScoreSection(
                        sportKey = key,
                        sportTitle = currentTitle,
                        emoji = currentEmoji,
                        leagues = currentLeagues.toList(),
                    ),
                )
            }
        }
        for (shelf in shelves) {
            if (currentKey != shelf.sportKey) {
                flush()
                currentKey = shelf.sportKey
                currentTitle = shelf.sportTitle
                currentEmoji = sportEmoji(shelf.sportKey)
                currentLeagues = ArrayList()
            }
            currentLeagues.add(shelf)
        }
        flush()
        return sections
    }


    /**
     * Pure aggregate merge/result helper (TDD: RED then GREEN).
     * For partial failure: retain prior games for *failed* leagues only (do not destructive [] replace).
     * Legit successful empty (from API) for a league does not retain its prior.
     * all failure handled upstream in VM with gen guard + error + prior preserve.
     */
    fun mergeWithRetainedPrevious(
        fresh: List<Game>,
        previous: List<Game>,
        failedLeagues: Set<SportLeague>
    ): List<Game> {
        if (failedLeagues.isEmpty()) return fresh
        val freshIds = fresh.mapTo(mutableSetOf()) { it.id }
        val retained = previous.filter { g ->
            g.league in failedLeagues && g.id !in freshIds
        }
        return fresh + retained
    }

    /**
     * Pure TV browse row transformation: one rail per `section.leagues` shelf.
     * Uses league title (e.g. "Premier League", "MLS") so empty upcoming leagues
     * produce explicit titled rail + "None scheduled".
     * Preserves sport grouping order (leagues under same sport are consecutive).
     * For Live/Final, upstream sportSections() omits empty leagues so no unnecessary rails.
     * My Games rail is constructed separately in ScoresTVBrowse (always first).
     */
    fun tvScoreRails(sections: List<SportScoreSection>): List<TvScoreRail> =
        sections.flatMap { section ->
            section.leagues.map { shelf ->
                TvScoreRail(
                    key = "rail-${section.sportKey}-${shelf.key}",
                    title = shelf.title,
                    emoji = section.emoji,
                    games = shelf.games,
                )
            }
        }

    fun warningMessageForFailedLeagues(failedLeagues: Set<SportLeague>): String? {
        if (failedLeagues.isEmpty()) return null
        val names = failedLeagues.map { it.label }.sorted()
        val joined = names.joinToString(", ")
        return "$joined could not refresh. Other scores are current."
    }

    /**
     * Pure helpers for ordering/dedup (extracted for testability and reuse).
     */
    internal fun statusRank(s: GameStatus): Int = when (s) {
        GameStatus.LIVE -> 0
        GameStatus.UPCOMING -> 1
        GameStatus.POSTPONED -> 2
        GameStatus.FINAL -> 3
        GameStatus.UNKNOWN -> 4
    }

    internal fun prefer(a: Game, b: Game): Game =
        if (statusRank(a.status) <= statusRank(b.status)) a else b

    /**
     * Pure aggregation semantics for combining per-league fetch results.
     * Testable independently of HTTP.
     * Only increments successful for completed HTTP + successful parse (blank/missing events = fail; explicit events=[] ok empty).
     * This centralizes the counting + game merge logic.
     */
    fun aggregateResults(results: List<LeagueFetchResult>): ScoreboardFetchResult {
        val byId = linkedMapOf<String, Game>()
        var successfulBoards = 0
        var failedBoards = 0
        val failedLeagues = mutableSetOf<SportLeague>()

        for (r in results) {
            successfulBoards += r.successfulBoards
            failedBoards += r.failedBoards
            if (!r.defaultSucceeded) {
                failedLeagues.add(r.league)
            }
            for (g in r.games) {
                val prev = byId[g.id]
                byId[g.id] = if (prev == null) g else prefer(prev, g)
            }
        }
        val sorted = byId.values.toList().sortedWith(
            compareBy<Game> { statusRank(it.status) }
                .thenBy { it.startTimeMs },
        )
        return ScoreboardFetchResult(
            games = sorted,
            successfulBoards = successfulBoards,
            failedBoards = failedBoards,
            failedLeagues = failedLeagues
        )
    }
}
