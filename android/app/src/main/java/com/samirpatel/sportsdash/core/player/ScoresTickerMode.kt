package com.samirpatel.sportsdash.core.player

/**
 * Player scores ticker visibility.
 * Cycles: Off → Fade with chrome → Persistent.
 */
enum class ScoresTickerMode {
    OFF,
    FADE,
    PERSISTENT,
    ;

    val shortLabel: String
        get() = when (this) {
            OFF -> "OFF"
            FADE -> "FADE"
            PERSISTENT -> "PIN"
        }

    val contentDescription: String
        get() = when (this) {
            OFF -> "Scores ticker off"
            FADE -> "Scores ticker fades with controls"
            PERSISTENT -> "Scores ticker always on"
        }

    fun next(): ScoresTickerMode = when (this) {
        OFF -> FADE
        FADE -> PERSISTENT
        PERSISTENT -> OFF
    }

    companion object {
        fun fromStorage(raw: String?, legacyBool: Boolean?): ScoresTickerMode {
            when (raw?.trim()?.lowercase()) {
                "off", "0", "false" -> return OFF
                "fade", "auto", "1" -> return FADE
                "persistent", "pin", "on", "always", "2", "true" -> return PERSISTENT
            }
            // Migrate old boolean pref: true → FADE (chrome-linked), false → OFF
            return when (legacyBool) {
                true -> FADE
                false -> OFF
                null -> FADE
            }
        }
    }
}
