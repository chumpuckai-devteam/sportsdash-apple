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
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
                state.channelStatus?.let {
                    Text(it, color = Muted, modifier = Modifier.padding(16.dp))
                }
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Gold)
                }
            }
            else -> {
                // Search + list/grid toggle (iOS Guide has List + Grid layouts)
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OutlinedTextField(
                        value = state.searchQuery,
                        onValueChange = { vm.setSearchQuery(it) },
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("Search channels", color = Muted) },
                        leadingIcon = {
                            Icon(Icons.Default.Search, null, tint = Muted)
                        },
                        singleLine = true,
                        colors = guideFieldColors(),
                    )
                    IconButton(
                        onClick = { vm.setGuideLayout(GuideLayout.LIST) },
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.List,
                            contentDescription = "List",
                            tint = if (state.guideLayout == GuideLayout.LIST) Gold else Muted,
                        )
                    }
                    IconButton(
                        onClick = { vm.setGuideLayout(GuideLayout.GRID) },
                    ) {
                        Icon(
                            Icons.Default.GridView,
                            contentDescription = "Grid",
                            tint = if (state.guideLayout == GuideLayout.GRID) Gold else Muted,
                        )
                    }
                }

                if (state.groups.size > 1) {
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(items = state.groups) { group ->
                            FilterChip(
                                selected = state.selectedGroup == group,
                                onClick = { vm.selectGroup(group) },
                                label = {
                                    Text(group, maxLines = 1, overflow = TextOverflow.Ellipsis)
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

                state.channelStatus?.let {
                    Text(
                        it + " · ${if (state.guideLayout == GuideLayout.LIST) "List" else "Grid"}",
                        color = Muted,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                }
                state.channelError?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp))
                }

                val channels = vm.filteredChannels()
                when (state.guideLayout) {
                    GuideLayout.LIST -> {
                        LazyColumn(
                            contentPadding = PaddingValues(12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(items = channels, key = { it.id }) { ch ->
                                ChannelListRow(ch) { vm.play(ch) }
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
                            items(items = channels, key = { it.id }) { ch ->
                                ChannelGridCard(ch) { vm.play(ch) }
                            }
                        }
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
        ChannelLogo(channel)
        Spacer(Modifier.width(10.dp))
        Column(Modifier = Modifier.weight(1f)) {
            Text(channel.name, color = TextPrimary, fontWeight = FontWeight.SemiBold, maxLines = 2)
            channel.group?.let {
                Text(it, color = Muted, style = MaterialTheme.typography.bodySmall, maxLines = 1)
            }
        }
        Icon(Icons.Default.PlayArrow, null, tint = Gold)
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
            Modifier
                .fillMaxWidth()
                .aspectRatio(1.2f)
                .clip(RoundedCornerShape(10.dp))
                .background(VoidBlack),
            contentAlignment = Alignment.Center,
        ) {
            if (!channel.logo.isNullOrBlank()) {
                AsyncImage(
                    model = channel.logo,
                    contentDescription = channel.name,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(12.dp),
                    contentScale = ContentScale.Fit,
                )
            } else {
                Icon(Icons.Default.LiveTv, null, tint = Gold, modifier = Modifier.size(36.dp))
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            channel.name,
            color = TextPrimary,
            fontWeight = FontWeight.SemiBold,
            fontSize = 13.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        channel.group?.let {
            Text(it, color = Muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun ChannelLogo(channel: IptvChannel) {
    if (!channel.logo.isNullOrBlank()) {
        AsyncImage(
            model = channel.logo,
            contentDescription = null,
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(8.dp)),
            contentScale = ContentScale.Fit,
        )
    } else {
        Box(
            Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(VoidBlack),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Default.PlayArrow, null, tint = Gold, modifier = Modifier.size(22.dp))
        }
    }
}

@Composable
private fun EmptyGuideHint() {
    Column(
        Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Default.LiveTv, null, tint = Gold, modifier = Modifier.size(48.dp))
        Spacer(Modifier.height(12.dp))
        Text("Guide", color = TextPrimary, style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(8.dp))
        Text(
            "Add an Xtream server URL + credentials (or M3U URL) in Settings. " +
                "Use List or Grid layout. Full EPG timeline is next.",
            color = Muted,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(16.dp))
        Text("→ Settings tab", color = Gold, fontWeight = FontWeight.Bold)
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
