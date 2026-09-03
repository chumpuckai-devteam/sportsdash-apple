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
 * EPG pipeline (UX-first):
 * 1. Download full xmltv.php **once** to disk (progress by MB/%)
 * 2. Parse after download completes
 * 3. Match to playlist (epg id + display-name + fuzzy name)
 * 4. Cache matched TSV for fast relaunch
 * Optional short-EPG for small open-category fill.
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
        const val MAX_STREAM_BYTES = 1024L * 1024 * 1024
        private const val CACHE_VERSION = 3
        private const val SHORT_EPG_NEGATIVE_TTL_MS = 6 * 3600_000L
    }

    data class LoadResult(
        val programsByChannelId: Map<String, List<EpgProgram>>,
        val status: String,
    )

    private val bulkMutex = Mutex()
    private val shortEpgEmptyAt = HashMap<String, Long>()
    private val shortEpgInFlight = HashSet<String>()
    private var lastGoodBulkUrl: String? = null

    /** Fast Now/Next for open category (Xtream short EPG only). */
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
        // Cap so movie packs don't hang UX. Skip recently-empty hosts and in-flight ids.
        val host = config.host
        val now = System.currentTimeMillis()
        val work = channels.filter { ch ->
            val key = "$host|${ch.id}"
            val emptyAt = shortEpgEmptyAt[key]
            val recentlyEmpty = emptyAt != null && now - emptyAt < SHORT_EPG_NEGATIVE_TTL_MS
            !recentlyEmpty && ch.id !in shortEpgInFlight
        }.take(80)
        work.forEach { shortEpgInFlight.add(it.id) }
        onStatus("Now/Next · ${work.size} channels…")
        val result = linkedMapOf<String, List<EpgProgram>>()
        var missing = work
        var wave = 0
        while (missing.isNotEmpty() && wave < 6) {
            wave++
            val slice = missing.take(20)
            val short = loadXtreamShortBatch(slice, config, limit = 8)
            if (short.isNotEmpty()) {
                for ((k, v) in short) if (v.isNotEmpty()) result[k] = v
                onBatch(result.toMap())
            }
            for (ch in slice) {
                if (short[ch.id].isNullOrEmpty()) {
                    shortEpgEmptyAt["$host|${ch.id}"] = System.currentTimeMillis()
                }
            }
            val attempted = slice.map { it.id }.toSet()
            missing = missing.filter { it.id !in attempted }
            if (short.isEmpty() && wave >= 2) break
            onStatus("Now/Next · ${result.size}/${work.size}")
        }
        work.forEach { shortEpgInFlight.remove(it.id) }
        val status = "Now/Next · ${result.size}/${work.size}"
        onStatus(status)
        onBatch(result.toMap())
        LoadResult(result.toMap(), status)
    }

    /**
     * Full guide: download once → parse → match → cache.
     * User can wait; progress callbacks are phase-based.
     */
    suspend fun loadBulkThenFill(
        channels: List<IptvChannel>,
        config: PlaylistConfig?,
        onStatus: (String) -> Unit = {},
        onBatch: (Map<String, List<EpgProgram>>) -> Unit = {},
    ): LoadResult = withContext(Dispatchers.IO) {
        if (channels.isEmpty()) return@withContext LoadResult(emptyMap(), "No channels")
        if (config == null) return@withContext LoadResult(emptyMap(), "No playlist")

        bulkMutex.withLock {
            var result = linkedMapOf<String, List<EpgProgram>>()

            // Fast TSV cache
            val cached = readTvgCache(config)
            if (!cached.isNullOrEmpty()) {
                onStatus("Matching cached guide (${cached.size} EPG channels)…")
                result = LinkedHashMap(mapXmltv(cached, channels))
                onStatus("Matched ${result.size}/${channels.size} from cache")
                onBatch(result.toMap())
            }

            val coverage = result.size.toFloat() / channels.size.coerceAtLeast(1)
            if (coverage < 0.20f) {
                onStatus("Step 1/3 · Download full TV guide (one-time)…")
                val byTvg = obtainParsedXmltv(config, onStatus)
                if (!byTvg.isNullOrEmpty()) {
                    onStatus("Step 3/3 · Matching ${byTvg.size} EPG channels to playlist…")
                    writeTvgCache(config, byTvg)
                    val mapped = mapXmltv(byTvg, channels)
                    for ((k, v) in mapped) {
                        val old = result[k]
                        if (old == null || v.size > old.size) result[k] = v
                    }
                    onStatus("Matched ${result.size}/${channels.size} channels")
                    onBatch(result.toMap())
                } else if (result.isEmpty()) {
                    onStatus("Full guide unavailable from provider")
                }
            }

            // Limited short fill — never thrash 13k movie channels
            if (config.type == PlaylistType.XTREAM &&
                config.username.isNotBlank() &&
                config.password.isNotBlank()
            ) {
                var missing = channels.filter { result[it.id].isNullOrEmpty() }.take(300)
                if (missing.isNotEmpty() && result.size < channels.size * 0.5) {
                    val total = missing.size
                    var wave = 0
                    while (missing.isNotEmpty() && wave < 10) {
                        wave++
                        val slice = missing.take(30)
                        onStatus(
                            "Optional gap fill ${result.size}/${channels.size} · " +
                                "${total - missing.size + slice.size}/$total…",
                        )
                        val short = loadXtreamShortBatch(slice, config, limit = 6)
                        if (short.isNotEmpty()) {
                            for ((k, v) in short) if (v.isNotEmpty()) result[k] = v
                            onBatch(result.toMap())
                        }
                        val attempted = slice.map { it.id }.toSet()
                        missing = missing.filter { it.id !in attempted }
                        if (short.isEmpty() && wave >= 2) break
                    }
                }
            }

            val status = "Guide ready · ${result.size}/${channels.size} channels with listings"
            onStatus(status)
            onBatch(result.toMap())
            LoadResult(result.toMap(), status)
        }
    }

    // region Download once + parse

    private fun obtainParsedXmltv(
        config: PlaylistConfig,
        onStatus: (String) -> Unit,
    ): Map<String, List<EpgProgram>>? {
        val xmlFile = xmlCacheFile(config)
        val fresh = xmlFile != null && xmlFile.isFile && xmlFile.length() > 1024 &&
            System.currentTimeMillis() - xmlFile.lastModified() < 18 * 3600_000L

        if (fresh && xmlFile != null) {
            onStatus("Step 2/3 · Parsing saved guide (${formatMb(xmlFile.length())})…")
            val parsed = parseXmltvFile(xmlFile)
            if (parsed.isNotEmpty()) {
                onStatus("Parsed ${parsed.size} EPG channels from disk")
                return parsed
            }
        }

        val urls = bulkXmltvUrls(config)
        for ((index, url) in urls.withIndex()) {
            onStatus("Step 1/3 · Streaming full guide… (${index + 1}/${urls.size})")
            val parsed = runCatching { streamParseXmltv(url, onStatus) }.getOrNull()
            if (!parsed.isNullOrEmpty()) {
                rememberGoodUrl(config, url)
                onStatus("Parsed ${parsed.size} EPG channels")
                return parsed
            }
        }
        return null
    }

    private fun streamParseXmltv(urlString: String, onStatus: (String) -> Unit): Map<String, List<EpgProgram>>? {
        val req = Request.Builder()
            .url(urlString)
            .header("Accept", "application/xml, text/xml, */*")
            .header("User-Agent", "SportsDash/1.0")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) return null
            val body = resp.body ?: return null
            onStatus("Step 2/3 · Parsing guide stream…")
            return body.byteStream().use { parseXmltv(it) }
        }
    }

    private fun formatMb(bytes: Long): String =
        String.format(Locale.US, "%.1f MB", bytes / 1_048_576.0)

    private fun downloadXmltvToFile(
        urlString: String,
        dest: File,
        onStatus: (String) -> Unit,
    ): Boolean {
        val req = Request.Builder()
            .url(urlString)
            .header("Accept", "application/xml, text/xml, */*")
            .header("User-Agent", "SportsDash/1.0")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) return false
            val body = resp.body ?: return false
            val contentLength = body.contentLength()
            val tmp = File(dest.parentFile ?: cacheDir, dest.name + ".part")
            try {
                body.byteStream().use { input ->
                    tmp.outputStream().use { output ->
                        val buf = ByteArray(64 * 1024)
                        var total = 0L
                        var lastReport = 0L
                        while (true) {
                            val n = input.read(buf)
                            if (n <= 0) break
                            total += n
                            if (total > MAX_STREAM_BYTES) {
                                onStatus("Guide stream exceeded 1 GB abort guard")
                                return false
                            }
                            output.write(buf, 0, n)
                            if (total - lastReport > 2_000_000L) {
                                lastReport = total
                                val msg = if (contentLength > 0) {
                                    val pct = (100.0 * total / contentLength).toInt().coerceIn(0, 99)
                                    "Step 1/3 · Downloading… $pct% (${formatMb(total)})"
                                } else {
                                    "Step 1/3 · Downloading… ${formatMb(total)}"
                                }
                                onStatus(msg)
                            }
                        }
                        if (total <= 0) return false
                    }
                }
                if (dest.exists()) dest.delete()
                if (!tmp.renameTo(dest)) {
                    tmp.copyTo(dest, overwrite = true)
                    tmp.delete()
                }
                return dest.isFile && dest.length() > 0
            } catch (_: Exception) {
                tmp.delete()
                return false
            }
        }
    }

    // endregion

    // region Cache files

    private fun cacheKey(config: PlaylistConfig): String {
        val host = when (config.type) {
            PlaylistType.XTREAM -> config.host.trim().lowercase(Locale.US)
            PlaylistType.M3U -> config.m3uUrl.trim().lowercase(Locale.US).take(120)
        }
        val user = config.username.trim().lowercase(Locale.US)
        return (host + "|" + user).hashCode().toUInt().toString(16)
    }

    private fun ensureCacheDir(): File? {
        val dir = cacheDir ?: return null
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun xmlCacheFile(config: PlaylistConfig): File? {
        val dir = ensureCacheDir() ?: return null
        return File(dir, "xmltv-v$CACHE_VERSION-${cacheKey(config)}.xml")
    }

    private fun tvgCacheFile(config: PlaylistConfig): File? {
        val dir = ensureCacheDir() ?: return null
        return File(dir, "tvg-v$CACHE_VERSION-${cacheKey(config)}.tsv")
    }

    private fun readTvgCache(config: PlaylistConfig): Map<String, List<EpgProgram>>? {
        val file = tvgCacheFile(config) ?: return null
        if (!file.isFile || file.length() < 32) return null
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
                        val title = parts[3]
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
                        val title = p.title.replace('\t', ' ').replace('\n', ' ')
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

    // region URLs

    private fun bulkXmltvUrls(config: PlaylistConfig): List<String> {
        val out = ArrayList<String>()
        lastGoodBulkUrl(config)?.let { out.add(it) }
        when (config.type) {
            PlaylistType.XTREAM ->
                out.addAll(xtreamXmltvUrls(config.host, config.username, config.password))
            PlaylistType.M3U ->
                xtreamXmltvUrlsFromAnyUrl(config.m3uUrl)?.let { out.addAll(it) }
        }
        return out.distinct()
    }

    private fun lastGoodBulkUrl(config: PlaylistConfig): String? {
        lastGoodBulkUrl?.let { return it }
        val f = lastGoodUrlFile(config) ?: return null
        return runCatching { f.readText().trim().takeIf { it.startsWith("http") } }.getOrNull()
            ?.also { lastGoodBulkUrl = it }
    }

    private fun rememberGoodUrl(config: PlaylistConfig, url: String) {
        lastGoodBulkUrl = url
        lastGoodUrlFile(config)?.writeText(url)
    }

    private fun lastGoodUrlFile(config: PlaylistConfig): File? {
        val dir = ensureCacheDir() ?: return null
        return File(dir, "last-xmltv-${cacheKey(config)}.txt")
    }

    private fun defaultPort(scheme: String): Int =
        if (scheme.equals("https", ignoreCase = true)) 443 else 80

    private fun xtreamXmltvUrls(hostField: String, user: String, pass: String): List<String> {
        val base = normalizeBase(hostField) ?: return emptyList()
        val query = "username=${enc(user)}&password=${enc(pass)}"
        val out = ArrayList<String>()
        for (root in httpsPreferredRoots(base)) {
            out.add("$root/xmltv.php?$query")
        }
        return out
    }

    private fun xtreamXmltvUrlsFromAnyUrl(raw: String): List<String>? {
        val url = raw.trim().toHttpUrlOrNull() ?: return null
        val user = url.queryParameter("username") ?: return null
        val pass = url.queryParameter("password") ?: return null
        if (user.isBlank() || pass.isBlank()) return null
        val base = buildString {
            append(url.scheme); append("://"); append(url.host)
            if (url.port != defaultPort(url.scheme)) {
                append(':'); append(url.port)
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

    // endregion

    // region Parse + map

    private fun parseXmltvFile(file: File): Map<String, List<EpgProgram>> =
        FileInputStream(file).use { parseXmltv(it) }

    /** Public for chunk-boundary tests. 1 GB abort while reading. */
    fun parseXmltv(input: java.io.InputStream): Map<String, List<EpgProgram>> {
        val now = System.currentTimeMillis()
        val windowStart = now - HOURS_BEHIND * 3600_000L
        val windowEnd = now + HOURS_AHEAD * 3600_000L
        val map = LinkedHashMap<String, MutableList<EpgProgram>>()
        val displayNames = LinkedHashMap<String, MutableList<String>>()
        val counting = object : java.io.FilterInputStream(input) {
            var total = 0L
            override fun read(): Int {
                val n = super.read()
                if (n >= 0) {
                    total += 1
                    if (total > MAX_STREAM_BYTES) error("guide stream exceeded 1 GB")
                }
                return n
            }
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                val n = super.read(b, off, len)
                if (n > 0) {
                    total += n
                    if (total > MAX_STREAM_BYTES) error("guide stream exceeded 1 GB")
                }
                return n
            }
        }

        counting.use { fis ->
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
                                capture = "display-name"; text.clear()
                            }
                            "programme" -> {
                                inProgramme = true
                                channelId = parser.getAttributeValue(null, "channel")
                                startMs = parseXmltvDate(parser.getAttributeValue(null, "start"))
                                endMs = parseXmltvDate(parser.getAttributeValue(null, "stop"))
                                title = null; category = null; desc = null
                            }
                            "title" -> if (inProgramme) { capture = "title"; text.clear() }
                            "category" -> if (inProgramme) { capture = "category"; text.clear() }
                            "desc" -> if (inProgramme) { capture = "desc"; text.clear() }
                        }
                    }
                    XmlPullParser.TEXT -> if (capture != null) text.append(parser.text)
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
                            if (ch != null && s != null && e != null && e > s &&
                                e > windowStart && s < windowEnd
                            ) {
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

        // Alias under display names + normalized forms
        val aliased = LinkedHashMap<String, List<EpgProgram>>(map.size * 3)
        for ((id, list) in map) {
            putAllKeys(aliased, id, list)
            for (dn in displayNames[id].orEmpty()) {
                putAllKeys(aliased, dn, list)
            }
        }
        return aliased
    }

    private fun putAllKeys(
        target: MutableMap<String, List<EpgProgram>>,
        key: String,
        list: List<EpgProgram>,
    ) {
        if (key.isBlank()) return
        target.putIfAbsent(key, list)
        target.putIfAbsent(key.lowercase(Locale.US), list)
        target.putIfAbsent(normalizeName(key), list)
        target.putIfAbsent(slug(key), list)
    }

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
                val digits = rest.replace(":", "").replace(" ", "")
                val sign = when {
                    digits.startsWith("+") || digits.startsWith("-") -> digits.first()
                    else -> '+'
                }
                val num = digits.dropWhile { it == '+' || it == '-' }.padStart(4, '0').take(4)
                TimeZone.getTimeZone("GMT$sign${num.take(2)}:${num.drop(2)}")
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

        // Direct index
        val index = HashMap<String, List<EpgProgram>>(byTvg.size * 2)
        // Normalized slug → programmes (for fuzzy)
        val byNorm = HashMap<String, List<EpgProgram>>(byTvg.size)
        for ((k, v) in byTvg) {
            if (v.isEmpty()) continue
            index[k] = v
            index[k.lowercase(Locale.US)] = v
            val n = normalizeName(k)
            if (n.length >= 4) {
                index[n] = v
                // Prefer longer key when colliding
                val prev = byNorm[n]
                if (prev == null || k.length > (prev.firstOrNull()?.channelKey?.length ?: 0)) {
                    byNorm[n] = v
                }
            }
        }

        val out = LinkedHashMap<String, List<EpgProgram>>()
        for (ch in channels) {
            val candidates = buildList {
                ch.epgChannelId?.let {
                    add(it); add(it.lowercase(Locale.US)); add(normalizeName(it)); add(slug(it))
                }
                add(ch.name); add(ch.name.lowercase(Locale.US))
                add(normalizeName(ch.name)); add(slug(ch.name))
                ch.streamId?.let { add(it) }
            }

            var hit: List<EpgProgram>? = null
            for (c in candidates) {
                if (c.isBlank()) continue
                hit = index[c] ?: index[c.lowercase(Locale.US)] ?: index[normalizeName(c)]
                if (!hit.isNullOrEmpty()) break
            }

            // Fuzzy: normalized name contains / contained
            if (hit.isNullOrEmpty()) {
                val ns = normalizeName(ch.name)
                if (ns.length >= 6) {
                    hit = byNorm[ns]
                    if (hit.isNullOrEmpty()) {
                        hit = byNorm.entries.firstOrNull { (k, _) ->
                            k.length >= 6 && (k.contains(ns) || ns.contains(k))
                        }?.value
                    }
                }
            }

            if (!hit.isNullOrEmpty()) {
                out[ch.id] = hit.map { it.copy(channelKey = ch.id) }.take(MAX_PER_CHANNEL)
            }
        }
        return out
    }

    /** Strip HD/UK noise so "Sky Cinema Action HD" ≈ "Sky.Cinema.Action.uk". */
    private fun normalizeName(s: String): String =
        s.lowercase(Locale.US)
            .replace(Regex("\\b(hd|fhd|uhd|sd|4k|8k|hevc|hdr|hq|h265|h264)\\b"), " ")
            .replace(Regex("\\b(uk|us|usa|ca|eu|au)\\b"), " ")
            .replace(Regex("[^a-z0-9]+"), "")

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
        val out = LinkedHashMap<String, List<EpgProgram>>()
        var i = 0
        while (i < channels.size) {
            val end = min(i + 10, channels.size)
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
            for ((id, programs) in parts) if (programs.isNotEmpty()) out[id] = programs
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
        for (action in listOf("get_short_epg", "get_simple_data_table")) {
            val url =
                "$base/player_api.php?username=$userQ&password=$passQ" +
                    "&action=$action&stream_id=$streamId&limit=$limit"
            val body = runCatching { httpGet(url) }.getOrNull() ?: continue
            if (body.isBlank() || body.length > 512_000) continue
            val listings = parseListingsArray(body) ?: continue
            if (listings.length() == 0) continue
            val out = ArrayList<EpgProgram>()
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

fun List<EpgProgram>.nowOrNearest(nowMs: Long = System.currentTimeMillis()): EpgProgram? {
    nowPlaying(nowMs)?.let { return it }
    if (isEmpty()) return null
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
