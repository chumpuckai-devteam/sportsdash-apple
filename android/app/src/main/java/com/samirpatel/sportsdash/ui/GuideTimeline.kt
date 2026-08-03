package com.samirpatel.sportsdash.ui

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.samirpatel.sportsdash.AppViewModel
import com.samirpatel.sportsdash.core.epg.EpgProgram
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

private val ChannelColWidth = 148.dp
private val RowHeight = 78.dp
private val TimeHeaderHeight = 36.dp
private val PxPerHourDp = AppViewModel.PX_PER_HOUR.dp
private val GuideHours = AppViewModel.GUIDE_HOURS

/**
 * iOS-style traditional TV guide: channel column + hour timeline.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun GuideTimeline(
    channels: List<IptvChannel>,
    programsFor: (String) -> List<EpgProgram>,
    windowStartMs: Long,
    onPlay: (IptvChannel) -> Unit,
    onLongPressChannel: (IptvChannel) -> Unit = {},
    onShiftHours: (Int) -> Unit,
    onResetToNow: () -> Unit,
    favoriteIds: Set<String> = emptySet(),
    displayName: (IptvChannel) -> String = { it.name },
    ratingFor: (IptvChannel) -> com.samirpatel.sportsdash.core.ratings.MovieRating? = { null },
    ratingLoadingFor: (IptvChannel) -> Boolean = { false },
    onRequestRating: (IptvChannel) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val hScroll = rememberScrollState()
    val density = LocalDensity.current
    val pxPerHourPx = with(density) { PxPerHourDp.toPx() }
    val timelineWidthDp = PxPerHourDp * GuideHours
    val windowEndMs = windowStartMs + GuideHours * 3600_000L
    val nowMs = System.currentTimeMillis()
    val hourFmt = remember { SimpleDateFormat("h a", Locale.getDefault()) }

    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { onShiftHours(-3) }) {
                Icon(
                    imageVector = Icons.Default.KeyboardArrowLeft,
                    contentDescription = "Earlier",
                    tint = Gold,
                )
            }
            IconButton(onClick = onResetToNow) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = "Now",
                    tint = Gold,
                )
            }
            IconButton(onClick = { onShiftHours(3) }) {
                Icon(
                    imageVector = Icons.Default.KeyboardArrowRight,
                    contentDescription = "Later",
                    tint = Gold,
                )
            }
            Text(
                text = "Starts ${hourFmt.format(Date(windowStartMs))} · ${GuideHours}h",
                color = Muted,
                fontSize = 12.sp,
                modifier = Modifier.padding(start = 4.dp),
            )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(TimeHeaderHeight)
                .background(VoidBlack),
        ) {
            Box(
                modifier = Modifier
                    .width(ChannelColWidth)
                    .fillMaxHeight()
                    .background(Panel)
                    .padding(horizontal = 8.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                Text(
                    text = "Channel",
                    color = Muted,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Row(
                modifier = Modifier
                    .horizontalScroll(hScroll)
                    .height(TimeHeaderHeight),
            ) {
                repeat(GuideHours) { h ->
                    val t = windowStartMs + h * 3600_000L
                    Box(
                        modifier = Modifier
                            .width(PxPerHourDp)
                            .fillMaxHeight()
                            .background(if (h % 2 == 0) Panel.copy(alpha = 0.5f) else VoidBlack)
                            .padding(horizontal = 6.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        Text(
                            text = hourFmt.format(Date(t)),
                            color = Gold,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
            }
        }

        if (channels.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = "No channels in this category", color = Muted)
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(
                    items = channels,
                    key = { ch -> ch.id },
                ) { channel ->
                    TimelineRow(
                        channel = channel,
                        programs = programsFor(channel.id),
                        windowStartMs = windowStartMs,
                        windowEndMs = windowEndMs,
                        nowMs = nowMs,
                        pxPerHourPx = pxPerHourPx,
                        timelineWidthDp = timelineWidthDp,
                        hScroll = hScroll,
                        isFavorite = channel.id in favoriteIds,
                        label = displayName(channel),
                        rating = ratingFor(channel),
                        ratingLoading = ratingLoadingFor(channel),
                        onRequestRating = { onRequestRating(channel) },
                        onPlay = { onPlay(channel) },
                        onLongPress = { onLongPressChannel(channel) },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TimelineRow(
    channel: IptvChannel,
    programs: List<EpgProgram>,
    windowStartMs: Long,
    windowEndMs: Long,
    nowMs: Long,
    pxPerHourPx: Float,
    timelineWidthDp: Dp,
    hScroll: ScrollState,
    isFavorite: Boolean,
    label: String,
    rating: com.samirpatel.sportsdash.core.ratings.MovieRating?,
    ratingLoading: Boolean,
    onRequestRating: () -> Unit,
    onPlay: () -> Unit,
    onLongPress: () -> Unit,
) {
    val density = LocalDensity.current
    val minBlockPx = with(density) { 28.dp.toPx() }
    val layoutBlocks = remember(programs, windowStartMs, windowEndMs, pxPerHourPx, minBlockPx) {
        buildTimelineBlocks(programs, windowStartMs, windowEndMs).map { block ->
            val startX = ((block.startMs - windowStartMs) / 3_600_000f) * pxPerHourPx
            val widthPx = max(
                ((block.endMs - block.startMs) / 3_600_000f) * pxPerHourPx,
                minBlockPx,
            )
            LaidOutBlock(block = block, startX = startX, widthPx = widthPx)
        }
    }
    val nowX = if (nowMs in windowStartMs until windowEndMs) {
        ((nowMs - windowStartMs) / 3_600_000f) * pxPerHourPx
    } else {
        null
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(RowHeight)
            .background(VoidBlack),
    ) {
        Row(
            modifier = Modifier
                .width(ChannelColWidth)
                .fillMaxHeight()
                .background(Panel)
                .combinedClickable(onClick = onPlay, onLongClick = onLongPress)
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val logo = channel.logo
            if (!logo.isNullOrBlank()) {
                AsyncImage(
                    model = logo,
                    contentDescription = null,
                    modifier = Modifier
                        .size(32.dp)
                        .clip(RoundedCornerShape(6.dp)),
                    contentScale = ContentScale.Fit,
                )
                Spacer(modifier = Modifier.width(6.dp))
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (isFavorite) "★ $label" else label,
                    color = TextPrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                val nowTitle = programs.firstOrNull { it.contains(nowMs) }?.title
                    ?: programs.minByOrNull { kotlin.math.abs(it.startMs - nowMs) }?.title
                if (!nowTitle.isNullOrBlank()) {
                    MovieRatingRow(
                        title = nowTitle,
                        rating = rating,
                        loading = ratingLoading,
                        onRequest = onRequestRating,
                        compact = true,
                    )
                }
            }
        }

        Box(
            modifier = Modifier
                .horizontalScroll(hScroll)
                .width(timelineWidthDp)
                .fillMaxHeight()
                .background(VoidBlack)
                .combinedClickable(onClick = onPlay, onLongClick = onLongPress),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Panel.copy(alpha = 0.25f)),
            )

            layoutBlocks.forEach { laid ->
                ProgramBlock(
                    block = laid.block,
                    startX = laid.startX,
                    widthPx = laid.widthPx,
                    nowMs = nowMs,
                )
            }

            if (nowX != null) {
                Box(
                    modifier = Modifier
                        .offset { IntOffset(nowX.roundToInt(), 0) }
                        .width(2.dp)
                        .fillMaxHeight()
                        .background(LiveMint),
                )
            }
        }
    }
}

@Composable
private fun ProgramBlock(
    block: TimelineBlock,
    startX: Float,
    widthPx: Float,
    nowMs: Long,
) {
    val density = LocalDensity.current
    val widthDp = with(density) { widthPx.toDp() }
    val isNow = nowMs in block.startMs until block.endMs

    Box(
        modifier = Modifier
            .offset { IntOffset(startX.roundToInt(), 0) }
            .width(widthDp)
            .fillMaxHeight()
            .padding(vertical = 6.dp, horizontal = 2.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(
                when {
                    block.isGap -> Muted.copy(alpha = 0.12f)
                    isNow -> Gold.copy(alpha = 0.28f)
                    else -> Panel
                },
            )
            .padding(horizontal = 6.dp, vertical = 4.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (!block.isGap) {
            Column {
                Text(
                    text = block.title,
                    color = if (isNow) Gold else TextPrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (isNow) {
                    Text(
                        text = "LIVE",
                        color = LiveMint,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

private data class TimelineBlock(
    val startMs: Long,
    val endMs: Long,
    val title: String,
    val isGap: Boolean,
)

private data class LaidOutBlock(
    val block: TimelineBlock,
    val startX: Float,
    val widthPx: Float,
)

private fun buildTimelineBlocks(
    programs: List<EpgProgram>,
    windowStart: Long,
    windowEnd: Long,
): List<TimelineBlock> {
    val sorted = programs
        .filter { it.endMs > windowStart && it.startMs < windowEnd }
        .sortedBy { it.startMs }
    if (sorted.isEmpty()) {
        return listOf(
            TimelineBlock(
                startMs = windowStart,
                endMs = windowEnd,
                title = "",
                isGap = true,
            ),
        )
    }
    val out = ArrayList<TimelineBlock>()
    var cursor = windowStart
    for (p in sorted) {
        val s = max(p.startMs, windowStart)
        val e = minOf(p.endMs, windowEnd)
        if (s > cursor) {
            out.add(TimelineBlock(cursor, s, "", isGap = true))
        }
        if (e > s) {
            out.add(TimelineBlock(s, e, p.title, isGap = false))
            cursor = e
        }
    }
    if (cursor < windowEnd) {
        out.add(TimelineBlock(cursor, windowEnd, "", isGap = true))
    }
    return out
}
