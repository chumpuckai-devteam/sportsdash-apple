package com.samirpatel.sportsdash.ui

import android.app.Activity
import android.content.res.Configuration
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.material.icons.filled.ArrowBack
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
import androidx.core.view.WindowInsetsControllerCompat
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.player.VlcPlayerController
import com.samirpatel.sportsdash.core.player.createVlcVideoLayout
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack

/**
 * Fullscreen player closer to iOS:
 * - Always-reachable Back (system back + top-left)
 * - Play / pause, mute, rejoin live
 * - Channel title + engine / LIVE chips
 * - Bottom live scores ticker (compact, scores never clip)
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
) {
    val context = LocalContext.current
    val view = LocalView.current
    val controller = remember { VlcPlayerController(context) }
    var chromeVisible by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(false) }
    val landscape =
        LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE

    // Immersive fullscreen — kills the thin status-bar hairline in landscape video.
    DisposableEffect(Unit) {
        val activity = context as? Activity
        val window = activity?.window
        val insetsController = window?.let { WindowCompat.getInsetsController(it, view) }
        insetsController?.let {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            it.hide(WindowInsetsCompat.Type.systemBars())
            it.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        onDispose {
            insetsController?.show(WindowInsetsCompat.Type.systemBars())
        }
    }

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

        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(
                    top = if (landscape) 72.dp else 96.dp,
                    bottom = if (landscape) 96.dp else 148.dp,
                )
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) {
                    chromeVisible = !chromeVisible
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
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CircleControl(
                    onClick = onClose,
                    contentDescription = "Back",
                ) {
                    Icon(
                        imageVector = Icons.Default.ArrowBack,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(22.dp),
                    )
                }

                if (chromeVisible) {
                    Chip(text = "VLC", filled = false)
                    Spacer(modifier = Modifier.weight(1f))
                    CircleControl(
                        onClick = onPopOut,
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
                        onClick = onToggleScoresTicker,
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
                } else {
                    Spacer(modifier = Modifier.weight(1f))
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

        if (chromeVisible && showScoresTicker) {
            LiveScoresTicker(
                games = liveGames,
                currentGameId = currentGameId,
                compact = landscape,
                onGameTap = onTickerGame,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .zIndex(10f)
                    .navigationBarsPadding(),
            )
        }
    }
}

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

    val cardHeight = if (compact) 64.dp else 76.dp
    val cardWidth = if (compact) 148.dp else 168.dp
    val scoreSize = if (compact) 15.sp else 17.sp
    val abbrSize = if (compact) 11.sp else 12.sp

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    listOf(
                        Color.Transparent,
                        Color.Black.copy(alpha = 0.55f),
                        Color.Black.copy(alpha = 0.94f),
                    ),
                ),
            )
            .padding(bottom = 8.dp, top = 12.dp),
    ) {
        Text(
            text = if (live.isEmpty()) "No other live games" else "LIVE SCORES · tap to switch",
            color = LiveMint,
            fontWeight = FontWeight.Bold,
            fontSize = 10.sp,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 2.dp),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (live.isNotEmpty()) {
                item {
                    Column(
                        modifier = Modifier
                            .width(72.dp)
                            .height(cardHeight)
                            .clip(RoundedCornerShape(12.dp))
                            .background(Panel.copy(alpha = 0.95f))
                            .padding(horizontal = 8.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text("LIVE", color = LiveMint, fontWeight = FontWeight.Bold, fontSize = 10.sp)
                        Text(
                            "${live.size}",
                            color = TextPrimary,
                            fontWeight = FontWeight.Bold,
                            fontSize = 20.sp,
                        )
                        Text("games", color = Muted, fontSize = 10.sp)
                    }
                }
            }
            items(items = live, key = { it.id }) { game ->
                val current = game.id == currentGameId
                Column(
                    modifier = Modifier
                        .width(cardWidth)
                        .height(cardHeight)
                        .clip(RoundedCornerShape(12.dp))
                        .background(
                            if (current) Gold.copy(alpha = 0.22f) else Panel.copy(alpha = 0.95f),
                        )
                        .clickable { onGameTap(game) }
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            game.league.label,
                            color = Gold,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            "LIVE",
                            color = LiveMint,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                    Text(
                        text = game.matchupLabel,
                        color = TextPrimary,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = abbrSize,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = "${game.away.displayScore}  –  ${game.home.displayScore}",
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = scoreSize,
                        maxLines = 1,
                        textAlign = TextAlign.Start,
                        modifier = Modifier
                            .fillMaxWidth()
                            .widthIn(min = 48.dp),
                    )
                }
            }
        }
    }
}
