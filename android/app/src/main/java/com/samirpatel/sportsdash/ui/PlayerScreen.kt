package com.samirpatel.sportsdash.ui

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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.zIndex
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
 * - Always-reachable **Back** (system back + top-left)
 * - Play / pause, mute, rejoin live
 * - Channel title + engine / LIVE chips
 * - Bottom live scores ticker
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
    onClose: () -> Unit,
    onTickerGame: (Game) -> Unit,
    onReplay: () -> Unit,
) {
    val context = LocalContext.current
    val controller = remember { VlcPlayerController(context) }
    var chromeVisible by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(false) }

    // System back must leave the player
    BackHandler(onBack = onClose)

    DisposableEffect(url) {
        controller.play(url)
        isPlaying = true
        onDispose {
            controller.stop()
            controller.detach()
        }
    }
    DisposableEffect(Unit) {
        onDispose { controller.release() }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        // Video layer
        AndroidView(
            factory = { ctx ->
                createVlcVideoLayout(ctx).also { layout ->
                    controller.attach(layout)
                }
            },
            modifier = Modifier.fillMaxSize(),
            update = { layout ->
                if (!controller.isPlaying && url.isNotBlank()) {
                    // keep attached
                }
                controller.attach(layout)
            },
        )

        // Tap middle of video to toggle chrome (does NOT cover top/bottom control bands)
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 96.dp, bottom = 168.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) {
                    chromeVisible = !chromeVisible
                },
        )

        // ===== TOP CHROME (always on top of TextureView) =====
        // Keep Back ALWAYS visible so exit never depends on chrome toggle.
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .zIndex(10f)
                .statusBarsPadding()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Black.copy(alpha = 0.85f), Color.Transparent),
                    ),
                )
                .padding(horizontal = 8.dp, vertical = 6.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // Large hit target — primary exit
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

            if (chromeVisible) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = channel.group?.uppercase() ?: "LIVE TV",
                    color = Gold,
                    fontWeight = FontWeight.Bold,
                    fontSize = 11.sp,
                    maxLines = 1,
                )
                Text(
                    text = channel.name,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(modifier = Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Chip(text = engineLabel.substringBefore(" ·").ifBlank { "VLC" }, filled = false)
                    Chip(text = "LIVE", filled = true, fillColor = LiveMint)
                }
                Spacer(modifier = Modifier.height(8.dp))
            }
        }

        // ===== CENTER TRANSPORT =====
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

        // ===== BOTTOM TICKER (always when chrome visible; matches iOS strip) =====
        if (chromeVisible) {
            LiveScoresTicker(
                games = liveGames,
                currentGameId = currentGameId,
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
            .padding(bottom = 10.dp, top = 20.dp),
    ) {
        // Optional hero line for current game context
        Text(
            text = if (live.isEmpty()) "No other live games" else "LIVE SCORES · tap to switch",
            color = LiveMint,
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 4.dp),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Sport summary chip
            if (live.isNotEmpty()) {
                item {
                    Column(
                        modifier = Modifier
                            .width(96.dp)
                            .height(88.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(Panel.copy(alpha = 0.95f))
                            .padding(10.dp),
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text("LIVE", color = LiveMint, fontWeight = FontWeight.Bold, fontSize = 11.sp)
                        Text(
                            "${live.size} games",
                            color = TextPrimary,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 13.sp,
                        )
                    }
                }
            }
            items(items = live, key = { it.id }) { game ->
                val current = game.id == currentGameId
                Column(
                    modifier = Modifier
                        .width(156.dp)
                        .height(88.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(
                            if (current) Gold.copy(alpha = 0.22f) else Panel.copy(alpha = 0.95f),
                        )
                        .clickable { onGameTap(game) }
                        .padding(10.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            game.league.label,
                            color = Gold,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                        )
                        Text(
                            "LIVE",
                            color = LiveMint,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                    Text(
                        game.matchupLabel,
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        "${game.away.displayScore} – ${game.home.displayScore}",
                        color = TextPrimary,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        game.statusLine,
                        color = Muted,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}
