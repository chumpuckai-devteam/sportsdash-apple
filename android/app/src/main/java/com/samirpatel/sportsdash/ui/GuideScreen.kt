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
import androidx.compose.foundation.lazy.rememberLazyListState
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
import com.samirpatel.sportsdash.ui.tv.tvFocusRing

/**
 * Guide: no search. Main bar = ★ / Hour / Grid + one ☰ categories menu.
 * Long-press channel → favorites. Sheet is categories only (no duplicate actions).
 */
@Composable
fun GuideScreen(
    vm: AppViewModel,
    state: AppUiState,
    landscape: Boolean = false,
    isTelevision: Boolean = false,
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
    onGoScores: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    var favoriteTarget by remember { mutableStateOf<IptvChannel?>(null) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    Column(modifier = Modifier.fillMaxSize()) {
        GuideActionBar(
            state = state,
            landscape = landscape,
            onFavorites = { vm.selectGroup(FAVORITES_GROUP) },
            onHourGuide = { vm.setGuideLayout(GuideLayout.LIST) },
            onGrid = { vm.setGuideLayout(GuideLayout.GRID) },
            onToggleMoviesNow = { vm.setMoviesNow(!state.moviesNow) },
            onMenu = { showMenu = true },
            onGoScores = onGoScores,
        )

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
            val channels = vm.guideChannels()
            when (state.guideLayout) {
                GuideLayout.LIST -> {
                    if (channels.isEmpty() && state.selectedGroup == FAVORITES_GROUP) {
                        EmptyFavoritesHint()
                    } else {
                        GuideTimeline(
                            channels = channels,
                            programsFor = { id -> vm.programsFor(id) },
                            windowStartMs = state.guideWindowStartMs,
                            onPlay = { ch -> vm.play(ch) },
                            onLongPressChannel = { ch -> favoriteTarget = ch },
                            onShiftHours = { h -> vm.shiftGuideWindowHours(h) },
                            onResetToNow = { vm.resetGuideWindowToNow() },
                            favoriteIds = state.favoriteChannelIds,
                            displayName = { ch -> vm.displayChannelName(ch.name) },
                            ratingFor = { ch -> vm.ratingForTitle(vm.nowTitle(ch.id)) },
                            ratingLoadingFor = { ch -> vm.isRatingLoading(vm.nowTitle(ch.id)) },
                            onRequestRating = { ch ->
                                vm.requestMovieRating(
                                    title = vm.nowTitle(ch.id),
                                    channelGroup = ch.group,
                                    channelName = ch.name,
                                )
                            },
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
                GuideLayout.GRID -> {
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
                                    displayName = vm.displayChannelName(ch.name),
                                    nowTitle = vm.nowTitle(ch.id),
                                    rating = vm.ratingForTitle(vm.nowTitle(ch.id)),
                                    ratingLoading = vm.isRatingLoading(vm.nowTitle(ch.id)),
                                    isFavorite = ch.id in state.favoriteChannelIds,
                                    tvFocus = isTelevision,
                                    onPlay = { vm.play(ch) },
                                    onLongPress = { favoriteTarget = ch },
                                    onRequestRating = {
                                        vm.requestMovieRating(
                                            title = vm.nowTitle(ch.id),
                                            channelGroup = ch.group,
                                            channelName = ch.name,
                                        )
                                    },
                                )
                            }
                        }
                    }
                }
            }

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
            GuideCategoryMenuSheet(
                categories = vm.guideCategoryGroups(),
                selectedGroup = state.selectedGroup,
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
    onToggleMoviesNow: () -> Unit,
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
            IconButton(onClick = onGoScores) {
                Icon(Icons.Default.LiveTv, contentDescription = "Guide", tint = Gold)
            }
        }
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
        FilterChip(
            selected = state.moviesNow,
            onClick = onToggleMoviesNow,
            label = { Text("Movies", maxLines = 1) },
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
            Icon(Icons.Default.Menu, contentDescription = "Categories", tint = Gold)
        }
    }
}

/** Categories only — actions stay on the main bar. Scrolls to current selection. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GuideCategoryMenuSheet(
    categories: List<String>,
    selectedGroup: String,
    onSelectGroup: (String) -> Unit,
    onRefresh: () -> Unit,
    onClose: () -> Unit,
) {
    val selectedIndex = categories.indexOf(selectedGroup).coerceAtLeast(0)
    val listState = rememberLazyListState(
        initialFirstVisibleItemIndex = selectedIndex,
    )
    LaunchedEffect(selectedGroup, categories) {
        val idx = categories.indexOf(selectedGroup)
        if (idx >= 0) {
            listState.scrollToItem(idx)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(bottom = 28.dp),
    ) {
        Text("Categories", color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text(
            "Provider order · current selection stays highlighted",
            color = Muted,
            fontSize = 12.sp,
            modifier = Modifier.padding(top = 4.dp, bottom = 12.dp),
        )

        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxWidth()
                .height(380.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            listItems(items = categories, key = { it }) { group ->
                val selected = selectedGroup == group
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
    displayName: String = channel.name,
    nowTitle: String?,
    rating: com.samirpatel.sportsdash.core.ratings.MovieRating? = null,
    ratingLoading: Boolean = false,
    isFavorite: Boolean,
    tvFocus: Boolean = false,
    onPlay: () -> Unit,
    onLongPress: () -> Unit,
    onRequestRating: () -> Unit = {},
) {
    Column(
        modifier = Modifier
            .tvFocusRing(enabled = tvFocus, shape = RoundedCornerShape(12.dp))
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
            text = if (isFavorite) "★ $displayName" else displayName,
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
            "Add Xtream in Settings. Use ★ / Hour / Grid on the bar. ☰ opens categories. " +
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
