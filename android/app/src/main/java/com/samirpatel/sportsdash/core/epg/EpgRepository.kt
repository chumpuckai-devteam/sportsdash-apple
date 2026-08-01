package com.samirpatel.sportsdash.core.epg

import android.util.Base64
import android.util.Xml
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.model.PlaylistConfig
import com.samirpatel.sportsdash.core.model.PlaylistType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.FileInputStream
import java.io.FileReader
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.min

/**
 * Auto EPG:
 * - Category path: **short EPG first** (fast Now/Next)
 * - Background: bulk xmltv.php download → disk cache → map → short fill gaps
 */
class EpgRepository(
    private val cacheDir: File? = null,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(180, TimeUnit.SECONDS)
        .followRedirects(true)
        .build(),
) {
    companion object {
        const val MAX_PER_CHANNEL = 16
        const val HOURS_BEHIND = 6
        const val HOURS_AHEAD = 36
        const val MAX_DOWNLOAD_BYTES = 150L * 1024 * 1024
        private const val CACHE_VERSION = 2
    }

    data class LoadResult(
        val programsByChannelId: Map<String, List<EpgProgram>>,
        val status: String,
    )

    private val bulkMutex = Mutex()

    /** Fast path for open Guide category — short EPG only. */
    suspend fun loadShortEpgForChannels(
        channels: List<IptvChannel>,
        config: PlaylistConfig,
        onStatus: (String) -> Unit = {},
        onBatch: (Map<String, List<EpgProgram>>) -> Unit = {},
    ): LoadResult = withContext(Dispatchers.IO) {
        if (channels.isEmpty()) return@withContext LoadResult(emptyMap(), "No channels")
        if (config.type != PlaylistType.XTREAM) {
            return@withContext LoadResult(emptyMap(), "Short EPG needs Xtream")
        }
        onStatus("Loading Now/Next for ${channels.size} channels…")
        val result = linkedMapOf<String, List<EpgProgram>>()
        var missing = channels.toList()
        var wave = 0
        while (missing.isNotEmpty() && wave < 30) {
            wave++
            val slice = missing.take(40)
            onStatus(
                "EPG ${result.size}/${channels.size} · wave $wave…",
            )
            val short = loadXtreamShortBatch(slice, config, limit = 10)
            if (short.isNotEmpty()) {
                for ((k, v) in short) {
                    if (v.isNotEmpty()) result[k] = v
                }
                onBatch(result.toMap())
            }
            val attempted = slice.map { it.id }.toSet()
            missing = missing.filter { it.id !in attempted }
            if (short.isEmpty() && wave >= 2) break
        }
        val status = "Category guide · ${result.size}/${channels.size} channels"
        onStatus(status)
        onBatch(result.toMap())
        LoadResult(result.toMap(), status)
    }

    /**
     * Full path: disk cache → bulk xmltv → map → short fill remaining.
     * Serialised so category + background don't thrash the same download.
     */
    suspend fun loadBulkThenFill(
        channels: List<IptvChannel>,
        config: PlaylistConfig?,
        onStatus: (String) -> Unit = {},
        onBatch: (Map<String, List<EpgProgram>>) -> Unit = {},
    ): LoadResult = withContext(Dispatchers.IO) {
        if (channels.isEmpty()) return@withContext LoadResult(emptyMap(), "No channels")
        bulkMutex.withLock {
            var result = linkedMapOf<String, List<EpgProgram>>()

            // 1) Disk cache of raw tvg map
            if (config != null) {
                val cached = readTvgCache(config)
                if (!cached.isNullOrEmpty()) {
                    onStatus("Using cached guide (${cached.size} listings)…")
                    result = LinkedHashMap(mapXmltv(cached, channels))
                    onStatus("Cache mapped · ${result.size}/${channels.size} channels")
                    onBatch(result.toMap())
                }
            }

            // 2) Bulk download if still thin coverage
            val coverage = result.size.toFloat() / channels.size.coerceAtLeast(1)
            if (config != null && coverage < 0.15f) {
                val urls = bulkXmltvUrls(config)
                for ((index, url) in urls.withIndex()) {
                    onStatus("Downloading guide… (${index + 1}/${urls.size})")
                    val byTvg = runCatching { downloadAndParseXmltv(url, onStatus) }.getOrNull()
                    if (!byTvg.isNullOrEmpty()) {
                        writeTvgCache(config, byTvg)
                        val mapped = mapXmltv(byTvg, channels)
                        // merge richer
                        for ((k, v) in mapped) {
                            val old = result[k]
                            if (old == null || v.size > old.size) result[k] = v
                        }
                        onStatus("Bulk mapped · ${result.size}/${channels.size} channels")
                        onBatch(result.toMap())
                        break
                    }
                }
            }

            // 3) Short EPG for gaps (Xtream)
            if (config?.type == PlaylistType.XTREAM &&
                config.username.isNotBlank() &&
                config.password.isNotBlank()
            ) {
                var missing = channels.filter { result[it.id].isNullOrEmpty() }
                if (missing.isNotEmpty()) {
                    val totalMissing = missing.size
                    var wave = 0
                    while (missing.isNotEmpty() && wave < 50) {
                        wave++
                        val slice = missing.take(48)
                        onStatus(
                            "Auto-filling ${result.size}/${channels.size} · " +
                                "${totalMissing - missing.size + slice.size}/$totalMissing…",
                        )
                        val short = loadXtreamShortBatch(slice, config, limit = 10)
                        if (short.isNotEmpty()) {
                            for ((k, v) in short) {
                                if (v.isNotEmpty()) result[k] = v
                            }
                            onBatch(result.toMap())
                        }
                        val attempted = slice.map { it.id }.toSet()
                        missing = missing.filter { it.id !in attempted }
                        if (short.isEmpty() && wave >= 3) break
                    }
                }
            }

            val status = "Guide ready · ${result.size}/${channels.size} channels"
            onStatus(status)
            onBatch(result.toMap())
            LoadResult(result.toMap(), status)
        }
    }

    // region Cache

    private fun cacheKey(config: PlaylistConfig): String {
        val host = when (config.type) {
            PlaylistType.XTREAM -> config.host.trim().lowercase(Locale.US)
            PlaylistType.M3U -> config.m3uUrl.trim().lowercase(Locale.US).take(120)
        }
        val user = config.username.trim().lowercase(Locale.US)
        return (host + "|" + user).hashCode().toUInt().toString(16)
    }

    private fun tvgCacheFile(config: PlaylistConfig): File? {
        val dir = cacheDir ?: return null
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "tvg-v$CACHE_VERSION-${cacheKey(config)}.tsv")
    }

    private fun readTvgCache(config: PlaylistConfig): Map<String, List<EpgProgram>>? {
        val file = tvgCacheFile(config) ?: return null
        if (!file.isFile || file.length() < 32) return null
        // stale after 18h
        if (System.currentTimeMillis() - file.lastModified() > 18 * 3600_000L) return null
        return runCatching {
            val map = LinkedHashMap<String, MutableList<EpgProgram>>()
            BufferedReader(FileReader(file)).use { br ->
                var line = br.readLine()
                while (line != null) {
                    val parts = line.split('\t')
                    if (parts.size >= 4) {
                        val ch = parts[0]
                        val start = parts[1].toLongOrNull()
                        val end = parts[2].toLongOrNull()
                        val title = parts[3].replace("\\n", "\n").replace("\\t", "\t")
                        if (start != null && end != null && end > start) {
                            val list = map.getOrPut(ch) { ArrayList() }
                            if (list.size < MAX_PER_CHANNEL) {
                                list.add(
                                    EpgProgram(
                                        channelKey = ch,
                                        title = title.ifBlank { "Program" },
                                        startMs = start,
                                        endMs = end,
                                    ),
                                )
                            }
                        }
                    }
                    line = br.readLine()
                }
            }
            map.mapValues { (_, v) -> v.sortedBy { it.startMs } }
        }.getOrNull()
    }

    private fun writeTvgCache(config: PlaylistConfig, byTvg: Map<String, List<EpgProgram>>) {
        val file = tvgCacheFile(config) ?: return
        runCatching {
            val tmp = File(file.parentFile, file.name + ".tmp")
            BufferedWriter(FileWriter(tmp)).use { bw ->
                for ((ch, list) in byTvg) {
                    for (p in list) {
                        val title = p.title.replace("\t", " ").replace("\n", " ")
                        bw.append(ch).append('\t')
                            .append(p.startMs.toString()).append('\t')
                            .append(p.endMs.toString()).append('\t')
                            .append(title).append('\n')
                    }
                }
            }
            if (!tmp.renameTo(file)) {
                tmp.copyTo(file, overwrite = true)
                tmp.delete()
            }
        }
    }

    // endregion

    // region Bulk XMLTV

    private fun bulkXmltvUrls(config: PlaylistConfig): List<String> {
        val out = ArrayList<String>()
        when (config.type) {
            PlaylistType.XTREAM -> {
                out.addAll(xtreamXmltvUrls(config.host, config.username, config.password))
            }
            PlaylistType.M3U -> {
                xtreamXmltvUrlsFromAnyUrl(config.m3uUrl)?.let { out.addAll(it) }
            }
        }
        return out.distinct()
    }

    private fun defaultPort(scheme: String): Int =
        if (scheme.equals("https", ignoreCase = true)) 443 else 80

    private fun xtreamXmltvUrls(hostField: String, user: String, pass: String): List<String> {
        val base = normalizeBase(hostField) ?: return emptyList()
        val query = "username=${enc(user)}&password=${enc(pass)}"
        val out = ArrayList<String>()
        for (root in httpsPreferredRoots(base)) {
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
        val base = buildString {
            append(url.scheme)
            append("://")
            append(url.host)
            if (url.port != defaultPort(url.scheme)) {
                append(':')
                append(url.port)
            }
        }
        return xtreamXmltvUrls(base, user, pass)
    }

    private fun normalizeBase(raw: String): String? {
        var s = raw.trim().trimEnd('/')
        if (s.isEmpty()) return null
        if (!s.contains("://")) s = "https://$s"
        val u = s.toHttpUrlOrNull() ?: return null
        if (u.host.isBlank()) return null
        val scheme = u.scheme.ifBlank { "https" }
        return if (u.port != defaultPort(scheme)) {
            "$scheme://${u.host}:${u.port}"
        } else {
            "$scheme://${u.host}"
        }
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

    private fun downloadAndParseXmltv(
        urlString: String,
        onStatus: (String) -> Unit,
    ): Map<String, List<EpgProgram>> {
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
                val parsed = parseXmltvFile(tmp)
                onStatus("Parsed ${parsed.size} guide channels")
                return parsed
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
        // channel id → display names (for name matching to playlist)
        val displayNames = LinkedHashMap<String, MutableList<String>>()

        FileInputStream(file).use { fis ->
            val parser = Xml.newPullParser()
            parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
            parser.setInput(fis, null)

            var event = parser.eventType
            var inProgramme = false
            var inChannel = false
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
                            "channel" -> {
                                inChannel = true
                                channelId = parser.getAttributeValue(null, "id")
                            }
                            "display-name" -> if (inChannel) {
                                capture = "display-name"
                                text.clear()
                            }
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
                        if (capture != null && name == capture) {
                            val v = text.toString().trim()
                            when (capture) {
                                "title" -> title = v
                                "category" -> category = v
                                "desc" -> desc = v
                                "display-name" -> {
                                    val id = channelId
                                    if (id != null && v.isNotBlank()) {
                                        displayNames.getOrPut(id) { ArrayList() }.add(v)
                                    }
                                }
                            }
                            capture = null
                        } else if (name == "channel") {
                            inChannel = false
                        } else if (name == "programme" && inProgramme) {
                            val ch = channelId
                            val s = startMs
                            val e = endMs
                            if (ch != null && s != null && e != null && e > s) {
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
                event = parser.next()
            }
        }

        for ((k, list) in map) {
            list.sortBy { it.startMs }
            map[k] = list
        }

        // Alias programmes under display-name keys so playlist names can match
        val aliased = LinkedHashMap<String, List<EpgProgram>>(map.size * 2)
        for ((id, list) in map) {
            aliased[id] = list
            for (dn in displayNames[id].orEmpty()) {
                if (dn.isNotBlank()) {
                    aliased.putIfAbsent(dn, list)
                    aliased.putIfAbsent(dn.lowercase(Locale.US), list)
                    aliased.putIfAbsent(slug(dn), list)
                }
            }
        }
        return aliased
    }

    /** XMLTV: yyyyMMddHHmmss optional offset (+0000 / +00:00 / Z). */
    private fun parseXmltvDate(raw: String?): Long? {
        if (raw.isNullOrBlank()) return null
        val cleaned = raw.trim()
        val core = cleaned.take(14)
        if (core.length < 14 || !core.all { it.isDigit() }) return null
        val rest = cleaned.drop(14).trim()
        val tz: TimeZone = when {
            rest.isEmpty() || rest.equals("Z", true) || rest.equals("UTC", true) ->
                TimeZone.getTimeZone("UTC")
            else -> {
                // "+0000", "+00:00", " +0100"
                val digits = rest.replace(":", "").replace(" ", "")
                val sign = when {
                    digits.startsWith("+") || digits.startsWith("-") -> digits.first()
                    else -> '+'
                }
                val num = digits.dropWhile { it == '+' || it == '-' }.padStart(4, '0').take(4)
                val hh = num.take(2)
                val mm = num.drop(2).take(2)
                TimeZone.getTimeZone("GMT$sign$hh:$mm")
            }
        }
        return try {
            val fmt = SimpleDateFormat("yyyyMMddHHmmss", Locale.US)
            fmt.timeZone = tz
            fmt.isLenient = false
            fmt.parse(core)?.time
        } catch (_: Exception) {
            null
        }
    }

    private fun mapXmltv(
        byTvg: Map<String, List<EpgProgram>>,
        channels: List<IptvChannel>,
    ): Map<String, List<EpgProgram>> {
        if (byTvg.isEmpty() || channels.isEmpty()) return emptyMap()

        val index = HashMap<String, List<EpgProgram>>(byTvg.size * 4)
        for ((k, v) in byTvg) {
            fun put(key: String) {
                if (key.isBlank()) return
                index.putIfAbsent(key, v)
                index.putIfAbsent(key.lowercase(Locale.US), v)
                index.putIfAbsent(slug(key), v)
            }
            put(k)
            // common tvg id variants
            put(k.replace(' ', '_'))
            put(k.replace('_', '.'))
            put(k.replace('.', '_'))
        }

        val out = LinkedHashMap<String, List<EpgProgram>>()
        for (ch in channels) {
            val candidates = buildList {
                ch.epgChannelId?.let {
                    add(it)
                    add(it.lowercase(Locale.US))
                    add(slug(it))
                    add(it.replace(' ', '_'))
                    add(it.replace('_', '.'))
                }
                add(ch.name)
                add(ch.name.lowercase(Locale.US))
                add(slug(ch.name))
                ch.streamId?.let {
                    add(it)
                    add("xtream-$it")
                }
            }
            var hit: List<EpgProgram>? = null
            for (c in candidates) {
                val found = index[c] ?: index[c.lowercase(Locale.US)] ?: index[slug(c)]
                if (!found.isNullOrEmpty()) {
                    hit = found
                    break
                }
            }
            if (hit == null) {
                val ns = slug(ch.name)
                if (ns.length >= 5) {
                    hit = index.entries.firstOrNull { (k, _) ->
                        val ks = slug(k)
                        ks == ns || (ks.length >= 5 && (ks.contains(ns) || ns.contains(ks)))
                    }?.value
                }
            }
            if (!hit.isNullOrEmpty()) {
                out[ch.id] = hit.map { it.copy(channelKey = ch.id) }.take(MAX_PER_CHANNEL)
            }
        }
        return out
    }

    private fun slug(s: String): String =
        s.lowercase(Locale.US).replace(Regex("[^a-z0-9]+"), "")

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
        val roots = httpsPreferredRoots(base)
        val batchSize = 10
        val out = LinkedHashMap<String, List<EpgProgram>>()
        var i = 0
        while (i < channels.size) {
            val end = min(i + batchSize, channels.size)
            val slice = channels.subList(i, end)
            val parts = slice.map { ch ->
                async(Dispatchers.IO) {
                    val sid = ch.streamId ?: xtreamStreamId(ch) ?: return@async ch.id to emptyList()
                    var programs: List<EpgProgram> = emptyList()
                    for (root in roots) {
                        programs = fetchShortEpg(root, userQ, passQ, sid, limit, ch.id)
                        if (programs.isNotEmpty()) break
                    }
                    ch.id to programs
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
        val actions = listOf(
            "get_short_epg",
            "get_simple_data_table",
        )
        for (action in actions) {
            val url =
                "$base/player_api.php?username=$userQ&password=$passQ" +
                    "&action=$action&stream_id=$streamId&limit=$limit"
            val body = runCatching { httpGet(url) }.getOrNull() ?: continue
            if (body.length > 512_000 || body.isBlank()) continue
            val listings = parseListingsArray(body) ?: continue
            if (listings.length() == 0) continue
            val out = ArrayList<EpgProgram>(listings.length())
            for (i in 0 until min(listings.length(), limit)) {
                val item = listings.optJSONObject(i) ?: continue
                val title = decodeBase64Maybe(item.optString("title"))
                    ?: decodeBase64Maybe(item.optString("name"))
                    ?: "Program"
                val start = parseEpgDate(
                    item.optString("start_timestamp")
                        .ifBlank { item.optString("start") }
                        .ifBlank { item.optString("time") },
                ) ?: continue
                val end = parseEpgDate(
                    item.optString("end_timestamp")
                        .ifBlank { item.optString("stop_timestamp") }
                        .ifBlank { item.optString("stop") }
                        .ifBlank { item.optString("end") }
                        .ifBlank { item.optString("time_to") },
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
            if (out.isNotEmpty()) return out.sortedBy { it.startMs }
        }
        return emptyList()
    }

    private fun parseListingsArray(body: String): JSONArray? {
        val trimmed = body.trim()
        return try {
            when {
                trimmed.startsWith("{") -> {
                    val obj = JSONObject(trimmed)
                    obj.optJSONArray("epg_listings")
                        ?: obj.optJSONArray("listings")
                        ?: obj.optJSONArray("data")
                }
                trimmed.startsWith("[") -> JSONArray(trimmed)
                else -> null
            }
        } catch (_: Exception) {
            null
        }
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
            val decoded = Base64.decode(s, Base64.DEFAULT)
            val str = String(decoded, Charsets.UTF_8)
            if (str.isNotBlank() && str.any { it.isLetterOrDigit() }) str else s
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
        // XMLTV-ish without space
        parseXmltvDate(s)?.let { return it }
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
}

fun List<EpgProgram>.nowPlaying(nowMs: Long = System.currentTimeMillis()): EpgProgram? =
    firstOrNull { it.contains(nowMs) }

fun List<EpgProgram>.upNext(nowMs: Long = System.currentTimeMillis()): EpgProgram? =
    filter { it.startMs > nowMs }.minByOrNull { it.startMs }

/** Prefer live, else nearest listing (Grid + empty timeline labels). */
fun List<EpgProgram>.nowOrNearest(nowMs: Long = System.currentTimeMillis()): EpgProgram? {
    nowPlaying(nowMs)?.let { return it }
    if (isEmpty()) return null
    // started recently / about to start
    val soon = filter {
        it.endMs > nowMs - 30 * 60_000L && it.startMs < nowMs + 6 * 3600_000L
    }
    if (soon.isNotEmpty()) {
        return soon.minByOrNull { p ->
            when {
                p.contains(nowMs) -> 0L
                p.startMs >= nowMs -> p.startMs - nowMs
                else -> nowMs - p.endMs
            }
        }
    }
    return minByOrNull { abs((it.startMs + it.endMs) / 2 - nowMs) }
}
