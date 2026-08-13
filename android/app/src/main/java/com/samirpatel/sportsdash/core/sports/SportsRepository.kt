package com.samirpatel.sportsdash.core.sports

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * ESPN public scoreboard client — mirrors iOS SportsAPI.
 */
class SportsRepository(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build(),
) {
    companion object {
        /**
         * ESPN team ids collide across sports (NFL 27 = Buccaneers, MLB 27 = Rockies).
         * Always scope with league id: `nfl:27`.
         */
        fun stableTeamId(league: SportLeague, rawId: String): String {
            val raw = rawId.trim()
            if (raw.isEmpty()) return ""
            if (raw.contains(":")) return raw
            return "${league.id}:$raw"
        }

        fun jsonId(obj: org.json.JSONObject, key: String): String {
            if (!obj.has(key) || obj.isNull(key)) return ""
            return when (val v = obj.get(key)) {
                is Number -> v.toLong().toString()
                else -> v.toString().trim()
            }
        }
    }
    suspend fun fetchGames(leagues: List<SportLeague>): ScoreboardFetchResult = withContext(Dispatchers.IO) {
        coroutineScope {
            val results: List<LeagueFetchResult> = leagues.map { league ->
                async { fetchLeagueResult(league) }
            }.awaitAll()

            var agg = ScoreboardGrouping.aggregateResults(results)
            if (agg.failedLeagues.isNotEmpty()) {
                delay(500L)
                val toRetry = agg.failedLeagues.toList()
                val retryResults: List<LeagueFetchResult> = toRetry.map { league ->
                    async { fetchLeagueResult(league, onlyDefault = true) }
                }.awaitAll()
                // Merge retry with original: keep prior range/default games; only update failure/default flags.
                val leagueToRes = results.associateBy { it.league }.toMutableMap()
                for (rr in retryResults) {
                    val prev = leagueToRes[rr.league]
                    if (prev == null) {
                        leagueToRes[rr.league] = rr
                    } else {
                        val byId = LinkedHashMap<String, Game>()
                        for (g in prev.games) byId[g.id] = g
                        for (g in rr.games) byId[g.id] = g
                        leagueToRes[rr.league] = LeagueFetchResult(
                            league = rr.league,
                            games = byId.values.toList(),
                            successfulBoards = prev.successfulBoards + rr.successfulBoards,
                            failedBoards = if (prev.defaultSucceeded || rr.defaultSucceeded) prev.failedBoards else rr.failedBoards,
                            defaultSucceeded = prev.defaultSucceeded || rr.defaultSucceeded,
                        )
                    }
                }
                agg = ScoreboardGrouping.aggregateResults(leagueToRes.values.toList())
            }
            agg
        }
    }

    /**
     * Full roster for favorite-team picker.
     * ESPN: /sports/{sport}/{league}/teams
     */
    suspend fun fetchTeams(league: SportLeague): List<TeamInfo> = withContext(Dispatchers.IO) {
        val url = "https://site.api.espn.com/apis/site/v2/sports/${league.sportPath}/${league.leaguePath}/teams?limit=400"
        val body = runCatching { httpGet(url) }.getOrDefault("")
        if (body.isBlank()) return@withContext emptyList()
        parseTeams(body, league)
    }

    private fun parseTeams(body: String, league: SportLeague): List<TeamInfo> {
        val root = runCatching { JSONObject(body) }.getOrNull() ?: return emptyList()
        val sports = root.optJSONArray("sports") ?: return emptyList()
        val out = ArrayList<TeamInfo>()
        val seen = HashSet<String>()
        for (si in 0 until sports.length()) {
            val sport = sports.optJSONObject(si) ?: continue
            val leagues = sport.optJSONArray("leagues") ?: continue
            for (li in 0 until leagues.length()) {
                val leagueJson = leagues.optJSONObject(li) ?: continue
                val teams = leagueJson.optJSONArray("teams") ?: continue
                for (ti in 0 until teams.length()) {
                    val wrap = teams.optJSONObject(ti) ?: continue
                    val team = wrap.optJSONObject("team") ?: wrap
                    val raw = jsonId(team, "id").ifBlank { jsonId(team, "uid") }
                    // Never fall back to abbreviation — TB collides Bucs vs Rays.
                    if (raw.isBlank()) continue
                    // Use SportLeague param (not JSONObject) — ids are league-scoped.
                    val id = stableTeamId(league, raw)
                    if (id.isBlank() || !seen.add(id)) continue
                    val logos = team.optJSONArray("logos")
                    var logo: String? = null
                    if (logos != null && logos.length() > 0) {
                        logo = logos.optJSONObject(0)?.optString("href")?.takeIf { it.isNotBlank() }
                    }
                    if (logo.isNullOrBlank()) {
                        logo = team.optString("logo").takeIf { it.isNotBlank() }
                    }
                    out.add(
                        TeamInfo(
                            id = id,
                            name = team.optString("displayName").ifBlank {
                                team.optString("name").ifBlank { team.optString("shortDisplayName") }
                            },
                            abbreviation = team.optString("abbreviation").ifBlank {
                                team.optString("shortDisplayName").take(3)
                            },
                            logoUrl = logo,
                            shortName = team.optString("shortDisplayName").takeIf { it.isNotBlank() }
                                ?: team.optString("name").takeIf { it.isNotBlank() },
                        ),
                    )
                }
            }
        }
        return out.sortedBy { it.name.lowercase() }
    }

    private fun fetchLeagueResult(league: SportLeague, onlyDefault: Boolean = false): LeagueFetchResult {
        val urls = scoreboardUrls(league)
        val defaultUrl = urls.firstOrNull() ?: league.scoreboardUrl
        val rangeUrls = if (onlyDefault) emptyList() else urls.drop(1)

        val byId = linkedMapOf<String, Game>()
        var successfulBoards = 0
        var failedBoards = 0
        var defaultSucceeded = false

        // Default board (primary for failure accounting)
        val defBody = runCatching { httpGet(defaultUrl) }.getOrNull()
        if (defBody != null) {
            // HTTP success only counts if parse also succeeds.
            // Legitimate empty list from parse is success (no events).
            val parsed = runCatching { parseScoreboard(defBody, league) }.getOrNull()
            if (parsed != null) {
                successfulBoards += 1
                defaultSucceeded = true
                parsed.forEach { g ->
                    val prev = byId[g.id]
                    byId[g.id] = if (prev == null) g else ScoreboardGrouping.prefer(prev, g)
                }
            } else {
                failedBoards += 1
            }
        } else {
            failedBoards += 1
        }

        // Range supplements are best-effort; never affect defaultSucceeded or failure mark for league
        for (url in rangeUrls) {
            val body = runCatching { httpGet(url) }.getOrNull()
            if (body != null) {
                val parsed = runCatching { parseScoreboard(body, league) }.getOrNull()
                if (parsed != null) {
                    successfulBoards += 1
                    parsed.forEach { g ->
                        val prev = byId[g.id]
                        byId[g.id] = if (prev == null) g else ScoreboardGrouping.prefer(prev, g)
                    }
                } else {
                    failedBoards += 1
                }
            } else {
                failedBoards += 1
            }
        }
        return LeagueFetchResult(
            league = league,
            games = byId.values.toList(),
            successfulBoards = successfulBoards,
            failedBoards = failedBoards,
            defaultSucceeded = defaultSucceeded
        )
    }

    private fun scoreboardUrls(league: SportLeague): List<String> {
        val root = league.scoreboardUrl
        val cal = Calendar.getInstance(TimeZone.getTimeZone("America/New_York"))
        val fmt = SimpleDateFormat("yyyyMMdd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("America/New_York")
        }
        val start = fmt.format(cal.time)
        cal.add(Calendar.DAY_OF_YEAR, 7)
        val end = fmt.format(cal.time)
        cal.time = Calendar.getInstance(TimeZone.getTimeZone("America/New_York")).time
        cal.add(Calendar.DAY_OF_YEAR, 1)
        val tomorrow = fmt.format(cal.time)
        return listOf(
            root,
            "$root?dates=$start-$end&limit=200",
            "$root?dates=$tomorrow&limit=100",
        )
    }

    private fun httpGet(url: String): String {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "SportsDash/1.0 (Android)")
            .header("Accept", "application/json")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                // Do not log URL, status, body, or any credential. Caller sees failure via exception.
                throw RuntimeException("http error")
            }
            return resp.body?.string().orEmpty()
        }
    }

    internal fun parseScoreboard(body: String, league: SportLeague): List<Game> {
        if (body.isBlank()) {
            throw IllegalStateException("blank body")
        }
        val json = runCatching { JSONObject(body) }.getOrElse { throw IllegalStateException("malformed json") }
        val events = if (json.has("events")) json.optJSONArray("events") else null
        if (events == null) {
            throw IllegalStateException("missing or invalid events")
        }
        val out = ArrayList<Game>(events.length())
        for (i in 0 until events.length()) {
            val event = events.optJSONObject(i) ?: continue
            val id = event.optString("id")
            if (id.isBlank()) continue
            val competitions = event.optJSONArray("competitions") ?: continue
            val comp = competitions.optJSONObject(0) ?: continue

            val statusObj = comp.optJSONObject("status")
                ?: event.optJSONObject("status")
                ?: JSONObject()
            val type = statusObj.optJSONObject("type") ?: JSONObject()
            val state = type.optString("state", "pre").lowercase()
            val name = type.optString("name").uppercase()
            val completed = type.optBoolean("completed", false)
            val shortDetail = type.optString("shortDetail").takeIf { it.isNotBlank() }
            val detail = type.optString("detail").takeIf { it.isNotBlank() }

            val status = when {
                name.contains("POSTPONED") || name.contains("CANCELED") || name.contains("CANCELLED") ->
                    GameStatus.POSTPONED
                state == "in" || name.contains("IN_PROGRESS") || name.contains("HALFTIME") ->
                    GameStatus.LIVE
                state == "pre" || name.contains("SCHEDULED") || name.contains("DELAYED") ->
                    GameStatus.UPCOMING
                completed || name.contains("FINAL") || state == "post" ->
                    GameStatus.FINAL
                else -> GameStatus.UNKNOWN
            }

            val dateStr = comp.optString("date").ifBlank { event.optString("date") }
            val startMs = parseEspnDate(dateStr) ?: 0L

            var home = TeamInfo("", "Home", "HOME")
            var away = TeamInfo("", "Away", "AWAY")
            val competitors = comp.optJSONArray("competitors")
            if (competitors != null) {
                for (c in 0 until competitors.length()) {
                    val row = competitors.optJSONObject(c) ?: continue
                    val team = row.optJSONObject("team") ?: JSONObject()
                    val scoreRaw = row.opt("score")
                    val score = when (scoreRaw) {
                        is Number -> scoreRaw.toInt()
                        is String -> scoreRaw.trim().toIntOrNull()
                        else -> null
                    }
                    val rawTid = jsonId(team, "id").ifBlank { jsonId(team, "uid") }
                    val info = TeamInfo(
                        id = stableTeamId(league, rawTid).ifBlank { java.util.UUID.randomUUID().toString() },
                        name = team.optString("displayName")
                            .ifBlank { team.optString("name") }
                            .ifBlank { "Team" },
                        abbreviation = team.optString("abbreviation").ifBlank { "TBD" },
                        score = score,
                        logoUrl = team.optString("logo").takeIf { it.isNotBlank() },
                        shortName = team.optString("shortDisplayName")
                            .ifBlank { team.optString("name") }
                            .takeIf { it.isNotBlank() },
                    )
                    if (row.optString("homeAway") == "home") home = info else away = info
                }
            }

            val broadcasts = mutableListOf<String>()
            val bArr = comp.optJSONArray("broadcasts")
            if (bArr != null) {
                for (b in 0 until bArr.length()) {
                    val names = bArr.optJSONObject(b)?.optJSONArray("names")
                    if (names != null) {
                        for (n in 0 until names.length()) {
                            names.optString(n).takeIf { it.isNotBlank() }?.let { broadcasts.add(it) }
                        }
                    }
                }
            }

            val venue = comp.optJSONObject("venue")?.optString("fullName")?.takeIf { it.isNotBlank() }
            val eventName = event.optString("name").ifBlank { event.optString("shortName") }
                .takeIf { it.isNotBlank() }
            val clock = statusObj.optString("displayClock").takeIf { it.isNotBlank() }

            out.add(
                Game(
                    id = "${league.id}-$id",
                    league = league,
                    home = home,
                    away = away,
                    status = status,
                    startTimeMs = startMs,
                    statusDetail = shortDetail ?: detail,
                    clock = clock,
                    venue = venue,
                    eventName = eventName,
                    broadcasts = broadcasts,
                ),
            )
        }
        return out
    }

    private fun parseEspnDate(raw: String): Long? {
        val s = raw.trim()
        if (s.isEmpty()) return null
        val patterns = listOf(
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
        )
        for (p in patterns) {
            runCatching {
                val f = SimpleDateFormat(p, Locale.US)
                f.timeZone = TimeZone.getTimeZone("UTC")
                return f.parse(s)?.time
            }
        }
        return null
    }

}
