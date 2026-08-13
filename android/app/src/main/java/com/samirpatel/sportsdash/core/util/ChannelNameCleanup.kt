package com.samirpatel.sportsdash.core.util

/**
 * Mirrors iOS `ChannelNameCleanup.displayName`.
 * Strip common IPTV quality / codec noise when clean-up is enabled.
 */
object ChannelNameCleanup {
    private val bracket = Regex("""\s*\[.*?\]""")
    private val parenQual = Regex(
        """\s*\((?:4K|UHD|FHD|HD|SD|HEVC|H\.?265|H\.?264|60FPS|50FPS|1080p|720p|2160p)[^)]*\)""",
        RegexOption.IGNORE_CASE,
    )
    private val trailingQual = Regex(
        """\s+(?:4K|UHD|FHD|HD|SD|HEVC|H265|H264|1080P|720P|2160P)\b""",
        RegexOption.IGNORE_CASE,
    )
    private val multiSpace = Regex("""\s{2,}""")

    fun displayName(raw: String, enabled: Boolean = true): String {
        if (!enabled) return raw
        var s = raw
        s = bracket.replace(s, " ")
        s = parenQual.replace(s, " ")
        s = trailingQual.replace(s, " ")
        s = multiSpace.replace(s, " ")
        return s.trim()
    }

    /** Pure canonical key for dedupe / internal use. ALWAYS cleans (ignores display pref).
     * Mirrors Apple dedupe key construction independent of cleanUpNames.
     */
    fun canonicalKey(raw: String): String {
        val cleaned = displayName(raw, enabled = true)
        return cleaned.lowercase().trim().ifBlank { raw.lowercase().trim() }
    }
}
