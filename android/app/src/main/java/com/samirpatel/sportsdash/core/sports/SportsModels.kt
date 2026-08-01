package com.samirpatel.sportsdash.core.sports

enum class GameStatus { LIVE, UPCOMING, FINAL, POSTPONED, UNKNOWN }

data class TeamInfo(
    val id: String,
    val name: String,
    val abbreviation: String,
    val score: Int? = null,
    val logoUrl: String? = null,
    val shortName: String? = null,
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
