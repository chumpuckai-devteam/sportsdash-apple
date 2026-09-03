package com.samirpatel.sportsdash.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import com.samirpatel.sportsdash.ui.theme.BebasNeue
import com.samirpatel.sportsdash.ui.theme.Border
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.GuideRowHeight
import com.samirpatel.sportsdash.ui.theme.JumbotronLed
import com.samirpatel.sportsdash.ui.theme.JumbotronMessagePanel
import com.samirpatel.sportsdash.ui.theme.JumbotronScreenTitle
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.ScreenInset
import com.samirpatel.sportsdash.ui.theme.SpaceMono
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack
import com.samirpatel.sportsdash.ui.theme.brandStripe
import com.samirpatel.sportsdash.ui.theme.jumbotronPanel
import com.samirpatel.sportsdash.core.epg.nowPlaying
import com.samirpatel.sportsdash.ui.tv.tvFocusGroup
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
                isTelevision = isTelevision,
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
    isTelevision: Boolean = false,
    onGoScores: () -> Unit,
) {
    val epg by vm.epg.collectAsState()
    var showMenu by remember { mutableStateOf(false) }
    var favoriteTarget by remember { mutableStateOf<IptvChannel?>(null) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    Column(modifier = Modifier.fillMaxSize()) {
        if (isTelevision || landscape) GuideActionBar(
            state = state,
            landscape = landscape,
            isTelevision = isTelevision,
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
            epg.epgStatus?.takeIf { !epg.isLoadingEpg },
            epg.bulkEpgStatus?.takeIf { epg.isLoadingEpg },
        ).joinToString(" · ")
        if (status.isNotBlank() && (isTelevision || landscape)) {
            Text(
                text = status + if (epg.isLoadingEpg || epg.isAutoFillingEpg) " …" else "",
                color = if (epg.isLoadingEpg || epg.isAutoFillingEpg) Gold else Muted,
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
                    } else if (isTelevision) {
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
                            tvFocus = isTelevision,
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        GuideNowBarPhone(
                            vm = vm,
                            state = state,
                            channels = channels.filter { it.url.isNotBlank() },
                            onPlay = { ch -> vm.play(ch) },
                            onLongPress = { ch -> favoriteTarget = ch },
                            onOpenCategories = { showMenu = true },
                            onGrid = { vm.setGuideLayout(GuideLayout.GRID) },
                            onMovies = { vm.setMoviesNow(!state.moviesNow) },
                        )
                    }
                }
                GuideLayout.GRID -> {
                  Column(modifier = Modifier.fillMaxSize()) {
                    if (!isTelevision && !landscape) {
                        Column(modifier = Modifier.fillMaxWidth().padding(horizontal = ScreenInset, vertical = 4.dp)) {
                            JumbotronScreenTitle(first = "CHANNEL ", gold = "GUIDE")
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                modifier = Modifier.padding(top = 8.dp, bottom = 8.dp),
                            ) {
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .height(38.dp)
                                        .jumbotronPanel(Gold.copy(alpha = 0.5f))
                                        .clickable { showMenu = true }
                                        .padding(horizontal = 12.dp),
                                    contentAlignment = Alignment.CenterStart,
                                ) {
                                    Text(
                                        (state.selectedGroup.ifBlank { "★ FAVORITES" }).uppercase(),
                                        color = Gold,
                                        fontFamily = BebasNeue,
                                        fontSize = 18.sp,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                                Box(
                                    modifier = Modifier
                                        .width(64.dp)
                                        .height(38.dp)
                                        .jumbotronPanel()
                                        .clickable { vm.setGuideLayout(GuideLayout.LIST) },
                                    contentAlignment = Alignment.Center,
                                ) { Text("LIST", color = Muted, fontFamily = BebasNeue, fontSize = 16.sp) }
                                Box(
                                    modifier = Modifier
                                        .width(74.dp)
                                        .height(38.dp)
                                        .background(Gold)
                                        .clickable { vm.setMoviesNow(!state.moviesNow) },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text("MOVIES", color = VoidBlack, fontFamily = BebasNeue, fontSize = 16.sp)
                                }
                            }
                        }
                    }
                    if (channels.isEmpty() && state.selectedGroup == FAVORITES_GROUP) {
                        EmptyFavoritesHint()
                    } else {
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(minSize = if (landscape) 120.dp else 140.dp),
                            contentPadding = PaddingValues(10.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.weight(1f).fillMaxWidth(),
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
            }

            val catCovered = channels.count { !epg.epgByChannelId[it.id].isNullOrEmpty() }
            if (epg.isLoadingEpg && catCovered == 0 &&
                state.selectedGroup != FAVORITES_GROUP &&
                channels.isNotEmpty()
            ) {
                EpgLoadingCard(
                    title = "Loading full TV guide",
                    status = epg.bulkEpgStatus ?: epg.epgStatus,
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
                tvFocus = isTelevision,
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
    isTelevision: Boolean = false,
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
            .padding(horizontal = 6.dp, vertical = 4.dp)
            .tvFocusGroup(enabled = isTelevision),
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
    tvFocus: Boolean = false,
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
                        .tvFocusRing(enabled = tvFocus, shape = RoundedCornerShape(10.dp))
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

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GuideNowBarPhone(
    vm: AppViewModel,
    state: AppUiState,
    channels: List<IptvChannel>,
    onPlay: (IptvChannel) -> Unit,
    onLongPress: (IptvChannel) -> Unit,
    onOpenCategories: () -> Unit,
    onGrid: () -> Unit,
    onMovies: () -> Unit,
) {
    val now = System.currentTimeMillis()
    val liveCount = channels.count { vm.programsFor(it.id).nowPlaying(now) != null }
    val sdf = remember { java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()) }
    val hourChips = remember {
        val cal = java.util.Calendar.getInstance()
        cal.set(java.util.Calendar.MINUTE, 0)
        cal.set(java.util.Calendar.SECOND, 0)
        cal.set(java.util.Calendar.MILLISECOND, 0)
        (1..3).map {
            cal.add(java.util.Calendar.HOUR_OF_DAY, 1)
            cal.timeInMillis
        }
    }
    Column(modifier = Modifier.fillMaxSize().padding(horizontal = ScreenInset)) {
        JumbotronScreenTitle(first = "CHANNEL ", gold = "GUIDE", modifier = Modifier.padding(top = 4.dp, bottom = 12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(38.dp)
                    .jumbotronPanel(Gold.copy(alpha = 0.5f))
                    .clickable(onClick = onOpenCategories)
                    .padding(horizontal = 12.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                Text(
                    (state.selectedGroup.ifBlank { "★ FAVORITES" }).uppercase(),
                    color = Gold,
                    fontFamily = BebasNeue,
                    fontSize = 18.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Box(
                modifier = Modifier.width(64.dp).height(38.dp).jumbotronPanel().clickable(onClick = onGrid),
                contentAlignment = Alignment.Center,
            ) { Text("GRID", color = Muted, fontFamily = BebasNeue, fontSize = 16.sp) }
            Box(
                modifier = Modifier
                    .width(74.dp)
                    .height(38.dp)
                    .then(if (state.moviesNow) Modifier.background(Gold) else Modifier.jumbotronPanel())
                    .clickable(onClick = onMovies),
                contentAlignment = Alignment.Center,
            ) {
                Text("MOVIES", color = if (state.moviesNow) VoidBlack else Muted, fontFamily = BebasNeue, fontSize = 16.sp)
            }
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.padding(top = 8.dp, bottom = 10.dp),
        ) {
            Box(
                modifier = Modifier.background(LiveMint).padding(horizontal = 10.dp).height(26.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text("NOW · $liveCount LIVE", color = VoidBlack, fontFamily = BebasNeue, fontSize = 14.sp)
            }
            hourChips.forEach { t ->
                Box(
                    modifier = Modifier.border(1.dp, Border).padding(horizontal = 10.dp).height(26.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(sdf.format(java.util.Date(t)), color = Muted, fontFamily = BebasNeue, fontSize = 14.sp)
                }
            }
        }
        if (channels.isEmpty()) {
            JumbotronMessagePanel(
                title = "NO CHANNELS IN THIS CATEGORY",
                subtitle = "Pick another category.",
                cta = "CHOOSE CATEGORY",
                onClick = onOpenCategories,
            )
        } else {
            LazyColumn(modifier = Modifier.weight(1f).jumbotronPanel()) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().height(28.dp).padding(start = 15.dp, end = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("CH", color = Muted, fontFamily = SpaceMono, fontSize = 9.sp, modifier = Modifier.width(40.dp))
                        Text("NAME", color = Muted, fontFamily = SpaceMono, fontSize = 9.sp, modifier = Modifier.width(74.dp))
                        Text("NOW", color = Muted, fontFamily = SpaceMono, fontSize = 9.sp, modifier = Modifier.weight(1f))
                        JumbotronLed("▼ ${sdf.format(java.util.Date(now))}", size = 9, color = LiveMint, glow = true)
                    }
                }
                listItems(items = channels, key = { it.id }) { ch ->
                    val idx = channels.indexOf(ch) + 1
                    val programs = vm.programsFor(ch.id)
                    val prog = programs.nowPlaying(now) ?: programs.firstOrNull()
                    val live = programs.nowPlaying(now) != null
                    val progress = if (prog != null && prog.durationMs > 0) {
                        ((now - prog.startMs).toFloat() / prog.durationMs).coerceIn(0f, 1f)
                    } else 0f
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(GuideRowHeight)
                            .combinedClickable(onClick = { onPlay(ch) }, onLongClick = { onLongPress(ch) }),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.width(5.dp).height(GuideRowHeight).background(brandStripe(ch.group)))
                        JumbotronLed("%03d".format(idx), size = 13, color = Gold, glow = true, modifier = Modifier.width(40.dp).padding(start = 4.dp))
                        Text(
                            vm.displayChannelName(ch.name).uppercase(),
                            color = TextPrimary,
                            fontFamily = BebasNeue,
                            fontSize = 18.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.width(74.dp),
                        )
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(36.dp)
                                .padding(end = 8.dp)
                                .background(VoidBlack)
                                .border(1.dp, Border),
                        ) {
                            if (live) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxHeight()
                                        .fillMaxWidth(progress)
                                        .background(LiveMint.copy(alpha = 0.22f)),
                                )
                            }
                            Row(
                                modifier = Modifier.fillMaxSize().padding(horizontal = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        (prog?.title ?: "NO LISTING").uppercase(),
                                        color = TextPrimary,
                                        fontFamily = SpaceMono,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 11.sp,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    if (prog != null) {
                                        Text(
                                            "ENDS ${sdf.format(java.util.Date(prog.endMs))}",
                                            color = Muted,
                                            fontFamily = SpaceMono,
                                            fontSize = 8.sp,
                                        )
                                    }
                                }
                                if (live) {
                                    JumbotronLed("LIVE", size = 8, color = LiveMint, glow = true)
                                }
                            }
                        }
                    }
                }
            }
        }
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
