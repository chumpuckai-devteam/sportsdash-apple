package com.samirpatel.sportsdash.core.epg

/**
 * Single guide listing block — mirrors iOS EpgProgram.
 * Times are epoch millis (device local interpretation for display).
 */
data class EpgProgram(
    val channelKey: String,
    val title: String,
    val startMs: Long,
    val endMs: Long,
    val description: String? = null,
    val category: String? = null,
) {
    fun contains(nowMs: Long = System.currentTimeMillis()): Boolean =
        nowMs in startMs until endMs

    val durationMs: Long get() = (endMs - startMs).coerceAtLeast(0)
}
