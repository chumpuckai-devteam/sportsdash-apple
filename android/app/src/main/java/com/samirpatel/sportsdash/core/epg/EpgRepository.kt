package com.samirpatel.sportsdash.core.epg

import android.util.Xml
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.model.PlaylistConfig
import com.samirpatel.sportsdash.core.model.PlaylistType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import kotlin.math.min

/**
 * Auto EPG like iOS:
 * 1. Bulk `xmltv.php?username=&password=` download → stream-parse
 * 2. Map by epg id / slug / name
 * 3. Progressive Xtream `get_short_epg` for remaining gaps
 *
 * No "Fill missing" UX — caller auto-invokes after playlist load.
 */
class EpgRepository(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(180, TimeUnit.SECONDS)
        .followRedirects(true)
        .build(),
) {
    companion object {
        const val MAX_PER_CHANNEL = 12
        const val HOURS_BEHIND = 1
        const val HOURS_AHEAD = 18
        const val MAX_DOWNLOAD_BYTES = 120L * 1024 * 1024
    }

    data class LoadResult(
        val programsByChannelId: Map<String, List<EpgProgram>>,
        val status: String,
    )

    suspend fun loadForChannels(
        channels: List<IptvChannel>,
        config: PlaylistConfig?,
        onStatus: (String) -> Unit = {},
        onBatch: (Map<String, List<EpgProgram>>) -> Unit = {},
    ): LoadResult = withContext(Dispatchers.IO) {
        if (channels.isEmpty()) {
            return@withContext LoadResult(emptyMap(), "No channels")
        }

        var result = linkedMapOf<String, List<EpgProgram>>()

        // 1) Bulk XMLTV
        if (config != null) {
            val urls = bulkXmltvUrls(config)
            for ((index, url) in urls.withIndex()) {
                onStatus("Downloading guide… (${index + 1}/${urls.size})")
                val byTvg = runCatching {
                    downloadAndParseXmltv(url, onStatus)
                }.getOrNull()
                if (!byTvg.isNullOrEmpty()) {
                    result = LinkedHashMap(mapXmltv(byTvg, channels))
                    onStatus("Guide mapped · ${result.size}/${channels.size} channels")
                    onBatch(result)
                    break
                }
            }
            if (result.isEmpty()) {
                onStatus("Bulk guide unavailable — loading per-channel EPG…")
            }
        }

        // 2) Short EPG fill for Xtream gaps
        if (config?.type == PlaylistType.XTREAM &&
            config.username.isNotBlank() &&
            config.password.isNotBlank()
        ) {
            var missing = channels.filter { result[it.id].isNullOrEmpty() }
            if (missing.isNotEmpty()) {
                val totalMissing = missing.size
                var wave = 0
                while (missing.isNotEmpty() && wave < 40) {
                    wave++
                    val slice = missing.take(48)
                    onStatus(
                        "Auto-filling guide ${result.size}/${channels.size} · " +
                            "${totalMissing - missing.size + slice.size}/$totalMissing gaps…",
                    )
                    val short = loadXtreamShortBatch(slice, config, limit = 8)
                    if (short.isNotEmpty()) {
                        for ((k, v) in short) {
                            if (v.isNotEmpty()) result[k] = v
                        }
                        onBatch(result.toMap())
                    }
                    val attempted = slice.map { it.id }.toSet()
                    missing = missing.filter { it.id !in attempted }
                    if (short.isEmpty() && wave >= 2) {
                        onStatus(
                            "Guide partial · ${result.size}/${channels.size} — " +
                                "provider has no listings for remaining channels",
                        )
                        break
                    }
                }
            }
        }

        val status = "Guide ready · ${result.size}/${channels.size} channels"
        onStatus(status)
        onBatch(result.toMap())
        LoadResult(result.toMap(), status)
    }

    // region Bulk XMLTV

    private fun bulkXmltvUrls(config: PlaylistConfig): List<String> {
        val out = ArrayList<String>()
        when (config.type) {
            PlaylistType.XTREAM -> {
                out.addAll(
                    xtreamXmltvUrls(
                        hostField = config.host,
                        user = config.username,
                        pass = config.password,
                    ),
                )
            }
            PlaylistType.M3U -> {
                xtreamXmltvUrlsFromAnyUrl(config.m3uUrl)?.let { out.addAll(it) }
            }
        }
        return out.distinct()
    }

    private fun xtreamXmltvUrls(hostField: String, user: String, pass: String): List<String> {
        val base = normalizeBase(hostField) ?: return emptyList()
        val userQ = enc(user)
        val passQ = enc(pass)
        val query = "username=$userQ&password=$passQ"
        val roots = httpsPreferredRoots(base)
        val out = ArrayList<String>()
        for (root in roots) {
            out.add("$root/xmltv.php?$query")
            out.add("$root/xmltv.php?$query&type=m3u_plus")
        }
        return out
    }

    private fun xtreamXmltvUrlsFromAnyUrl(raw: String): List<String>? {
        val url = raw.trim().toHttpUrlOrNull() ?: return null
        val user = url.queryParameter("username") ?: return null
        val pass = url.queryParameter("password") ?: return null
        if (user.isBlank() || pass.isBlank()) return null
        val path = url.encodedPath.lowercase()
        if (!path.contains("get.php") && !path.contains("player_api") &&
            !path.contains("xmltv") && !raw.lowercase().contains("username=")
        ) {
            return null
        }
        val base = "${url.scheme}://${url.host}" +
            if (url.port != defaultPort(url.scheme)) ":${url.port}" else ""
        return xtreamXmltvUrls(base, user, pass)
    }

    private fun defaultPort(scheme: String): Int =
        if (scheme.equals("https", ignoreCase = true)) 443 else 80

    private fun normalizeBase(raw: String): String? {
        var s = raw.trim().trimEnd('/')
        if (s.isEmpty()) return null
        if (!s.contains("://")) s = "https://$s"
        val u = s.toHttpUrlOrNull() ?: return null
        val host = u.host
        if (host.isBlank()) return null
        val scheme = u.scheme.ifBlank { "https" }
        return if (u.port != defaultPort(scheme)) "$scheme://$host:${u.port}" else "$scheme://$host"
    }

    private fun httpsPreferredRoots(base: String): List<String> {
        val roots = mutableListOf(base)
        if (base.startsWith("http://")) {
            roots.add(0, "https://" + base.removePrefix("http://"))
        } else if (base.startsWith("https://")) {
            roots.add("http://" + base.removePrefix("https://"))
        }
        return roots.distinct()
    }

    private fun downloadAndParseXmltv(urlString: String, onStatus: (String) -> Unit): Map<String, List<EpgProgram>> {
        val req = Request.Builder()
            .url(urlString)
            .header("Accept", "application/xml, text/xml, */*")
            .header("User-Agent", "SportsDash/1.0")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) return emptyMap()
            val body = resp.body ?: return emptyMap()
            val tmp = File.createTempFile("sportsdash-epg-", ".xml")
            try {
                body.byteStream().use { input ->
                    tmp.outputStream().use { output ->
                        val buf = ByteArray(64 * 1024)
                        var total = 0L
                        while (true) {
                            val n = input.read(buf)
                            if (n <= 0) break
                            total += n
                            if (total > MAX_DOWNLOAD_BYTES) {
                                onStatus("Guide file too large for this device")
                                return emptyMap()
                            }
                            output.write(buf, 0, n)
                        }
                        if (total <= 0) {
                            onStatus("Empty guide file")
                            return emptyMap()
                        }
                        val mb = total / 1_048_576.0
                        onStatus(String.format(Locale.US, "Downloaded %.1f MB — parsing…", mb))
                    }
                }
                return parseXmltvFile(tmp)
            } finally {
                tmp.delete()
            }
        }
    }

    private fun parseXmltvFile(file: File): Map<String, List<EpgProgram>> {
        val now = System.currentTimeMillis()
        val windowStart = now - HOURS_BEHIND * 3600_000L
        val windowEnd = now + HOURS_AHEAD * 3600_000L
        val map = LinkedHashMap<String, MutableList<EpgProgram>>()

        FileInputStream(file).use { fis ->
            val parser = Xml.newPullParser()
            parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
            parser.setInput(fis, null)

            var event = parser.eventType
            var inProgramme = false
            var channelId: String? = null
            var startMs: Long? = null
            var endMs: Long? = null
            var title: String? = null
            var category: String? = null
            var desc: String? = null
            var capture: String? = null
            val text = StringBuilder()

            while (event != XmlPullParser.END_DOCUMENT) {
                when (event) {
                    XmlPullParser.START_TAG -> {
                        when (parser.name.lowercase(Locale.US)) {
                            "programme" -> {
                                inProgramme = true
                                channelId = parser.getAttributeValue(null, "channel")
                                startMs = parseXmltvDate(parser.getAttributeValue(null, "start"))
                                endMs = parseXmltvDate(parser.getAttributeValue(null, "stop"))
                                title = null
                                category = null
                                desc = null
                            }
                            "title" -> if (inProgramme) {
                                capture = "title"
                                text.clear()
                            }
                            "category" -> if (inProgramme) {
                                capture = "category"
                                text.clear()
                            }
                            "desc" -> if (inProgramme) {
                                capture = "desc"
                                text.clear()
                            }
                        }
                    }
                    XmlPullParser.TEXT -> {
                        if (capture != null) text.append(parser.text)
                    }
                    XmlPullParser.END_TAG -> {
                        val name = parser.name.lowercase(Locale.US)
                        when {
                            capture != null && name == capture -> {
                                val v = text.toString().trim()
                                when (capture) {
                                    "title" -> title = v
                                    "category" -> category = v
                                    "desc" -> desc = v
                                }
                                capture = null
                            }
                            name == "programme" && inProgramme -> {
                                val ch = channelId
                                val s = startMs
                                val e = endMs
                                if (ch != null && s != null && e != null && e > s) {
                                    // keep if overlaps window
                                    if (e > windowStart && s < windowEnd) {
                                        val list = map.getOrPut(ch) { ArrayList() }
                                        if (list.size < MAX_PER_CHANNEL) {
                                            list.add(
                                                EpgProgram(
                                                    channelKey = ch,
                                                    title = title?.ifBlank { null } ?: "Program",
                                                    startMs = s,
                                                    endMs = e,
                                                    description = desc,
                                                    category = category,
                                                ),
                                            )
                                        }
                                    }
                                }
                                inProgramme = false
                            }
                        }
                    }
                }
                event = parser.next()
            }
        }

        // sort each channel
        for ((k, list) in map) {
            list.sortBy { it.startMs }
            map[k] = list
        }
        return map
    }

    /** XMLTV start/stop: yyyyMMddHHmmss [±HHMM] */
    private fun parseXmltvDate(raw: String?): Long? {
        if (raw.isNullOrBlank()) return null
        val cleaned = raw.trim()
        val core = cleaned.take(14)
        if (core.length < 14) return null
        return try {
            val fmt = SimpleDateFormat("yyyyMMddHHmmss", Locale.US)
            // Prefer offset if present
            val rest = cleaned.drop(14).trim()
            fmt.timeZone = when {
                rest.startsWith("+") || rest.startsWith("-") -> {
                    val off = rest.replace(" ", "")
                    TimeZone.getTimeZone("GMT$off")
                }
                rest.equals("UTC", true) || rest.equals("Z", true) -> TimeZone.getTimeZone("UTC")
                else -> TimeZone.getDefault()
            }
            fmt.parse(core)?.time
        } catch (_: Exception) {
            null
        }
    }

    private fun mapXmltv(
        byTvg: Map<String, List<EpgProgram>>,
        channels: List<IptvChannel>,
    ): Map<String, List<EpgProgram>> {
        if (byTvg.isEmpty()) return emptyMap()
        // index keys lowercase
        val index = HashMap<String, List<EpgProgram>>(byTvg.size * 2)
        for ((k, v) in byTvg) {
            index[k] = v
            index[k.lowercase(Locale.US)] = v
            index[slug(k)] = v
        }

        val out = LinkedHashMap<String, List<EpgProgram>>()
        for (ch in channels) {
            val candidates = buildList {
                ch.epgChannelId?.let {
                    add(it)
                    add(it.lowercase(Locale.US))
                    add(slug(it))
                }
                add(ch.name)
                add(ch.name.lowercase(Locale.US))
                add(slug(ch.name))
                ch.streamId?.let { add(it) }
            }
            var hit: List<EpgProgram>? = null
            for (c in candidates) {
                val found = index[c]
                if (!found.isNullOrEmpty()) {
                    hit = found
                    break
                }
            }
            // fuzzy: contains name slug in any key
            if (hit == null) {
                val ns = slug(ch.name)
                if (ns.length >= 4) {
                    val entry = index.entries.firstOrNull { (k, _) ->
                        k.contains(ns) || ns.contains(k)
                    }
                    hit = entry?.value
                }
            }
            if (!hit.isNullOrEmpty()) {
                out[ch.id] = hit.map { it.copy(channelKey = ch.id) }.take(MAX_PER_CHANNEL)
            }
        }
        return out
    }

    private fun slug(s: String): String =
        s.lowercase(Locale.US)
            .replace(Regex("[^a-z0-9]+"), "")

    // endregion

    // region Short EPG

    private suspend fun loadXtreamShortBatch(
        channels: List<IptvChannel>,
        config: PlaylistConfig,
        limit: Int,
    ): Map<String, List<EpgProgram>> = coroutineScope {
        val base = normalizeBase(config.host) ?: return@coroutineScope emptyMap()
        val userQ = enc(config.username)
        val passQ = enc(config.password)
        val batchSize = 12
        val out = LinkedHashMap<String, List<EpgProgram>>()
        var i = 0
        while (i < channels.size) {
            val end = min(i + batchSize, channels.size)
            val slice = channels.subList(i, end)
            val parts = slice.map { ch ->
                async(Dispatchers.IO) {
                    val sid = ch.streamId ?: xtreamStreamId(ch) ?: return@async ch.id to emptyList()
                    ch.id to fetchShortEpg(base, userQ, passQ, sid, limit, ch.id)
                }
            }.awaitAll()
            for ((id, programs) in parts) {
                if (programs.isNotEmpty()) out[id] = programs
            }
            i = end
        }
        out
    }

    private fun fetchShortEpg(
        base: String,
        userQ: String,
        passQ: String,
        streamId: String,
        limit: Int,
        channelKey: String,
    ): List<EpgProgram> {
        val url =
            "$base/player_api.php?username=$userQ&password=$passQ" +
                "&action=get_short_epg&stream_id=$streamId&limit=$limit"
        val body = runCatching { httpGet(url) }.getOrNull() ?: return emptyList()
        if (body.length > 256_000) return emptyList()
        val listings: JSONArray = try {
            val trimmed = body.trim()
            when {
                trimmed.startsWith("{") -> {
                    val obj = JSONObject(trimmed)
                    obj.optJSONArray("epg_listings") ?: JSONArray()
                }
                trimmed.startsWith("[") -> JSONArray(trimmed)
                else -> JSONArray()
            }
        } catch (_: Exception) {
            return emptyList()
        }
        val out = ArrayList<EpgProgram>(listings.length())
        for (i in 0 until min(listings.length(), limit)) {
            val item = listings.optJSONObject(i) ?: continue
            val title = decodeBase64Maybe(item.optString("title")) ?: "Program"
            val start = parseEpgDate(
                item.optString("start_timestamp").ifBlank { item.optString("start") },
            ) ?: continue
            val end = parseEpgDate(
                item.optString("end_timestamp")
                    .ifBlank { item.optString("stop_timestamp") }
                    .ifBlank { item.optString("stop") }
                    .ifBlank { item.optString("end") },
            ) ?: continue
            if (end <= start) continue
            out.add(
                EpgProgram(
                    channelKey = channelKey,
                    title = title,
                    startMs = start,
                    endMs = end,
                    description = decodeBase64Maybe(item.optString("description")),
                ),
            )
        }
        return out.sortedBy { it.startMs }
    }

    private fun xtreamStreamId(ch: IptvChannel): String? {
        if (ch.id.startsWith("xtream-")) return ch.id.removePrefix("xtream-")
        val last = ch.url.substringAfterLast('/').substringBefore('?')
            .removeSuffix(".m3u8").removeSuffix(".ts")
        return last.takeIf { it.toIntOrNull() != null }
    }

    private fun decodeBase64Maybe(s: String?): String? {
        if (s.isNullOrBlank()) return null
        return try {
            val decoded = android.util.Base64.decode(s, android.util.Base64.DEFAULT)
            val str = String(decoded, Charsets.UTF_8)
            if (str.isNotBlank()) str else s
        } catch (_: Exception) {
            s
        }
    }

    private fun parseEpgDate(raw: String?): Long? {
        if (raw.isNullOrBlank()) return null
        var s = raw.trim()
        decodeBase64Maybe(s)?.let { if (it != s) s = it }
        s.toDoubleOrNull()?.let { ts ->
            return when {
                ts > 1_000_000_000_000 -> ts.toLong()
                ts > 1_000_000_000 -> (ts * 1000).toLong()
                else -> null
            }
        }
        return try {
            val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
            fmt.timeZone = TimeZone.getDefault()
            fmt.parse(s)?.time
        } catch (_: Exception) {
            null
        }
    }

    private fun httpGet(url: String): String {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "SportsDash/1.0")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            return resp.body?.string().orEmpty()
        }
    }

    private fun enc(s: String): String =
        java.net.URLEncoder.encode(s, Charsets.UTF_8.name())

    // endregion
}

/** Helpers used by Guide UI. */
fun List<EpgProgram>.nowPlaying(nowMs: Long = System.currentTimeMillis()): EpgProgram? =
    firstOrNull { it.contains(nowMs) }

fun List<EpgProgram>.upNext(nowMs: Long = System.currentTimeMillis()): EpgProgram? =
    filter { it.startMs > nowMs }.minByOrNull { it.startMs }
