package com.samirpatel.sportsdash.core.model

import java.util.UUID

/** Mirrors iOS IptvChannel / playlist config. */
data class IptvChannel(
    val id: String,
    val name: String,
    val url: String,
    val group: String? = null,
    val logo: String? = null,
    val epgChannelId: String? = null,
    val streamId: String? = null,
)

enum class PlaylistType { XTREAM, M3U }

data class PlaylistConfig(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val type: PlaylistType,
    /** Host only or full base URL (https://panel.example.com) */
    val host: String = "",
    val username: String = "",
    val password: String = "",
    /** Full M3U URL when type == M3U */
    val m3uUrl: String = "",
)

enum class StreamContainer {
    TS, HLS, UNKNOWN;

    companion object {
        /** Best-effort detect from URL — same rules as iOS StreamContainer. */
        fun detect(urlString: String): StreamContainer {
            val raw = urlString.trim()
            if (raw.isEmpty()) return UNKNOWN
            val lower = raw.lowercase()
            val path = try {
                val u = java.net.URI(raw)
                (u.path.orEmpty() + " " + (u.query.orEmpty())).lowercase()
            } catch (_: Exception) {
                lower
            }
            if (path.contains(".m3u8") || path.contains("m3u8") || path.contains("format=hls") ||
                path.contains("/hls/") || path.contains("type=m3u")
            ) {
                return HLS
            }
            if (path.contains(".ts") || path.contains("format=ts") || path.contains("extension=ts") ||
                (path.contains("/live/") && !path.contains("m3u8"))
            ) {
                return TS
            }
            if (lower.contains("/live/") && !lower.contains("m3u8")) return TS
            return UNKNOWN
        }
    }
}
