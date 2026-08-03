package com.samirpatel.sportsdash.core.ratings

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.URLEncoder
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

data class MovieRating(
    val cacheKey: String,
    val title: String,
    val year: Int? = null,
    val criticScore: Int? = null,
    val audienceScore: Int? = null,
    val source: String = "",
    val fetchedAtMs: Long = System.currentTimeMillis(),
    val posterURL: String? = null,
) {
    val hasAnyScore: Boolean get() = criticScore != null || audienceScore != null
    val criticLabel: String? get() = criticScore?.let { "$it%" }
    val audienceLabel: String? get() = audienceScore?.let { "$it%" }
}

object MovieTitleParser {
    private val noise = setOf(
        "hd", "fhd", "uhd", "4k", "8k", "hdr", "hdr10", "dv", "sdr",
        "live", "premiere", "new", "eng", "en", "multi", "dual",
        "h264", "h265", "hevc", "aac", "ac3", "dts",
    )

    fun parse(raw: String): Pair<String, Int?> {
        var t = raw.trim()
        val lower = t.lowercase(Locale.US)
        for (p in listOf("movie:", "film:", "cinema:", "mov:", "movies -", "movie -")) {
            if (lower.startsWith(p)) {
                t = t.drop(p.length).trim()
                break
            }
        }
        var year: Int? = null
        Regex("""\((\d{4})\)\s*$""").find(t)?.let { m ->
            year = m.groupValues[1].toIntOrNull()
            t = t.removeRange(m.range).trim()
        }
        if (year == null) {
            Regex("""\s((?:19|20)\d{2})\s*$""").find(t)?.let { m ->
                val y = m.groupValues[1].toIntOrNull()
                if (y != null && y in 1950..2035) {
                    year = y
                    t = t.removeRange(m.range).trim()
                }
            }
        }
        t = t.replace(Regex("""\[.*?\]"""), " ")
        t = t.replace(Regex("""\((?:hd|fhd|uhd|4k|hdr|live|multi)[^)]*\)""", RegexOption.IGNORE_CASE), " ")
        val parts = t.split(Regex("""\s+""")).filter { it.isNotBlank() }.toMutableList()
        while (parts.isNotEmpty()) {
            val last = parts.last().lowercase(Locale.US)
            if (last in noise || last.startsWith("1080") || last.startsWith("720")) parts.removeAt(parts.lastIndex)
            else break
        }
        t = parts.joinToString(" ").replace(Regex("""\s+"""), " ").trim()
        return t to year
    }

    fun cacheKey(title: String, year: Int? = null): String {
        val (clean, y) = parse(title)
        val resolved = year ?: y
        val base = clean.lowercase(Locale.US)
        return if (resolved != null) "$base|$resolved" else base
    }
}

object MovieDetection {
    fun isMovieCandidate(
        title: String,
        category: String? = null,
        channelGroup: String? = null,
        channelName: String? = null,
        forceMovie: Boolean = false,
    ): Boolean {
        if (forceMovie) return true
        val blob = listOfNotNull(title, category, channelGroup, channelName)
            .joinToString(" ")
            .lowercase(Locale.US)
        if (blob.contains("sport") || blob.contains("news") || blob.contains("weather") ||
            blob.contains("series") || blob.contains("episode")
        ) {
            // still allow explicit movie tokens
            if (!(blob.contains("movie") || blob.contains("cinema") || blob.contains("film"))) {
                return false
            }
        }
        if (blob.contains("movie") || blob.contains("cinema") || blob.contains("film")) return true
        // year in title is a soft hint
        return Regex("""\b(19|20)\d{2}\b""").containsMatchIn(blob) && title.length >= 4
    }
}

/**
 * OMDb primary + TMDB fallback — mirrors iOS MovieRatingsService.
 * Keys from PrefsStore; never throw into UI.
 */
