package com.samirpatel.sportsdash.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val VoidBlack = Color(0xFF0A0A0B)
val Gold = Color(0xFFD4A017)
val Panel = Color(0xFF16161A)
val LiveMint = Color(0xFF3DDC84)
val Muted = Color(0xFF9CA3AF)
val TextPrimary = Color(0xFFF3F4F6)
val Danger = Color(0xFFEF4444)

private val DarkColors = darkColorScheme(
    primary = Gold,
    onPrimary = VoidBlack,
    background = VoidBlack,
    surface = Panel,
    onBackground = TextPrimary,
    onSurface = TextPrimary,
    secondary = LiveMint,
    error = Danger,
)

@Composable
fun SportsDashTheme(content: @Composable () -> Unit) {
    // Always dark product chrome for v1 dogfood
    MaterialTheme(
        colorScheme = DarkColors,
        content = content,
    )
}
