package com.samirpatel.sportsdash.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import com.samirpatel.sportsdash.R

val VoidBlack = Color(0xFF070910)
val Panel = Color(0xFF0F131A)
val PanelElevated = Color(0xFF171C24)
val Border = Color(0xFF2A3340)
val Gold = Color(0xFFFFB800)
val GoldDim = Color(0xFFB8860B)
val LiveMint = Color(0xFF00E5A0)
val Danger = Color(0xFFFF3B5C)
val Muted = Color(0xFF8B96A8)
val TextPrimary = Color(0xFFF2F4F7)
val TextSecondary = Color(0xFFB8C0CE)
val GridDot = Color(0xFF141B28)
val LedGlow = Gold.copy(alpha = 0.80f)
val LiveGlow = LiveMint.copy(alpha = 0.75f)

val PanelGradient = Brush.verticalGradient(listOf(PanelElevated, Panel))

val BebasNeue = FontFamily(Font(R.font.bebas_neue, FontWeight.Normal))
val OrbitronBlack = FontFamily(Font(R.font.orbitron_black, FontWeight.Black))
val SpaceMono = FontFamily(
    Font(R.font.space_mono, FontWeight.Normal),
    Font(R.font.space_mono_bold, FontWeight.Bold),
)

val LedShadow = Shadow(color = LedGlow, blurRadius = 12f)
val LiveShadow = Shadow(color = LiveGlow, blurRadius = 10f)

val ScreenInset = 12.dp
val ScoreRowHeight = 58.dp
val GuideRowHeight = 62.dp
val SettingsRowHeight = 50.dp
val TabBarHeight = 80.dp
val TeamEdgeWidth = 5.dp

private val DarkColors = darkColorScheme(
    primary = Gold,
    onPrimary = VoidBlack,
    background = VoidBlack,
    surface = Panel,
    onBackground = TextPrimary,
    onSurface = TextPrimary,
    secondary = LiveMint,
    error = Danger,
    outline = Border,
)

@Composable
fun SportsDashTheme(content: @Composable () -> Unit) {
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? android.app.Activity)?.window ?: return@SideEffect
            window.navigationBarColor = android.graphics.Color.parseColor("#FF0F131A")
            window.statusBarColor = android.graphics.Color.parseColor("#00000000")
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = false
        }
    }
    MaterialTheme(
        colorScheme = DarkColors,
        content = content,
    )
}

fun parseTeamHex(hex: String?): Color? {
    val s = hex?.trim()?.removePrefix("#") ?: return null
    if (s.length != 6) return null
    return runCatching { Color(android.graphics.Color.parseColor("#$s")) }.getOrNull()
}

fun hashedAccent(key: String): Color {
    var hash = 5381L
    for (b in key.lowercase().toByteArray()) {
        hash = ((hash shl 5) + hash) + (b.toLong() and 0xFF)
    }
    val hue = ((hash % 360 + 360) % 360).toFloat()
    return Color.hsv(hue, 0.70f, 0.38f)
}
