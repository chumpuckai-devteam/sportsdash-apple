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

data class ChannelLoadResult(
    val channels: List<IptvChannel>,
    /** Category display names in **provider order** (not alphabetical). */
    val categoryOrder: List<String>,
)

/**
 * Xtream Codes + M3U loader — port of iOS IptvService essentials.
 * Live streams preferred as TS (panel default).
 * Categories keep panel order from get_live_categories / first-seen M3U groups.
 */
class IptvRepository(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS)
        .followRedirects(true)
        .build(),
) {
    suspend fun loadChannels(config: PlaylistConfig): Result<ChannelLoadResult> =
        withContext(Dispatchers.IO) {
            runCatching {
                when (config.type) {
                    PlaylistType.XTREAM -> loadXtream(config)
                    PlaylistType.M3U -> loadM3u(config.m3uUrl)
                }
            }
        }

    private fun loadXtream(config: PlaylistConfig): ChannelLoadResult {
        val base = normalizeHost(config.host)
        require(config.username.isNotBlank() && config.password.isNotBlank()) {
            "Username and password required"
        }
        val user = enc(config.username)
        val pass = enc(config.password)

        // LinkedHashMap preserves get_live_categories order from the panel
        val categoryNames = linkedMapOf<String, String>()
        runCatching {
            val catBody = httpGet(
                "$base/player_api.php?username=$user&password=$pass&action=get_live_categories",
            )
            val cats = JSONArray(catBody)
            for (i in 0 until cats.length()) {
                val c = cats.optJSONObject(i) ?: continue
                val id = c.optString("category_id").ifBlank { c.optInt("category_id").toString() }
                val name = c.optString("category_name").ifBlank { id }
                if (id.isNotBlank()) categoryNames[id] = name
            }
        }

        val playerApi =
            "$base/player_api.php?username=$user&password=$pass&action=get_live_streams"
        val body = httpGet(playerApi)
        val arr = JSONArray(body)
        val out = ArrayList<IptvChannel>(arr.length())
        val seenGroups = linkedSetOf<String>()

        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val streamId = o.optString("stream_id").ifBlank { o.optInt("stream_id").toString() }
            if (streamId.isBlank() || streamId == "0") continue
            val name = o.optString("name").ifBlank { "Channel $streamId" }
            val epg = o.optString("epg_channel_id").takeIf { it.isNotBlank() }
            val logo = o.optString("stream_icon").takeIf { it.isNotBlank() }
            val catId = o.optString("category_id").ifBlank { o.optInt("category_id").toString() }
            val group = o.optString("category_name").takeIf { it.isNotBlank() }
                ?: categoryNames[catId]
                ?: catId.takeIf { it.isNotBlank() }
            if (!group.isNullOrBlank()) seenGroups.add(group)
            val url = "$base/live/$user/$pass/$streamId"
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

        // Provider category order first; append any group only seen on streams
        val ordered = ArrayList<String>()
        for (name in categoryNames.values) {
            if (name in seenGroups && name !in ordered) ordered.add(name)
        }
        for (g in seenGroups) {
            if (g !in ordered) ordered.add(g)
        }
        return ChannelLoadResult(channels = out, categoryOrder = ordered)
    }

    private fun loadM3u(url: String): ChannelLoadResult {
        require(url.isNotBlank()) { "M3U URL required" }
        val body = httpGet(url)
        val channels = parseM3u(body)
        val order = channels.mapNotNull { it.group }.filter { it.isNotBlank() }.distinct()
        return ChannelLoadResult(channels = channels, categoryOrder = order)
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
                val streamUrl = lines.getOrNull(i + 1)?.takeIf { !it.startsWith("#") }
                if (streamUrl != null) {
                    out.add(
                        IptvChannel(
                            id = "m3u-${idx++}",
                            name = name,
                            url = streamUrl,
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

    fun playbackCandidates(url: String, preferTs: Boolean = true): List<String> {
        val list = linkedSetOf<String>()
        list.add(url)
        val alt = when {
            url.contains(".m3u8", ignoreCase = true) ->
                url.replace(".m3u8", ".ts", ignoreCase = true)
            url.endsWith(".ts", ignoreCase = true) ->
                url.replace(Regex("""\.ts$""", RegexOption.IGNORE_CASE), ".m3u8")
            url.contains("/live/") && !url.contains(".") -> "$url.ts"
            else -> null
        }
        if (alt != null && alt != url) {
            if (preferTs && alt.endsWith(".ts", true)) {
                list.clear()
                list.add(alt)
                list.add(url)
            } else {
                list.add(alt)
            }
        }
        return list.toList()
    }

    private fun normalizeHost(host: String): String {
        var h = host.trim().trimEnd('/')
        if (!h.startsWith("http://") && !h.startsWith("https://")) {
            h = "https://$h"
        }
        val url = h.toHttpUrlOrNull()
            ?: error("Invalid host URL")
        val scheme = url.scheme
        val default = if (scheme == "https") 443 else 80
        val portPart = if (url.port != default) ":${url.port}" else ""
        return "$scheme://${url.host}$portPart"
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

fun PlaylistConfig.describe(): String = when (type) {
    PlaylistType.XTREAM -> "Xtream · $name"
    PlaylistType.M3U -> "M3U · $name"
}
