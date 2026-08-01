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
            state.playlist == null -> {
                EmptyGuideHint()
            }

            state.isLoadingChannels && state.channels.isEmpty() -> {
                val status = state.channelStatus
                if (status != null) {
                    Text(
                        text = status,
                        color = Muted,
                        modifier = Modifier.padding(16.dp),
                    )
                }
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = Gold)
                }
            }

            else -> {
                GuideBrowseBody(vm = vm, state = state)
            }
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
                    Icon(
                        imageVector = Icons.Default.Search,
                        contentDescription = null,
                        tint = Muted,
                    )
                },
                singleLine = true,
                colors = guideFieldColors(),
            )
            FilterChip(
                selected = state.guideLayout == GuideLayout.LIST,
                onClick = { vm.setGuideLayout(GuideLayout.LIST) },
                label = { Text("List") },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = Gold,
                    selectedLabelColor = VoidBlack,
                    containerColor = Panel,
                    labelColor = TextPrimary,
                ),
            )
            FilterChip(
                selected = state.guideLayout == GuideLayout.GRID,
                onClick = { vm.setGuideLayout(GuideLayout.GRID) },
                label = { Text("Grid") },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = Gold,
                    selectedLabelColor = VoidBlack,
                    containerColor = Panel,
                    labelColor = TextPrimary,
                ),
            )
        }

        if (state.groups.size > 1) {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                listItems(items = state.groups) { group ->
                    FilterChip(
                        selected = state.selectedGroup == group,
                        onClick = { vm.selectGroup(group) },
                        label = {
                            Text(
                                text = group,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = Gold,
                            selectedLabelColor = VoidBlack,
                            containerColor = Panel,
                            labelColor = TextPrimary,
                        ),
                    )
                }
            }
        }

        val status = state.channelStatus
        if (status != null) {
            val layoutLabel = if (state.guideLayout == GuideLayout.LIST) "List" else "Grid"
            Text(
                text = "$status · $layoutLabel",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
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

        val channels = vm.filteredChannels()
        when (state.guideLayout) {
            GuideLayout.LIST -> {
                LazyColumn(
                    contentPadding = PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    listItems(
                        items = channels,
                        key = { ch -> ch.id },
                    ) { ch ->
                        ChannelListRow(channel = ch, onPlay = { vm.play(ch) })
                    }
                }
            }

            GuideLayout.GRID -> {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 140.dp),
                    contentPadding = PaddingValues(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    gridItems(
                        items = channels,
                        key = { ch -> ch.id },
                    ) { ch ->
                        ChannelGridCard(channel = ch, onPlay = { vm.play(ch) })
                    }
                }
            }
        }
    }
}

@Composable
private fun ChannelListRow(channel: IptvChannel, onPlay: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Panel)
            .clickable(onClick = onPlay)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ChannelLogo(channel = channel)
        Spacer(modifier = Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = channel.name,
                color = TextPrimary,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
            )
            val group = channel.group
            if (group != null) {
                Text(
                    text = group,
                    color = Muted,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                )
            }
        }
        Icon(
            imageVector = Icons.Default.PlayArrow,
            contentDescription = null,
            tint = Gold,
        )
    }
}

@Composable
private fun ChannelGridCard(channel: IptvChannel, onPlay: () -> Unit) {
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
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(12.dp),
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
        val group = channel.group
        if (group != null) {
            Text(
                text = group,
                color = Muted,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun ChannelLogo(channel: IptvChannel) {
    val logo = channel.logo
    if (!logo.isNullOrBlank()) {
        AsyncImage(
            model = logo,
            contentDescription = null,
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(8.dp)),
            contentScale = ContentScale.Fit,
        )
    } else {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(VoidBlack),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Default.PlayArrow,
                contentDescription = null,
                tint = Gold,
                modifier = Modifier.size(22.dp),
            )
        }
    }
}

@Composable
private fun EmptyGuideHint() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
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
        Text(
            text = "Guide",
            color = TextPrimary,
            style = MaterialTheme.typography.titleLarge,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Add an Xtream server URL + credentials (or M3U URL) in Settings. " +
                "Use List or Grid layout. Full EPG timeline is next.",
            color = Muted,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "→ Settings tab",
            color = Gold,
            fontWeight = FontWeight.Bold,
        )
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
