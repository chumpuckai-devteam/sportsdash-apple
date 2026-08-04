package com.samirpatel.sportsdash.ui

import android.app.Activity
import android.content.res.Configuration
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Sports
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.zIndex
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.player.VlcPlayerController
import com.samirpatel.sportsdash.core.player.createVlcVideoLayout
import com.samirpatel.sportsdash.core.sports.Game
import coil.compose.AsyncImage
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.systemGestureExclusion
import androidx.compose.ui.input.pointer.pointerInput

/**
 * Fullscreen player:
 * - Native system Back / Home / Recents (bars stay visible; no immersive hide)
 * - System Back exits player via BackHandler (no custom back chip)
 * - Play / pause, mute, rejoin live
 * - Channel title + engine / LIVE chips
 * - Top live scores ticker (variant D / NFL-style; logos when available)
 * - Chrome auto-hides after idle; tap video to restore (S-AND.FB.13)
 * - Landscape ticker scrolls: systemGestureExclusion + tap-only video layer (S-AND.FB.10)
 *
 * VLC uses TextureView so overlays receive taps (SurfaceView was eating the X).
 */
@Composable
fun PlayerScreen(
    channel: IptvChannel,
    url: String,
    engineLabel: String,
    liveGames: List<Game>,
    currentGameId: String?,
    showScoresTicker: Boolean,
    nowTitle: String?,
    nextTitle: String?,
    onClose: () -> Unit,
    onPopOut: () -> Unit = {},
    onTickerGame: (Game) -> Unit,
    onReplay: () -> Unit,
    onToggleScoresTicker: () -> Unit,
    displayName: String = channel.name,
    favoriteTeamIds: Set<String> = emptySet(),
) {
    val context = LocalContext.current
    val view = LocalView.current
    val controller = remember { VlcPlayerController(context) }
    var chromeVisible by remember { mutableStateOf(true) }
    /** Bumped to restart the idle hide timer while chrome is shown. */
    var chromeIdleEpoch by remember { mutableIntStateOf(0) }
    var isPlaying by remember { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(false) }
    val landscape =
        LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE

    fun noteChromeInteraction() {
        if (chromeVisible) chromeIdleEpoch++
    }

    fun toggleChrome() {
        if (chromeVisible) {
            chromeVisible = false
        } else {
            chromeVisible = true
            chromeIdleEpoch++
        }
    }

    // Auto-fade title/controls/ticker after idle (tap video to restore). Back stays reachable.
    LaunchedEffect(chromeVisible, chromeIdleEpoch) {
        if (!chromeVisible) return@LaunchedEffect
        delay(CHROME_IDLE_HIDE_MS)
        chromeVisible = false
    }

    // Keep native system Back / Home / Recents visible (gesture or 3-button).
    // Edge-to-edge draw only — do NOT immersive-hide bars.
    DisposableEffect(Unit) {
        val activity = context as? Activity
        val window = activity?.window
        val insetsController = window?.let { WindowCompat.getInsetsController(it, view) }
        insetsController?.let {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            it.show(WindowInsetsCompat.Type.systemBars())
            it.isAppearanceLightStatusBars = false
            it.isAppearanceLightNavigationBars = false
        }
        onDispose {
            insetsController?.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    // System Back / predictive back → leave player
    BackHandler(onBack = onClose)

    DisposableEffect(url) {
        if (url.isNotBlank()) {
            controller.play(url)
            isPlaying = true
        }
        onDispose { }
    }
    DisposableEffect(Unit) {
        onDispose { controller.release() }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        AndroidView(
            factory = { ctx ->
                createVlcVideoLayout(ctx).also { layout ->
                    controller.attach(layout)
                    if (url.isNotBlank()) controller.play(url)
                }
            },
            modifier = Modifier.fillMaxSize(),
            update = { layout ->
                controller.attach(layout)
            },
        )

        // Tap-only video hit target — never claims horizontal drags meant for the ticker.
        // Landscape bottom reserve clears compact ticker (label + cards + pad).
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(
                    // Reserve space under top ticker + status
                    top = if (landscape) 108.dp else 132.dp,
                    bottom = if (landscape) 96.dp else 120.dp,
                )
                .pointerInput(Unit) {
                    detectTapGestures {
                        toggleChrome()
                    }
                },
        )

        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .zIndex(10f)
                .statusBarsPadding()
                .background(
                    if (chromeVisible) {
                        Brush.verticalGradient(
                            listOf(Color.Black.copy(alpha = 0.85f), Color.Transparent),
                        )
                    } else {
                        Brush.verticalGradient(
                            listOf(Color.Black.copy(alpha = 0.35f), Color.Transparent),
                        )
                    },
                )
                .padding(horizontal = 8.dp, vertical = 6.dp),
        ) {
            // No custom Back — use system Back / Home / Recents.
            if (chromeVisible) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Chip(text = "VLC", filled = false)
                    Spacer(modifier = Modifier.weight(1f))
                    CircleControl(
                        onClick = {
                            noteChromeInteraction()
                            onPopOut()
                        },
                        contentDescription = "Pop out mini player",
                    ) {
                        Icon(
                            imageVector = Icons.Default.OpenInFull,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                    CircleControl(
                        onClick = {
                            noteChromeInteraction()
                            onToggleScoresTicker()
                        },
                        contentDescription = if (showScoresTicker) {
                            "Hide scores ticker"
                        } else {
                            "Show scores ticker"
                        },
                        background = if (showScoresTicker) {
                            Gold.copy(alpha = 0.9f)
                        } else {
                            Color.Black.copy(alpha = 0.55f)
                        },
                    ) {
                        Icon(
                            imageVector = Icons.Default.Sports,
                            contentDescription = null,
                            tint = if (showScoresTicker) VoidBlack else Color.White,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                    CircleControl(
                        onClick = {
                            noteChromeInteraction()
                            controller.toggleMute()
                            isMuted = controller.isMuted
                        },
                        contentDescription = if (isMuted) "Unmute" else "Mute",
                    ) {
                        Icon(
                            imageVector = if (isMuted) Icons.Default.VolumeOff else Icons.Default.VolumeUp,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            if (chromeVisible && !landscape) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = channel.group?.uppercase() ?: "LIVE TV",
                    color = Gold,
                    fontWeight = FontWeight.Bold,
                    fontSize = 11.sp,
                    maxLines = 1,
                )
                Text(
                    text = displayName,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (!nowTitle.isNullOrBlank()) {
                    Text(
                        text = "Now · $nowTitle",
                        color = Color.White.copy(alpha = 0.9f),
                        fontSize = 13.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (!nextTitle.isNullOrBlank()) {
                    Text(
                        text = "Next · $nextTitle",
                        color = Muted,
                        fontSize = 12.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Chip(text = engineLabel.substringBefore(" ·").ifBlank { "VLC" }, filled = false)
                    Chip(text = "LIVE", filled = true, fillColor = LiveMint)
                }
                Spacer(modifier = Modifier.height(8.dp))
            } else if (chromeVisible) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = displayName,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        if (chromeVisible) {
            Row(
                modifier = Modifier
                    .align(Alignment.Center)
                    .zIndex(10f),
                horizontalArrangement = Arrangement.spacedBy(28.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircleControl(
                    onClick = {
                        noteChromeInteraction()
                        onReplay()
                        controller.play(url)
                        isPlaying = true
                    },
                    contentDescription = "Rejoin live",
                    size = 52.dp,
                ) {
                    Icon(
                        imageVector = Icons.Default.Refresh,
                        contentDescription = null,
                        tint = Color.White,
                    )
                }
                CircleControl(
                    onClick = {
                        noteChromeInteraction()
                        controller.togglePlayPause()
                        isPlaying = controller.isPlaying
                    },
                    contentDescription = if (isPlaying) "Pause" else "Play",
                    size = 72.dp,
                    background = Gold,
                ) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = null,
                        tint = VoidBlack,
                        modifier = Modifier.size(40.dp),
                    )
                }
            }
        }

        // Variant D: sticky multi-game ticker at TOP (NFL-style). Always on when pref
        // is true — chrome auto-hide must not clear it (S-AND.FB.11).
        if (showScoresTicker) {
            LiveScoresTicker(
                games = liveGames,
                currentGameId = currentGameId,
                compact = landscape,
                onGameTap = { game ->
                    noteChromeInteraction()
                    onTickerGame(game)
                },
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .zIndex(20f)
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .systemGestureExclusion(),
            )
        }
    }
}

/** Idle before hiding title/controls/ticker; tap video restores (task ~3–5s). */
private const val CHROME_IDLE_HIDE_MS = 4_000L

@Composable
private fun CircleControl(
    onClick: () -> Unit,
    contentDescription: String,
    modifier: Modifier = Modifier,
    size: androidx.compose.ui.unit.Dp = 44.dp,
    background: Color = Color.Black.copy(alpha = 0.55f),
    content: @Composable () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = modifier.size(size),
        shape = CircleShape,
        color = background,
        contentColor = Color.White,
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
            content()
        }
    }
}

@Composable
private fun Chip(
    text: String,
    filled: Boolean,
    fillColor: Color = Gold,
) {
    Text(
        text = text,
        color = if (filled) VoidBlack else Color.White,
        fontWeight = FontWeight.Bold,
        fontSize = 11.sp,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(if (filled) fillColor else Color.White.copy(alpha = 0.15f))
            .padding(horizontal = 10.dp, vertical = 5.dp),
    )
}

@Composable
private fun LiveScoresTicker(
    games: List<Game>,
    currentGameId: String?,
    compact: Boolean,
    onGameTap: (Game) -> Unit,
    modifier: Modifier = Modifier,
) {
    val live = remember(games, currentGameId) {
        games
            .filter { it.isLive }
            .sortedWith(
                compareBy<Game> { if (it.id == currentGameId) 0 else 1 }
                    .thenBy { it.startTimeMs },
            )
            .take(24)
    }

    val listState = rememberLazyListState()
    val pillH = if (compact) 44.dp else 48.dp

    Column(
        modifier = modifier
            .fillMaxWidth()
            .systemGestureExclusion()
            .background(
                Brush.verticalGradient(
                    listOf(
                        Color.Black.copy(alpha = 0.82f),
                        Color.Black.copy(alpha = 0.45f),
                        Color.Transparent,
                    ),
                ),
            )
            .padding(top = 4.dp, bottom = 10.dp),
    ) {
        LazyRow(
            state = listState,
            modifier = Modifier
                .fillMaxWidth()
                .systemGestureExclusion(),
            contentPadding = PaddingValues(horizontal = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            userScrollEnabled = true,
        ) {
            if (live.isEmpty()) {
                item {
                    Text(
                        text = "No other live games",
                        color = Muted,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 12.dp),
                    )
                }
            }
            items(items = live, key = { it.id }) { game ->
                val current = game.id == currentGameId
                Row(
                    modifier = Modifier
                        .height(pillH)
                        .clip(RoundedCornerShape(12.dp))
                        .background(
                            if (current) Gold else Panel.copy(alpha = 0.94f),
                        )
                        .clickable { onGameTap(game) }
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    TickerTeamLogo(url = game.away.logoUrl, abbrev = game.away.abbreviation)
                    Text(
                        text = buildString {
                            append(game.away.abbreviation.ifBlank { game.away.rowLabel }.take(4))
                            append(' ')
                            append(game.away.displayScore)
                            append('–')
                            append(game.home.displayScore)
                            append(' ')
                            append(game.home.abbreviation.ifBlank { game.home.rowLabel }.take(4))
                        },
                        color = if (current) VoidBlack else TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = if (compact) 12.sp else 13.sp,
                        maxLines = 1,
                    )
                    TickerTeamLogo(url = game.home.logoUrl, abbrev = game.home.abbreviation)
                }
            }
        }
    }
}

@Composable
private fun TickerTeamLogo(url: String?, abbrev: String) {
    if (!url.isNullOrBlank()) {
        AsyncImage(
            model = url,
            contentDescription = abbrev,
            modifier = Modifier
                .size(22.dp)
                .clip(CircleShape),
            contentScale = ContentScale.Fit,
        )
    } else {
        Box(
            modifier = Modifier
                .size(22.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.35f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = abbrev.take(2).ifBlank { "·" },
                color = Gold,
                fontSize = 8.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
