package com.samirpatel.sportsdash.core.sports

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
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
    suspend fun fetchGames(leagues: List<SportLeague>): List<Game> = withContext(Dispatchers.IO) {
        coroutineScope {
            leagues.map { league ->
                async { fetchLeague(league) }
            }.awaitAll().flatten()
                .distinctBy { it.id }
                .sortedWith(
                    compareBy<Game> { statusRank(it.status) }
                        .thenBy { it.startTimeMs },
                )
        }
    }

    private fun fetchLeague(league: SportLeague): List<Game> {
        val urls = scoreboardUrls(league)
        val byId = linkedMapOf<String, Game>()
        for (url in urls) {
            runCatching {
                parseScoreboard(httpGet(url), league).forEach { g ->
                    val prev = byId[g.id]
                    byId[g.id] = if (prev == null) g else prefer(prev, g)
                }
            }
        }
        return byId.values.toList()
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
            if (!resp.isSuccessful) return ""
            return resp.body?.string().orEmpty()
        }
    }

    private fun parseScoreboard(body: String, league: SportLeague): List<Game> {
        if (body.isBlank()) return emptyList()
        val json = JSONObject(body)
        val events = json.optJSONArray("events") ?: return emptyList()
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
                        is Int -> scoreRaw
                        is String -> scoreRaw.toIntOrNull()
                        else -> null
                    }
                    val info = TeamInfo(
                        id = team.optString("id").ifBlank { java.util.UUID.randomUUID().toString() },
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

    private fun statusRank(s: GameStatus): Int = when (s) {
        GameStatus.LIVE -> 0
        GameStatus.UPCOMING -> 1
        GameStatus.POSTPONED -> 2
        GameStatus.FINAL -> 3
        GameStatus.UNKNOWN -> 4
    }

    private fun prefer(a: Game, b: Game): Game =
        if (statusRank(a.status) <= statusRank(b.status)) a else b
}
