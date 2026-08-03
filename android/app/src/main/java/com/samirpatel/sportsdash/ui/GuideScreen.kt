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
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.ViewList
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
import androidx.compose.runtime.LaunchedEffect
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

/**
 * Guide: **no search bar**, **no sticky category strip**.
 * Compact action row + ☰ menu for Favorites / Hour / Grid / categories.
 * Long-press channel → add/remove favorites.
 */
@Composable
fun GuideScreen(
    vm: AppViewModel,
    state: AppUiState,
    landscape: Boolean = false,
    openMenu: Boolean = false,
    onMenuConsumed: () -> Unit = {},
    onOpenMenu: () -> Unit = {},
    onGoSettings: () -> Unit = {},
    onGoScores: () -> Unit = {},
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(VoidBlack),
    ) {
        when {
            state.playlist == null -> EmptyGuideHint(onGoSettings = onGoSettings)
            state.isLoadingChannels && state.channels.isEmpty() -> {
                state.channelStatus?.let {
                    Text(text = it, color = Muted, modifier = Modifier.padding(16.dp))
                }
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Gold)
                }
            }
            else -> GuideBrowseBody(
                vm = vm,
                state = state,
                landscape = landscape,
                openMenu = openMenu,
                onMenuConsumed = onMenuConsumed,
                onOpenMenu = onOpenMenu,
                onGoScores = onGoScores,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun GuideBrowseBody(
    vm: AppViewModel,
    state: AppUiState,
    landscape: Boolean,
    openMenu: Boolean,
    onMenuConsumed: () -> Unit,
    onOpenMenu: () -> Unit,
    onGoScores: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    var favoriteTarget by remember { mutableStateOf<IptvChannel?>(null) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    LaunchedEffect(openMenu) {
        if (openMenu) {
            showMenu = true
            onMenuConsumed()
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // ONE compact action row — nothing else sticky above the grid
        GuideActionBar(
            state = state,
            landscape = landscape,
            onFavorites = { vm.selectGroup(FAVORITES_GROUP) },
            onHourGuide = { vm.setGuideLayout(GuideLayout.LIST) },
            onGrid = { vm.setGuideLayout(GuideLayout.GRID) },
            onMenu = {
                showMenu = true
                onOpenMenu()
            },
            onGoScores = onGoScores,
        )

        // Single muted status line (collapses noise)
        val status = listOfNotNull(
            state.selectedGroup.takeIf { it.isNotBlank() },
            if (state.guideLayout == GuideLayout.LIST) "Hour" else "Grid",
            state.epgStatus?.takeIf { !state.isLoadingEpg },
            state.bulkEpgStatus?.takeIf { state.isLoadingEpg },
        ).joinToString(" · ")
        if (status.isNotBlank()) {
            Text(
                text = status + if (state.isLoadingEpg || state.isAutoFillingEpg) " …" else "",
                color = if (state.isLoadingEpg || state.isAutoFillingEpg) Gold else Muted,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
            )
        }

        Box(modifier = Modifier.fillMaxSize()) {
            when (state.guideLayout) {
                GuideLayout.LIST -> {
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
                }
                GuideLayout.GRID -> {
                    val channels = vm.guideChannels()
                    if (channels.isEmpty() && state.selectedGroup == FAVORITES_GROUP) {
                        EmptyFavoritesHint()
                    } else {
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(minSize = if (landscape) 120.dp else 140.dp),
                            contentPadding = PaddingValues(10.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
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
                }
            }

            val channels = vm.guideChannels()
            val catCovered = channels.count { !state.epgByChannelId[it.id].isNullOrEmpty() }
            if (state.isLoadingEpg && catCovered == 0 &&
                state.selectedGroup != FAVORITES_GROUP &&
                channels.isNotEmpty()
            ) {
                EpgLoadingCard(
                    title = "Loading full TV guide",
                    status = state.bulkEpgStatus ?: state.epgStatus,
                )
            }
            if (state.selectedGroup == FAVORITES_GROUP && channels.isEmpty() &&
                state.guideLayout == GuideLayout.LIST
            ) {
                EmptyFavoritesHint()
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
                favoriteCount = state.favoriteChannelIds.size,
                onSelectLayout = { vm.setGuideLayout(it) },
                onSelectGroup = {
                    vm.selectGroup(it)
                    showMenu = false
                },
                onRefresh = {
                    vm.refreshChannels()
                    vm.reloadEpg(force = true)
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
            title = { Text(ch.name, color = TextPrimary) },
            text = {
                Text(
                    if (fav) "Remove from Favorites?" else "Add to Favorites?",
                    color = Muted,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (fav) vm.removeFavorite(ch) else vm.addFavorite(ch)
                        favoriteTarget = null
                    },
                ) { Text(if (fav) "Remove" else "Add to Favorites", color = Gold) }
            },
            dismissButton = {
                TextButton(onClick = { favoriteTarget = null }) {
                    Text("Cancel", color = Muted)
                }
            },
            containerColor = Panel,
        )
    }
}

@Composable
private fun GuideActionBar(
    state: AppUiState,
    landscape: Boolean,
    onFavorites: () -> Unit,
    onHourGuide: () -> Unit,
    onGrid: () -> Unit,
    onMenu: () -> Unit,
    onGoScores: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(VoidBlack)
            .padding(horizontal = 6.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (landscape) {
            // Landscape: tab jump without bottom bar
            IconButton(onClick = onGoScores) {
                Icon(Icons.Default.LiveTv, contentDescription = "Guide", tint = Gold)
            }
        }
        // Quick actions — not a permanent category strip
        FilterChip(
            selected = state.selectedGroup == FAVORITES_GROUP,
            onClick = onFavorites,
            label = { Text("★", maxLines = 1) },
            colors = chipColors(),
        )
        FilterChip(
            selected = state.guideLayout == GuideLayout.LIST &&
                state.selectedGroup != FAVORITES_GROUP,
            onClick = onHourGuide,
            label = {
                Icon(Icons.Default.ViewList, contentDescription = "Hour guide", modifier = Modifier.size(16.dp))
            },
            colors = chipColors(),
        )
        FilterChip(
            selected = state.guideLayout == GuideLayout.GRID,
            onClick = onGrid,
            label = {
                Icon(Icons.Default.Apps, contentDescription = "Grid", modifier = Modifier.size(16.dp))
            },
            colors = chipColors(),
        )
        Text(
            text = state.selectedGroup.ifBlank { "Pick category" },
            color = TextPrimary,
            fontWeight = FontWeight.SemiBold,
            fontSize = 13.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 4.dp),
        )
        IconButton(onClick = onMenu) {
            Icon(Icons.Default.Menu, contentDescription = "Menu", tint = Gold)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GuideMenuSheet(
    state: AppUiState,
    categories: List<String>,
    favoriteCount: Int,
    onSelectLayout: (GuideLayout) -> Unit,
    onSelectGroup: (String) -> Unit,
    onRefresh: () -> Unit,
    onClose: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(bottom = 28.dp),
    ) {
        Text("Guide", color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text(
            "Favorites, layout, and categories — no permanent search strip.",
            color = Muted,
            fontSize = 12.sp,
            modifier = Modifier.padding(top = 4.dp, bottom = 12.dp),
        )

        Text("ACTIONS", color = Muted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = state.selectedGroup == FAVORITES_GROUP,
                onClick = { onSelectGroup(FAVORITES_GROUP) },
                label = { Text("★ Favorites ($favoriteCount)") },
                colors = chipColors(),
            )
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

        Spacer(modifier = Modifier.height(14.dp))
        Text("CATEGORIES (provider order)", color = Muted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(6.dp))
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .height(320.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            listItems(items = categories, key = { it }) { group ->
                val selected = state.selectedGroup == group
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (selected) Gold.copy(alpha = 0.22f) else VoidBlack)
                        .combinedClickable(onClick = { onSelectGroup(group) })
                        .padding(horizontal = 12.dp, vertical = 12.dp),
                ) {
                    Text(
                        text = group,
                        color = if (selected) Gold else TextPrimary,
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            TextButton(onClick = onRefresh) { Text("Reload guide", color = Gold) }
            TextButton(onClick = onClose) { Text("Done", color = Gold) }
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
            .clip(RoundedCornerShape(12.dp))
            .background(Panel)
            .combinedClickable(onClick = onPlay, onLongClick = onLongPress)
            .padding(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1.25f)
                .clip(RoundedCornerShape(8.dp))
                .background(VoidBlack),
            contentAlignment = Alignment.Center,
        ) {
            val logo = channel.logo
            if (!logo.isNullOrBlank()) {
                AsyncImage(
                    model = logo,
                    contentDescription = channel.name,
                    modifier = Modifier.fillMaxSize().padding(10.dp),
                    contentScale = ContentScale.Fit,
                )
            } else {
                Icon(Icons.Default.LiveTv, null, tint = Gold, modifier = Modifier.size(32.dp))
            }
            if (isFavorite) {
                Icon(
                    Icons.Default.Star,
                    contentDescription = "Favorite",
                    tint = Gold,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(4.dp)
                        .size(14.dp),
                )
            }
        }
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            channel.name,
            color = TextPrimary,
            fontWeight = FontWeight.SemiBold,
            fontSize = 12.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        Text(
            nowTitle?.takeIf { it.isNotBlank() } ?: (channel.group ?: "No guide"),
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
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Default.StarBorder, null, tint = Gold, modifier = Modifier.size(40.dp))
        Spacer(modifier = Modifier.height(12.dp))
        Text("No favorites yet", color = TextPrimary, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Long-press any channel → Add to Favorites.",
            color = Muted,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun EmptyGuideHint(onGoSettings: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Default.LiveTv, null, tint = Gold, modifier = Modifier.size(48.dp))
        Spacer(modifier = Modifier.height(12.dp))
        Text("Guide", color = TextPrimary, style = MaterialTheme.typography.titleLarge)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Add Xtream in Settings. Use ☰ for categories, Hour/Grid, and Favorites. " +
                "Long-press a channel to star it.",
            color = Muted,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(16.dp))
        TextButton(onClick = onGoSettings) {
            Text("→ Settings", color = Gold, fontWeight = FontWeight.Bold)
        }
    }
}