class MovieRatingsRepository(
    private val cacheDir: File,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build(),
) {
    private val mutex = Mutex()
    private val memory = mutableMapOf<String, MovieRating>()
    private val negative = mutableMapOf<String, Long>()
    private var diskLoaded = false
    private val cacheFile get() = File(cacheDir, "movie_ratings_cache.json")
    private val ttlMs = 7L * 24 * 3600 * 1000
    private val negTtlMs = 6L * 3600 * 1000

    suspend fun rating(
        rawTitle: String,
        year: Int? = null,
        isMovieHint: Boolean = true,
        omdbKey: String?,
        tmdbKey: String?,
    ): MovieRating? = withContext(Dispatchers.IO) {
        if (!isMovieHint) return@withContext null
        val (title, parsedYear) = MovieTitleParser.parse(rawTitle)
        if (title.length < 2) return@withContext null
        val y = year ?: parsedYear
        val key = MovieTitleParser.cacheKey(title, y)
        mutex.withLock {
            ensureDiskLocked()
            memory[key]?.let { hit ->
                if (hit.hasAnyScore && System.currentTimeMillis() - hit.fetchedAtMs < ttlMs) return@withContext hit
            }
            negative[key]?.let { t ->
                if (System.currentTimeMillis() - t < negTtlMs) return@withContext null
            }
        }
        val omdb = omdbKey?.takeIf { it.isNotBlank() }
        val tmdb = tmdbKey?.takeIf { it.isNotBlank() }
        if (omdb == null && tmdb == null) return@withContext null

        if (omdb != null) {
            fetchOmdb(title, y, omdb, key)?.let { r ->
                mutex.withLock {
                    memory[key] = r
                    negative.remove(key)
                    persistLocked()
                }
                return@withContext r
            }
        }
        if (tmdb != null) {
            fetchTmdb(title, y, tmdb, key)?.let { r ->
                mutex.withLock {
                    memory[key] = r
                    negative.remove(key)
                    persistLocked()
                }
                return@withContext r
            }
        }
        mutex.withLock { negative[key] = System.currentTimeMillis() }
        null
    }

    private fun fetchOmdb(title: String, year: Int?, apiKey: String, cacheKey: String): MovieRating? {
        fun once(typeMovie: Boolean): MovieRating? {
            val q = buildString {
                append("https://www.omdbapi.com/?t=")
                append(URLEncoder.encode(title, Charsets.UTF_8.name()))
                append("&apikey=").append(URLEncoder.encode(apiKey, Charsets.UTF_8.name()))
                if (typeMovie) append("&type=movie")
                if (year != null) append("&y=").append(year)
            }
            val body = httpGet(q) ?: return null
            val json = runCatching { JSONObject(body) }.getOrNull() ?: return null
            if (json.optString("Response") == "False") return null
            var critic: Int? = null
            var audience: Int? = null
            val ratings = json.optJSONArray("Ratings")
            if (ratings != null) {
                for (i in 0 until ratings.length()) {
                    val r = ratings.optJSONObject(i) ?: continue
                    val src = r.optString("Source").lowercase(Locale.US)
                    val value = r.optString("Value")
                    when {
                        src.contains("rotten") -> critic = parsePercent(value)
                        src.contains("internet movie database") || src == "imdb" -> {
                            value.substringBefore("/").toDoubleOrNull()?.let {
                                audience = (it * 10).toInt()
                            }
                        }
                    }
                }
            }
            if (audience == null) {
                json.optString("imdbRating").toDoubleOrNull()?.takeIf { it > 0 }?.let {
                    audience = (it * 10).toInt()
                }
            }
            if (critic == null) {
                json.optString("Metascore").toIntOrNull()?.takeIf { it in 0..100 }?.let { critic = it }
            }
            if (critic == null && audience == null) return null
            return MovieRating(
                cacheKey = cacheKey,
                title = json.optString("Title", title),
                year = json.optString("Year").take(4).toIntOrNull() ?: year,
                criticScore = critic,
                audienceScore = audience,
                source = "OMDb",
                posterURL = json.optString("Poster").takeIf { it.isNotBlank() && it != "N/A" },
            )
        }
        return once(true) ?: once(false)
    }

    private fun fetchTmdb(title: String, year: Int?, apiKey: String, cacheKey: String): MovieRating? {
        val q = buildString {
            append("https://api.themoviedb.org/3/search/movie?api_key=")
            append(URLEncoder.encode(apiKey, Charsets.UTF_8.name()))
            append("&query=").append(URLEncoder.encode(title, Charsets.UTF_8.name()))
            append("&include_adult=false")
            if (year != null) append("&year=").append(year)
        }
        val body = httpGet(q) ?: return null
        val json = runCatching { JSONObject(body) }.getOrNull() ?: return null
        val results = json.optJSONArray("results") ?: return null
        if (results.length() == 0) return null
        val first = results.optJSONObject(0) ?: return null
        val vote = first.optDouble("vote_average", 0.0)
        if (vote <= 0) return null
        val audience = minOf(100, (vote * 10).toInt())
        val rd = first.optString("release_date")
        val resolvedYear = if (rd.length >= 4) rd.take(4).toIntOrNull() else year
        val path = first.optString("poster_path")
        val poster = if (path.isNotBlank()) "https://image.tmdb.org/t/p/w185$path" else null
        return MovieRating(
            cacheKey = cacheKey,
            title = first.optString("title", title),
            year = resolvedYear,
            criticScore = null,
            audienceScore = audience,
            source = "TMDB",
            posterURL = poster,
        )
    }

    private fun httpGet(url: String): String? = runCatching {
        val req = Request.Builder().url(url).get().build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) return null
            resp.body?.string()
        }
    }.getOrNull()

    private fun parsePercent(raw: String): Int? {
        val digits = raw.filter { it.isDigit() }
        val n = digits.toIntOrNull() ?: return null
        return n.takeIf { it in 0..100 }
    }

    private fun ensureDiskLocked() {
        if (diskLoaded) return
        diskLoaded = true
        if (!cacheFile.exists()) return
        runCatching {
            val root = JSONObject(cacheFile.readText())
            val now = System.currentTimeMillis()
            val keys = root.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                val o = root.optJSONObject(k) ?: continue
                val fetched = o.optLong("fetchedAtMs", 0L)
                if (now - fetched > ttlMs) continue
                memory[k] = MovieRating(
                    cacheKey = o.optString("cacheKey", k),
                    title = o.optString("title"),
                    year = o.optInt("year").takeIf { o.has("year") && !o.isNull("year") },
                    criticScore = o.optInt("criticScore").takeIf { o.has("criticScore") && !o.isNull("criticScore") },
                    audienceScore = o.optInt("audienceScore").takeIf { o.has("audienceScore") && !o.isNull("audienceScore") },
                    source = o.optString("source"),
                    fetchedAtMs = fetched,
                    posterURL = o.optString("posterURL").takeIf { it.isNotBlank() },
                )
            }
        }
    }

    private fun persistLocked() {
        runCatching {
            cacheDir.mkdirs()
            val root = JSONObject()
            for ((k, v) in memory) {
                if (!v.hasAnyScore) continue
                root.put(
                    k,
                    JSONObject().apply {
                        put("cacheKey", v.cacheKey)
                        put("title", v.title)
                        if (v.year != null) put("year", v.year) else put("year", JSONObject.NULL)
                        if (v.criticScore != null) put("criticScore", v.criticScore) else put("criticScore", JSONObject.NULL)
                        if (v.audienceScore != null) put("audienceScore", v.audienceScore) else put("audienceScore", JSONObject.NULL)
                        put("source", v.source)
                        put("fetchedAtMs", v.fetchedAtMs)
                        put("posterURL", v.posterURL ?: JSONObject.NULL)
                    },
                )
            }
            cacheFile.writeText(root.toString())
        }
    }
}
