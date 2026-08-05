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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.systemGestureExclusion
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Sports
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.zIndex
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import coil.compose.AsyncImage
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.player.ScoresTickerMode
import com.samirpatel.sportsdash.core.player.VlcPlayerController
import com.samirpatel.sportsdash.core.player.createVlcVideoLayout
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack
import kotlinx.coroutines.delay

/**
 * Full-bleed video always (fit screen). Chrome + scores ticker are transparent
 * overlay layers on top of video — never reserve a black band that shrinks video.
 *
 * Top row: ← Back | ticker pills… | VLC ✕  (ticker aligned with back)
 */
@Composable
fun PlayerScreen(
    channel: IptvChannel,
    url: String,
    engineLabel: String,
    liveGames: List<Game>,
    currentGameId: String?,
    tickerMode: ScoresTickerMode = ScoresTickerMode.FADE,
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
    var chromeIdleEpoch by remember { mutableIntStateOf(0) }
    var isPlaying by remember { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(false) }
    val landscape =
        LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val tapInteraction = remember { MutableInteractionSource() }

    fun noteChromeInteraction() {
        chromeVisible = true
        chromeIdleEpoch++
    }

    fun toggleChrome() {
        if (chromeVisible) {
            chromeVisible = false
        } else {
            chromeVisible = true
            chromeIdleEpoch++
        }
    }

    LaunchedEffect(chromeVisible, chromeIdleEpoch) {
        if (!chromeVisible) return@LaunchedEffect
        delay(CHROME_IDLE_HIDE_MS)
        chromeVisible = false
    }

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
        // 1) Full-window video — always max size
        AndroidView(
            factory = { ctx ->
                createVlcVideoLayout(ctx).also { layout ->
                    layout.isClickable = false
                    layout.isFocusable = false
                    layout.isFocusableInTouchMode = false
                    controller.attach(layout)
                    if (url.isNotBlank()) controller.play(url)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .zIndex(0f),
            update = { layout ->
                layout.isClickable = false
                layout.isFocusable = false
                controller.attach(layout)
            },
        )

        // 2) Tap catcher under chrome
        Box(
            modifier = Modifier
                .fillMaxSize()
                .zIndex(1f)
                .clickable(
                    interactionSource = tapInteraction,
                    indication = null,
                    onClick = { toggleChrome() },
                )
                .semantics { contentDescription = "Toggle player controls" },
        )

        // 3) Transparent overlay chrome
        Column(
            modifier = Modifier
                .fillMaxSize()
                .zIndex(20f)
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            // Top row: Back + ticker (same row, left-aligned) + optional close
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CircleControl(
                    onClick = onClose,
                    contentDescription = "Exit player",
                    size = 44.dp,
                    background = Color.Transparent,
                ) {
                    Icon(
                        imageVector = Icons.Default.ArrowBack,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(22.dp),
                    )
                }

                // Off | Fade-with-chrome | Persistent
                val showTicker = when (tickerMode) {
                    ScoresTickerMode.OFF -> false
                    ScoresTickerMode.FADE -> chromeVisible
                    ScoresTickerMode.PERSISTENT -> true
                }
                if (showTicker) {
                    LiveScoresTicker(
                        games = liveGames,
                        currentGameId = currentGameId,
                        favoriteTeamIds = favoriteTeamIds,
                        compact = true,
                        onGameTap = { game ->
                            noteChromeInteraction()
                            onTickerGame(game)
                        },
                        modifier = Modifier
                            .weight(1f)
                            .systemGestureExclusion(),
                    )
                } else {
                    Spacer(modifier = Modifier.weight(1f))
                }

                if (chromeVisible) {
                    Chip(text = engineLabel.substringBefore(" ·").ifBlank { "VLC" }, filled = false)
                    CircleControl(
                        onClick = onClose,
                        contentDescription = "Close player",
                        size = 40.dp,
                        background = Color.Transparent,
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            if (chromeVisible) {
                // Bottom: multi-line info + right utilities row
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    ChannelProgramChrome(
                        channel = channel,
                        displayName = displayName,
                        nowTitle = nowTitle,
                        nextTitle = nextTitle,
                        engineLabel = engineLabel,
                        landscape = landscape,
                        modifier = Modifier.weight(1f),
                    )
                    Column(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        CircleControl(
                            onClick = {
                                noteChromeInteraction()
                                onPopOut()
                            },
                            contentDescription = "Pop out mini player",
                            background = Color.Transparent,
                        ) {
                            Icon(
                                imageVector = Icons.Default.OpenInFull,
                                contentDescription = null,
                                tint = Color.White,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        // Same sports control — cycles Off → Fade → Pin; label shows mode
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircleControl(
                                onClick = {
                                    noteChromeInteraction()
                                    onToggleScoresTicker()
                                },
                                contentDescription = tickerMode.contentDescription + ". Tap to change.",
                                background = when (tickerMode) {
                                    ScoresTickerMode.OFF -> Color.Transparent
                                    ScoresTickerMode.FADE -> Gold.copy(alpha = 0.55f)
                                    ScoresTickerMode.PERSISTENT -> Gold.copy(alpha = 0.92f)
                                },
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Sports,
                                    contentDescription = null,
                                    tint = when (tickerMode) {
                                        ScoresTickerMode.OFF -> Color.White
                                        else -> VoidBlack
                                    },
                                    modifier = Modifier.size(20.dp),
                                )
                            }
                            Text(
                                text = tickerMode.shortLabel,
                                color = when (tickerMode) {
                                    ScoresTickerMode.OFF -> Color.White.copy(alpha = 0.85f)
                                    else -> Gold
                                },
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                        CircleControl(
                            onClick = {
                                noteChromeInteraction()
                                controller.toggleMute()
                                isMuted = controller.isMuted
                            },
                            contentDescription = if (isMuted) "Unmute" else "Mute",
                            background = Color.Transparent,
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
            }
        }

        // 4) Center transport — transparent rings
        if (chromeVisible) {
            Row(
                modifier = Modifier
                    .align(Alignment.Center)
                    .zIndex(30f)
                    .padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(if (landscape) 36.dp else 28.dp),
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
                    size = if (landscape) 52.dp else 56.dp,
                    background = Color.Black.copy(alpha = 0.28f),
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
                    size = if (landscape) 72.dp else 76.dp,
                    background = Gold.copy(alpha = 0.92f),
                ) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = null,
                        tint = VoidBlack,
                        modifier = Modifier.size(if (landscape) 36.dp else 40.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun ChannelProgramChrome(
    channel: IptvChannel,
    displayName: String,
    nowTitle: String?,
    nextTitle: String?,
    engineLabel: String,
    landscape: Boolean,
    modifier: Modifier = Modifier,
) {
    // No solid panel — text only over video (shadow via dark text outline not needed;
    // slight soft black shadow via translucent text backdrop is avoided per Samir).
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(if (landscape) 2.dp else 3.dp),
    ) {
        Text(
            text = channel.group?.uppercase()?.takeIf { it.isNotBlank() } ?: "LIVE TV",
            color = Gold,
            fontWeight = FontWeight.Bold,
            fontSize = if (landscape) 10.sp else 11.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = displayName,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = if (landscape) 14.sp else 17.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            lineHeight = if (landscape) 17.sp else 21.sp,
        )
        if (!nowTitle.isNullOrBlank()) {
            Text(
                text = "Now",
                color = LiveMint,
                fontWeight = FontWeight.SemiBold,
                fontSize = if (landscape) 10.sp else 11.sp,
                maxLines = 1,
            )
            Text(
                text = nowTitle,
                color = Color.White.copy(alpha = 0.95f),
                fontWeight = FontWeight.Medium,
                fontSize = if (landscape) 12.sp else 13.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (!nextTitle.isNullOrBlank()) {
            Text(
                text = "Next · $nextTitle",
                color = Muted,
                fontSize = if (landscape) 11.sp else 12.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

private const val CHROME_IDLE_HIDE_MS = 4_500L

@Composable
private fun CircleControl(
    onClick: () -> Unit,
    contentDescription: String,
    modifier: Modifier = Modifier,
    size: androidx.compose.ui.unit.Dp = 48.dp,
    background: Color = Color.Transparent,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(background)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            )
            .semantics { this.contentDescription = contentDescription },
        contentAlignment = Alignment.Center,
    ) {
        content()
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
            .background(
                if (filled) fillColor.copy(alpha = 0.9f)
                else Color.White.copy(alpha = 0.12f),
            )
            .padding(horizontal = 10.dp, vertical = 5.dp),
    )
}

@Composable
private fun LiveScoresTicker(
    games: List<Game>,
    currentGameId: String?,
    favoriteTeamIds: Set<String> = emptySet(),
    compact: Boolean,
    onGameTap: (Game) -> Unit,
    modifier: Modifier = Modifier,
) {
    val live = remember(games, currentGameId, favoriteTeamIds) {
        fun isFav(g: Game): Boolean =
            favoriteTeamIds.isNotEmpty() &&
                (g.home.id in favoriteTeamIds || g.away.id in favoriteTeamIds)
        // Favorites lead the strip (cycle faves). Current game first only if also a fav;
        // otherwise current sits after the fav block so starred teams stay up front.
        games
            .filter { it.isLive }
            .sortedWith(
                compareBy<Game> { g ->
                    when {
                        isFav(g) && g.id == currentGameId -> 0
                        isFav(g) -> 1
                        g.id == currentGameId -> 2
                        else -> 3
                    }
                }.thenBy { it.startTimeMs },
            )
            .take(24)
    }

    val listState = rememberLazyListState()
    // After channel/game switch, snap strip to the front (fav block)
    LaunchedEffect(live.map { it.id }, currentGameId, favoriteTeamIds) {
        if (live.isNotEmpty()) {
            listState.scrollToItem(0)
        }
    }
    val pillH = if (compact) 36.dp else 42.dp

    // Fully transparent row — only pills float over video
    LazyRow(
        state = listState,
        modifier = modifier
            .fillMaxWidth()
            .systemGestureExclusion(),
        contentPadding = PaddingValues(end = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        userScrollEnabled = true,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (live.isEmpty()) {
            item {
                Text(
                    text = "No other live games",
                    color = Muted,
                    fontSize = 11.sp,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
            }
        }
        items(items = live, key = { it.id }) { game ->
            val current = game.id == currentGameId
            Row(
                modifier = Modifier
                    .height(pillH)
                    .clip(RoundedCornerShape(10.dp))
                    .background(
                        // Opaque pill only — row itself stays transparent
                        if (current) Gold
                        else Panel,
                    )
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onGameTap(game) }
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
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
                    fontSize = 12.sp,
                    maxLines = 1,
                )
                TickerTeamLogo(url = game.home.logoUrl, abbrev = game.home.abbreviation)
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
                .size(18.dp)
                .clip(CircleShape),
            contentScale = ContentScale.Fit,
        )
    } else {
        Box(
            modifier = Modifier
                .size(18.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.25f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = abbrev.take(2).ifBlank { "·" },
                color = Gold,
                fontSize = 7.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
