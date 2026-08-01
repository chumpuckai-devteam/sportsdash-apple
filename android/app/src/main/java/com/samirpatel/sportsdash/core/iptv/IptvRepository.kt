package com.samirpatel.sportsdash.core.iptv

import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.model.PlaylistConfig
import com.samirpatel.sportsdash.core.model.PlaylistType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import java.util.concurrent.TimeUnit

/**
 * Xtream Codes + M3U loader — port of iOS IptvService essentials.
 * Live streams preferred as TS (panel default).
 */
class IptvRepository(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .followRedirects(true)
        .build(),
) {
    suspend fun loadChannels(config: PlaylistConfig): Result<List<IptvChannel>> = withContext(Dispatchers.IO) {
        runCatching {
            when (config.type) {
                PlaylistType.XTREAM -> loadXtream(config)
                PlaylistType.M3U -> loadM3u(config.m3uUrl)
            }
        }
    }

    private fun loadXtream(config: PlaylistConfig): List<IptvChannel> {
        val base = normalizeHost(config.host)
        require(config.username.isNotBlank() && config.password.isNotBlank()) {
            "Username and password required"
        }
        val playerApi = "$base/player_api.php?username=${enc(config.username)}&password=${enc(config.password)}&action=get_live_streams"
        val body = httpGet(playerApi)
        val arr = JSONArray(body)
        val out = ArrayList<IptvChannel>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val streamId = o.optString("stream_id").ifBlank { o.optInt("stream_id").toString() }
            if (streamId.isBlank() || streamId == "0") continue
            val name = o.optString("name").ifBlank { "Channel $streamId" }
            val epg = o.optString("epg_channel_id").takeIf { it.isNotBlank() }
            val logo = o.optString("stream_icon").takeIf { it.isNotBlank() }
            val group = o.optString("category_name").takeIf { it.isNotBlank() }
                ?: o.optString("category_id").takeIf { it.isNotBlank() }
            // Prefer raw TS live path (matches iOS preferredLiveFormat = .ts)
            val url = "$base/live/${enc(config.username)}/${enc(config.password)}/$streamId"
            out.add(
                IptvChannel(
                    id = "xtream-$streamId",
                    name = name,
                    url = url,
                    group = group,
                    logo = logo,
                    epgChannelId = epg,
                    streamId = streamId,
                ),
            )
        }
        return out
    }

    private fun loadM3u(url: String): List<IptvChannel> {
        require(url.isNotBlank()) { "M3U URL required" }
        val body = httpGet(url)
        return parseM3u(body)
    }

    fun parseM3u(body: String): List<IptvChannel> {
        val lines = body.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
        val out = mutableListOf<IptvChannel>()
        var i = 0
        var idx = 0
        while (i < lines.size) {
            val line = lines[i]
            if (line.startsWith("#EXTINF", ignoreCase = true)) {
                val name = line.substringAfter(",", line).trim().ifBlank { "Channel ${idx + 1}" }
                val group = Regex("""group-title="([^"]*)"""", RegexOption.IGNORE_CASE)
                    .find(line)?.groupValues?.getOrNull(1)
                val logo = Regex("""tvg-logo="([^"]*)"""", RegexOption.IGNORE_CASE)
                    .find(line)?.groupValues?.getOrNull(1)
                val epg = Regex("""tvg-id="([^"]*)"""", RegexOption.IGNORE_CASE)
                    .find(line)?.groupValues?.getOrNull(1)
                val url = lines.getOrNull(i + 1)?.takeIf { !it.startsWith("#") }
                if (url != null) {
                    out.add(
                        IptvChannel(
                            id = "m3u-${idx++}",
                            name = name,
                            url = url,
                            group = group,
                            logo = logo,
                            epgChannelId = epg,
                        ),
                    )
                    i += 2
                    continue
                }
            }
            i++
        }
        return out
    }

    /** Build playback URL candidates: preferred first, then alternate extension. */
    fun playbackCandidates(url: String, preferTs: Boolean = true): List<String> {
        val list = linkedSetOf<String>()
        list.add(url)
        val alt = when {
            url.contains(".m3u8", ignoreCase = true) ->
                url.replace(".m3u8", ".ts", ignoreCase = true)
            url.endsWith(".ts", ignoreCase = true) ->
                url.replace(".ts", ".m3u8", ignoreCase = true)
            url.contains("/live/") && !url.contains(".") ->
                if (preferTs) "$url.ts" else "$url.m3u8"
            else -> null
        }
        if (alt != null) list.add(alt)
        // Xtream without extension: also try .m3u8
        if (url.contains("/live/") && !url.substringAfterLast('/').contains('.')) {
            list.add("$url.m3u8")
            list.add("$url.ts")
        }
        return if (preferTs) {
            list.sortedBy { if (StreamHints.isHls(it)) 1 else 0 }
        } else {
            list.sortedBy { if (StreamHints.isHls(it)) 0 else 1 }
        }
    }

    private fun httpGet(url: String): String {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "VLC/3.0.21 LibVLC/3.0.21")
            .header("Accept", "*/*")
            .get()
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code} for $url")
            return resp.body?.string().orEmpty()
        }
    }

    private fun normalizeHost(host: String): String {
        var h = host.trim().trimEnd('/')
        if (!h.startsWith("http://") && !h.startsWith("https://")) {
            h = "http://$h"
        }
        // Strip path like /player_api.php if pasted
        val u = h.toHttpUrlOrNull()
        return if (u != null) {
            buildString {
                append(u.scheme)
                append("://")
                append(u.host)
                if (u.port != u.defaultPort) append(":").append(u.port)
            }
        } else h
    }

    private fun enc(s: String): String = java.net.URLEncoder.encode(s, Charsets.UTF_8.name())
}

private object StreamHints {
    fun isHls(url: String) = url.contains("m3u8", ignoreCase = true)
}

/** Optional auth probe. */
fun PlaylistConfig.describe(): String = when (type) {
    PlaylistType.XTREAM -> "$name · Xtream · $host"
    PlaylistType.M3U -> "$name · M3U"
}
