package com.samirpatel.sportsdash.ui

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.player.VlcPlayerController
import com.samirpatel.sportsdash.core.player.createVlcVideoLayout
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary

/**
 * Fullscreen VLC player with:
 * - Play / pause / jump-to-live / close controls
 * - Live scores ticker (iOS LiveScoresStrip parity, simplified)
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
            .background(Color.Black)
            .clickable { chromeVisible = !chromeVisible },
    ) {
        AndroidView(
            factory = { ctx ->
                createVlcVideoLayout(ctx).also { layout ->
                    controller.attach(layout)
                }
            },
            modifier = Modifier.fillMaxSize(),
            update = { layout -> controller.attach(layout) },
        )

        if (chromeVisible) {
            // Top bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopCenter)
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Black.copy(alpha = 0.75f), Color.Transparent),
                        ),
                    )
                    .padding(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onClose) {
                    Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = channel.name,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = engineLabel,
                        color = Gold,
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }

            // Center transport
            Row(
                modifier = Modifier.align(Alignment.Center),
                horizontalArrangement = Arrangement.spacedBy(28.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    onClick = {
                        // Rejoin live
                        onReplay()
                        controller.play(url)
                        isPlaying = true
                    },
                    modifier = Modifier
                        .size(52.dp)
                        .clip(RoundedCornerShape(26.dp))
                        .background(Color.Black.copy(alpha = 0.45f)),
                ) {
                    Icon(Icons.Default.Refresh, contentDescription = "Live", tint = Color.White)
                }
                IconButton(
                    onClick = {
                        controller.togglePlayPause()
                        isPlaying = !isPlaying
                    },
                    modifier = Modifier
                        .size(72.dp)
                        .clip(RoundedCornerShape(36.dp))
                        .background(Gold.copy(alpha = 0.9f)),
                ) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = if (isPlaying) "Pause" else "Play",
                        tint = Color.Black,
                        modifier = Modifier.size(40.dp),
                    )
                }
            }

            // Bottom live scores ticker
            LiveScoresTicker(
                games = liveGames,
                currentGameId = currentGameId,
                onGameTap = onTickerGame,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
    }
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
                    listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f), Color.Black.copy(alpha = 0.92f)),
                ),
            )
            .padding(bottom = 10.dp, top = 24.dp),
    ) {
        Text(
            text = if (live.isEmpty()) "No other live games" else "LIVE · tap to switch",
            color = LiveMint,
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 4.dp),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(items = live, key = { it.id }) { game ->
                val current = game.id == currentGameId
                Column(
                    modifier = Modifier
                        .width(148.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (current) Gold.copy(alpha = 0.2f) else Panel.copy(alpha = 0.92f))
                        .clickable { onGameTap(game) }
                        .padding(10.dp),
                ) {
                    Text(
                        game.league.label,
                        color = Muted,
                        fontSize = 10.sp,
                        maxLines = 1,
                    )
                    Text(
                        game.matchupLabel,
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        "${game.away.displayScore} – ${game.home.displayScore}  ·  ${game.statusLine}",
                        color = if (current) Gold else LiveMint,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}
