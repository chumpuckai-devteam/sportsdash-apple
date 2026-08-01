package com.samirpatel.sportsdash.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.lazy.items as listItems
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
import com.samirpatel.sportsdash.FAVORITES_GROUP
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

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun GuideBrowseBody(vm: AppViewModel, state: AppUiState) {
    var showMenu by remember { mutableStateOf(false) }
    var favoriteTarget by remember { mutableStateOf<IptvChannel?>(null) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    Column(modifier = Modifier.fillMaxSize()) {
        // Compact chrome — more room for the guide
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            FilterChip(
                selected = state.selectedGroup == FAVORITES_GROUP,
                onClick = { vm.selectGroup(FAVORITES_GROUP) },
                label = {
                    Text(
                        text = "★ Favorites",
                        maxLines = 1,
                    )
                },
                leadingIcon = {
                    Icon(
                        imageVector = if (state.selectedGroup == FAVORITES_GROUP) {
                            Icons.Default.Star
                        } else {
                            Icons.Default.StarBorder
                        },
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                },
                colors = chipColors(),
            )
            Text(
                text = state.selectedGroup.ifBlank { "Category" },
                color = TextPrimary,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = if (state.guideLayout == GuideLayout.LIST) "Hour" else "Grid",
                color = Gold,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
            )
            IconButton(onClick = { showMenu = true }) {
                Icon(
                    imageVector = Icons.Default.Menu,
                    contentDescription = "Guide menu",
                    tint = Gold,
                )
            }
        }

        // Thin status only (one line preferred)
        val statusBits = buildList {
            state.channelStatus?.let { add(it) }
            state.epgStatus?.takeIf { it.isNotBlank() }?.let { add(it) }
            if (state.isLoadingEpg) state.bulkEpgStatus?.let { add(it) }
        }.joinToString(" · ")
        if (statusBits.isNotBlank()) {
            Text(
                text = statusBits + if (state.isLoadingEpg || state.isAutoFillingEpg) " …" else "",
                color = if (state.isLoadingEpg || state.isAutoFillingEpg) Gold else Muted,
                style = MaterialTheme.typography.bodySmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
            )
        }
        state.channelError?.let { err ->
            Text(
                text = err,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
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
                        onLongPressChannel = { ch -> favoriteTarget = ch },
                        onShiftHours = { d -> vm.shiftGuideWindowHours(d) },
                        onResetToNow = { vm.resetGuideWindowToNow() },
                        favoriteIds = state.favoriteChannelIds,
                        modifier = Modifier.fillMaxSize(),
                    )
                    val catCovered = vm.guideChannels().count { ch ->
                        !state.epgByChannelId[ch.id].isNullOrEmpty()
                    }
                    if (state.isLoadingEpg && catCovered == 0 &&
                        state.selectedGroup != FAVORITES_GROUP
                    ) {
                        EpgLoadingCard(
                            title = "Loading full TV guide",
                            status = state.bulkEpgStatus ?: state.epgStatus,
                        )
                    }
                    if (state.selectedGroup == FAVORITES_GROUP &&
                        vm.guideChannels().isEmpty()
                    ) {
                        EmptyFavoritesHint()
                    }
                }
            }
            GuideLayout.GRID -> {
                Box(modifier = Modifier.fillMaxSize()) {
                    val channels = vm.guideChannels()
                    if (channels.isEmpty() && state.selectedGroup == FAVORITES_GROUP) {
                        EmptyFavoritesHint()
                    } else {
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
                                    isFavorite = ch.id in state.favoriteChannelIds,
                                    onPlay = { vm.play(ch) },
                                    onLongPress = { favoriteTarget = ch },
                                )
                            }
                        }
                    }
                    val catCovered = channels.count { ch ->
                        !state.epgByChannelId[ch.id].isNullOrEmpty()
                    }
                    if (state.isLoadingEpg && catCovered == 0 &&
                        state.selectedGroup != FAVORITES_GROUP &&
                        channels.isNotEmpty()
                    ) {
                        EpgLoadingCard(
                            title = "Loading full TV guide",
                            status = state.bulkEpgStatus ?: state.epgStatus,
                        )
                    }
                }
            }
        }
    }

    if (showMenu) {
        ModalBottomSheet(
            onDismissRequest = { showMenu = false },
            sheetState = sheetState,
            containerColor = Panel,
        ) {
            GuideMenuSheet(
                state = state,
                categories = vm.guideCategoryGroups(),
                onSelectLayout = {
                    vm.setGuideLayout(it)
                },
                onSelectGroup = {
                    vm.selectGroup(it)
                    showMenu = false
                },
                onClose = { showMenu = false },
            )
        }
    }

    favoriteTarget?.let { ch ->
        val fav = ch.id in state.favoriteChannelIds
        AlertDialog(
            onDismissRequest = { favoriteTarget = null },
            title = { Text(ch.name) },
            text = {
                Text(
                    if (fav) {
                        "Remove this channel from Favorites?"
                    } else {
                        "Add this channel to Favorites?"
                    },
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (fav) vm.removeFavorite(ch) else vm.addFavorite(ch)
                        favoriteTarget = null
                    },
                ) {
                    Text(if (fav) "Remove" else "Add", color = Gold)
                }
            },
            dismissButton = {
                TextButton(onClick = { favoriteTarget = null }) {
                    Text("Cancel", color = Muted)
                }
            },
            containerColor = Panel,
            titleContentColor = TextPrimary,
            textContentColor = Muted,
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GuideMenuSheet(
    state: AppUiState,
    categories: List<String>,
    onSelectLayout: (GuideLayout) -> Unit,
    onSelectGroup: (String) -> Unit,
    onClose: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(bottom = 32.dp),
    ) {
        Text(
            text = "Guide menu",
            color = TextPrimary,
            fontWeight = FontWeight.Bold,
            fontSize = 18.sp,
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text("Layout", color = Muted, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = state.guideLayout == GuideLayout.LIST,
                onClick = { onSelectLayout(GuideLayout.LIST) },
                label = { Text("Hour guide") },
                colors = chipColors(),
            )
            FilterChip(
                selected = state.guideLayout == GuideLayout.GRID,
                onClick = { onSelectLayout(GuideLayout.GRID) },
                label = { Text("Grid") },
                colors = chipColors(),
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            "Categories (provider order)",
            color = Muted,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
        )
        Spacer(modifier = Modifier.height(6.dp))
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .height(360.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            listItems(items = categories, key = { it }) { group ->
                val selected = state.selectedGroup == group
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (selected) Gold.copy(alpha = 0.2f) else VoidBlack)
                        .combinedClickable(onClick = { onSelectGroup(group) })
                        .padding(horizontal = 12.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = group,
                        color = if (selected) Gold else TextPrimary,
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                        modifier = Modifier.weight(1f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        TextButton(onClick = onClose, modifier = Modifier.align(Alignment.End)) {
            Text("Done", color = Gold)
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

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ChannelGridCard(
    channel: IptvChannel,
    nowTitle: String?,
    isFavorite: Boolean,
    onPlay: () -> Unit,
    onLongPress: () -> Unit,
) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(14.dp))
            .background(Panel)
            .combinedClickable(
                onClick = onPlay,
                onLongClick = onLongPress,
            )
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
            if (isFavorite) {
                Icon(
                    imageVector = Icons.Default.Star,
                    contentDescription = "Favorite",
                    tint = Gold,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .size(16.dp),
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
private fun EmptyFavoritesHint() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Default.StarBorder, contentDescription = null, tint = Gold, modifier = Modifier.size(40.dp))
        Spacer(modifier = Modifier.height(12.dp))
        Text("No favorites yet", color = TextPrimary, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Long-press any channel in Guide or Grid to add it here.",
            color = Muted,
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
            text = "Add Xtream credentials in Settings. Open the menu (☰) for categories " +
                "and hour/grid layout. Long-press a channel to favorite.",
            color = Muted,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(text = "→ Settings tab", color = Gold, fontWeight = FontWeight.Bold)
    }
}
