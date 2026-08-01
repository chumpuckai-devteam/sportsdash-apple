package com.samirpatel.sportsdash.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.lazy.items as listItems
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.samirpatel.sportsdash.AppUiState
import com.samirpatel.sportsdash.AppViewModel
import com.samirpatel.sportsdash.GuideLayout
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack

@Composable
fun GuideScreen(vm: AppViewModel, state: AppUiState) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(VoidBlack),
    ) {
        when {
            state.playlist == null -> EmptyGuideHint()
            state.isLoadingChannels && state.channels.isEmpty() -> {
                val status = state.channelStatus
                if (status != null) {
                    Text(text = status, color = Muted, modifier = Modifier.padding(16.dp))
                }
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Gold)
                }
            }
            else -> GuideBrowseBody(vm = vm, state = state)
        }
    }
}

@Composable
private fun GuideBrowseBody(vm: AppViewModel, state: AppUiState) {
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { vm.setSearchQuery(it) },
                modifier = Modifier.weight(1f),
                placeholder = { Text(text = "Search channels", color = Muted) },
                leadingIcon = {
                    Icon(imageVector = Icons.Default.Search, contentDescription = null, tint = Muted)
                },
                singleLine = true,
                colors = guideFieldColors(),
            )
            // LIST = hour timeline (iOS Guide); GRID = cards
            FilterChip(
                selected = state.guideLayout == GuideLayout.LIST,
                onClick = { vm.setGuideLayout(GuideLayout.LIST) },
                label = { Text("Guide") },
                colors = chipColors(),
            )
            FilterChip(
                selected = state.guideLayout == GuideLayout.GRID,
                onClick = { vm.setGuideLayout(GuideLayout.GRID) },
                label = { Text("Grid") },
                colors = chipColors(),
            )
        }

        // Provider order — no alphabetical re-sort
        if (state.groups.isNotEmpty()) {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                listItems(items = state.groups) { group ->
                    FilterChip(
                        selected = state.selectedGroup == group,
                        onClick = { vm.selectGroup(group) },
                        label = {
                            Text(text = group, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        },
                        colors = chipColors(),
                    )
                }
            }
        }

        val status = state.channelStatus
        if (status != null) {
            val layoutLabel = if (state.guideLayout == GuideLayout.LIST) "Hour guide" else "Grid"
            val cat = state.selectedGroup.ifBlank { "—" }
            Text(
                text = "$status · $layoutLabel · $cat",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }
        val epgStatus = state.epgStatus
        if (epgStatus != null) {
            Text(
                text = epgStatus + if (state.isAutoFillingEpg) " …" else "",
                color = if (state.isAutoFillingEpg) Gold else Muted,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
            )
        }
        val bulkStatus = state.bulkEpgStatus
        if (bulkStatus != null) {
            Text(
                text = bulkStatus + if (state.isLoadingEpg) " …" else "",
                color = if (state.isLoadingEpg) Gold else Muted,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
            )
        }
        val err = state.channelError
        if (err != null) {
            Text(
                text = err,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(16.dp),
            )
        }

        when (state.guideLayout) {
            GuideLayout.LIST -> {
                Box(modifier = Modifier.fillMaxSize()) {
                    GuideTimeline(
                        channels = vm.guideChannels(),
                        programsFor = { id -> vm.programsFor(id) },
                        windowStartMs = state.guideWindowStartMs,
                        onPlay = { ch -> vm.play(ch) },
                        onShiftHours = { d -> vm.shiftGuideWindowHours(d) },
                        onResetToNow = { vm.resetGuideWindowToNow() },
                        modifier = Modifier.fillMaxSize(),
                    )
                    val catCovered = vm.guideChannels().count { ch ->
                        !state.epgByChannelId[ch.id].isNullOrEmpty()
                    }
                    if (state.isLoadingEpg && catCovered == 0) {
                        EpgLoadingCard(
                            title = "Loading full TV guide",
                            status = state.bulkEpgStatus ?: state.epgStatus,
                        )
                    }
                }
            }
            GuideLayout.GRID -> {
                Box(modifier = Modifier.fillMaxSize()) {
                    val channels = vm.guideChannels()
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = 140.dp),
                        contentPadding = PaddingValues(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        gridItems(items = channels, key = { it.id }) { ch ->
                            ChannelGridCard(
                                channel = ch,
                                nowTitle = vm.nowTitle(ch.id),
                                onPlay = { vm.play(ch) },
                            )
                        }
                    }
                    val catCovered = channels.count { ch ->
                        !state.epgByChannelId[ch.id].isNullOrEmpty()
                    }
                    if (state.isLoadingEpg && catCovered == 0) {
                        EpgLoadingCard(
                            title = "Loading full TV guide",
                            status = state.bulkEpgStatus ?: state.epgStatus,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun chipColors() = FilterChipDefaults.filterChipColors(
    selectedContainerColor = Gold,
    selectedLabelColor = VoidBlack,
    containerColor = Panel,
    labelColor = TextPrimary,
)

@Composable
private fun ChannelGridCard(
    channel: IptvChannel,
    nowTitle: String?,
    onPlay: () -> Unit,
) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(14.dp))
            .background(Panel)
            .clickable(onClick = onPlay)
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1.2f)
                .clip(RoundedCornerShape(10.dp))
                .background(VoidBlack),
            contentAlignment = Alignment.Center,
        ) {
            val logo = channel.logo
            if (!logo.isNullOrBlank()) {
                AsyncImage(
                    model = logo,
                    contentDescription = channel.name,
                    modifier = Modifier.fillMaxSize().padding(12.dp),
                    contentScale = ContentScale.Fit,
                )
            } else {
                Icon(
                    imageVector = Icons.Default.LiveTv,
                    contentDescription = null,
                    tint = Gold,
                    modifier = Modifier.size(36.dp),
                )
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = channel.name,
            color = TextPrimary,
            fontWeight = FontWeight.SemiBold,
            fontSize = 13.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        Text(
            text = when {
                !nowTitle.isNullOrBlank() -> nowTitle
                else -> channel.group ?: "No guide"
            },
            color = if (!nowTitle.isNullOrBlank()) Gold else Muted,
            fontSize = 11.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun EmptyGuideHint() {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Default.LiveTv,
            contentDescription = null,
            tint = Gold,
            modifier = Modifier.size(48.dp),
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(text = "Guide", color = TextPrimary, style = MaterialTheme.typography.titleLarge)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Add Xtream credentials in Settings. Categories keep provider order. " +
                "Default layout is the hour-by-hour guide (like iOS).",
            color = Muted,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(text = "→ Settings tab", color = Gold, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun guideFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = Gold,
    unfocusedBorderColor = Muted,
    focusedLabelColor = Gold,
    unfocusedLabelColor = Muted,
    cursorColor = Gold,
    focusedTextColor = TextPrimary,
    unfocusedTextColor = TextPrimary,
    focusedPlaceholderColor = Muted,
    unfocusedPlaceholderColor = Muted,
)
