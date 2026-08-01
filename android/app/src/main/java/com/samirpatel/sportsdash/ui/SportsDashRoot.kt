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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Scoreboard
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Sports
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import coil.compose.AsyncImage
import com.samirpatel.sportsdash.AppUiState
import com.samirpatel.sportsdash.AppViewModel
import com.samirpatel.sportsdash.ScoresFilter
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.player.VlcPlayerController
import com.samirpatel.sportsdash.core.player.createVlcVideoLayout
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.core.sports.SportLeague
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SportsDashRoot(vm: AppViewModel) {
    val state by vm.state.collectAsState()
    // 0 Scores · 1 Guide · 2 Settings — matches iOS
    var tab by remember { mutableIntStateOf(0) }

    val playing = state.playing
    val playUrl = state.playUrl
    if (playing != null && playUrl != null) {
        PlayerScreen(
            channel = playing,
            url = playUrl,
            engineLabel = state.engineLabel,
            onClose = { vm.stopPlayback() },
        )
        return
    }

    Scaffold(
        containerColor = VoidBlack,
        topBar = {
            TopAppBar(
                title = {
                    Text("SportsDash", fontWeight = FontWeight.Bold, color = Gold)
                },
                actions = {
                    IconButton(
                        onClick = {
                            when (tab) {
                                0 -> vm.refreshScores()
                                1 -> vm.refreshChannels()
                                else -> Unit
                            }
                        },
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh", tint = Gold)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = VoidBlack,
                    titleContentColor = Gold,
                ),
            )
        },
        bottomBar = {
            NavigationBar(containerColor = Panel) {
                NavItem(tab == 0, { tab = 0 }, Icons.Default.Scoreboard, "Scores")
                NavItem(tab == 1, { tab = 1 }, Icons.Default.LiveTv, "Guide")
                NavItem(tab == 2, { tab = 2 }, Icons.Default.Settings, "Settings")
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
        ) {
            when (tab) {
                0 -> ScoresScreen(vm, state)
                1 -> GuideScreen(vm, state)
                else -> SettingsScreen(vm, state)
            }
        }
    }
}

@Composable
private fun NavItem(
    selected: Boolean,
    onClick: () -> Unit,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
) {
    NavigationBarItem(
        selected = selected,
        onClick = onClick,
        icon = { Icon(icon, contentDescription = label) },
        label = { Text(label) },
        colors = NavigationBarItemDefaults.colors(
            selectedIconColor = Gold,
            selectedTextColor = Gold,
            indicatorColor = Panel,
            unselectedIconColor = Muted,
            unselectedTextColor = Muted,
        ),
    )
}

// region Scores

@Composable
private fun ScoresScreen(vm: AppViewModel, state: AppUiState) {
    Column(
        Modifier
            .fillMaxSize()
            .background(VoidBlack),
    ) {
        // Setup nudge
        if (state.playlist == null) {
            SetupBanner(
                title = "Add IPTV in Settings",
                body = "Scores work without a playlist. Add Xtream/M3U under Settings to watch streams.",
            )
        }

        // Live / Upcoming / Final
        LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                FilterChip(
                    selected = state.scoresFilter == ScoresFilter.LIVE,
                    onClick = { vm.setScoresFilter(ScoresFilter.LIVE) },
                    label = { Text("Live") },
                    colors = chipColors(),
                )
            }
            item {
                FilterChip(
                    selected = state.scoresFilter == ScoresFilter.UPCOMING,
                    onClick = { vm.setScoresFilter(ScoresFilter.UPCOMING) },
                    label = { Text("Upcoming") },
                    colors = chipColors(),
                )
            }
            item {
                FilterChip(
                    selected = state.scoresFilter == ScoresFilter.FINAL,
                    onClick = { vm.setScoresFilter(ScoresFilter.FINAL) },
                    label = { Text("Final") },
                    colors = chipColors(),
                )
            }
        }

        state.scoresStatus?.let {
            Text(it, color = Muted, modifier = Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.bodySmall)
        }
        state.scoresError?.let {
            Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp))
        }

        if (state.isLoadingScores && state.games.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Gold)
            }
            return
        }

        val byLeague = vm.gamesByLeague()
        if (byLeague.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Sports, null, tint = Muted, modifier = Modifier.size(40.dp))
                    Spacer(Modifier.height(8.dp))
                    Text(
                        when (state.scoresFilter) {
                            ScoresFilter.LIVE -> "No live games right now"
                            ScoresFilter.UPCOMING -> "Nothing upcoming for selected leagues"
                            ScoresFilter.FINAL -> "No finals in current boards"
                        },
                        color = Muted,
                    )
                }
            }
            return
        }

        LazyColumn(
            contentPadding = PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            byLeague.forEach { (league, games) ->
                item(key = "hdr-${league.id}") {
                    Text(
                        league.label.uppercase(),
                        color = Muted,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(vertical = 4.dp),
                    )
                }
                items(games, key = { it.id }) { game ->
                    GameRow(game)
                }
            }
        }
    }
}

@Composable
private fun GameRow(game: Game) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Panel)
            .padding(14.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TeamCell(game.away, Modifier.weight(1f), alignEnd = false)
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(horizontal = 8.dp),
            ) {
                Text(
                    game.statusLine,
                    color = if (game.isLive) LiveMint else Muted,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (game.isLive || game.isFinal) {
                    Text(
                        "${game.away.displayScore}  –  ${game.home.displayScore}",
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 22.sp,
                    )
                }
            }
            TeamCell(game.home, Modifier.weight(1f), alignEnd = true)
        }
        if (game.broadcasts.isNotEmpty()) {
            Text(
                game.broadcasts.take(3).joinToString(" · "),
                color = Muted,
                fontSize = 11.sp,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun TeamCell(
    team: com.samirpatel.sportsdash.core.sports.TeamInfo,
    modifier: Modifier,
    alignEnd: Boolean,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (alignEnd) Arrangement.End else Arrangement.Start,
    ) {
        if (!alignEnd) {
            TeamLogo(team.logoUrl, team.abbreviation)
            Spacer(Modifier.width(8.dp))
        }
        Column(horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start) {
            Text(
                team.rowLabel,
                color = TextPrimary,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(team.abbreviation, color = Muted, fontSize = 11.sp)
        }
        if (alignEnd) {
            Spacer(Modifier.width(8.dp))
            TeamLogo(team.logoUrl, team.abbreviation)
        }
    }
}

@Composable
private fun TeamLogo(url: String?, abbrev: String) {
    if (!url.isNullOrBlank()) {
        AsyncImage(
            model = url,
            contentDescription = abbrev,
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(8.dp)),
            contentScale = ContentScale.Fit,
        )
    } else {
        Box(
            Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(VoidBlack),
            contentAlignment = Alignment.Center,
        ) {
            Text(abbrev.take(3), color = Gold, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        }
    }
}

// endregion

// region Guide

@Composable
private fun GuideScreen(vm: AppViewModel, state: AppUiState) {
    Column(
        Modifier
            .fillMaxSize()
            .background(VoidBlack),
    ) {
        when {
            state.playlist == null -> {
                EmptyGuideHint()
            }
            state.isLoadingChannels && state.channels.isEmpty() -> {
                state.channelStatus?.let {
                    Text(it, color = Muted, modifier = Modifier.padding(16.dp))
                }
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Gold)
                }
            }
            else -> {
                OutlinedTextField(
                    value = state.searchQuery,
                    onValueChange = vm::setSearchQuery,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    placeholder = { Text("Search channels", color = Muted) },
                    leadingIcon = { Icon(Icons.Default.Search, null, tint = Muted) },
                    singleLine = true,
                    colors = fieldColors(),
                )
                if (state.groups.size > 1) {
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(state.groups) { g ->
                            FilterChip(
                                selected = state.selectedGroup == g,
                                onClick = { vm.selectGroup(g) },
                                label = {
                                    Text(
                                        g,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                },
                                colors = chipColors(),
                            )
                        }
                    }
                }
                state.channelStatus?.let {
                    Text(
                        it,
                        color = Muted,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                }
                state.channelError?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp))
                }
                val channels = vm.filteredChannels()
                LazyColumn(
                    contentPadding = PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(channels, key = { it.id }) { ch ->
                        ChannelRow(ch) { vm.play(ch) }
                    }
                }
            }
        }
    }
}

@Composable
private fun ChannelRow(channel: IptvChannel, onPlay: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Panel)
            .clickable(onClick = onPlay)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (!channel.logo.isNullOrBlank()) {
            AsyncImage(
                model = channel.logo,
                contentDescription = null,
                modifier = Modifier
                    .size(36.dp)
                    .clip(RoundedCornerShape(8.dp)),
                contentScale = ContentScale.Fit,
            )
            Spacer(Modifier.width(10.dp))
        } else {
            Icon(Icons.Default.PlayArrow, null, tint = Gold, modifier = Modifier.size(28.dp))
            Spacer(Modifier.width(10.dp))
        }
        Column(Modifier = Modifier.weight(1f)) {
            Text(channel.name, color = TextPrimary, fontWeight = FontWeight.SemiBold, maxLines = 2)
            channel.group?.let {
                Text(it, color = Muted, style = MaterialTheme.typography.bodySmall, maxLines = 1)
            }
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
            "Add an Xtream server URL + credentials (or M3U URL) in Settings to browse live channels.",
            color = Muted,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(16.dp))
        Text("→ Settings tab", color = Gold, fontWeight = FontWeight.Bold)
    }
}

// endregion

// region Settings

@Composable
private fun SettingsScreen(vm: AppViewModel, state: AppUiState) {
    var mode by remember { mutableIntStateOf(0) }
    var name by remember { mutableStateOf(state.playlist?.name ?: "My IPTV") }
    var serverUrl by remember { mutableStateOf(state.playlist?.host ?: "") }
    var user by remember { mutableStateOf(state.playlist?.username ?: "") }
    var pass by remember { mutableStateOf("") }
    var m3u by remember { mutableStateOf(state.playlist?.m3uUrl ?: "") }

    LazyColumn(
        Modifier
            .fillMaxSize()
            .background(VoidBlack)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text("Playlist", color = Gold, style = MaterialTheme.typography.titleMedium)
            Text(
                "Paste your Xtream server URL (https://host:port) or full player_api link. " +
                    "libVLC hard engine — same family as iOS.",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = mode == 0,
                    onClick = { mode = 0 },
                    label = { Text("Xtream") },
                    colors = chipColors(),
                )
                FilterChip(
                    selected = mode == 1,
                    onClick = { mode = 1 },
                    label = { Text("M3U URL") },
                    colors = chipColors(),
                )
            }
        }
        item {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name") },
                modifier = Modifier.fillMaxWidth(),
                colors = fieldColors(),
                singleLine = true,
            )
        }
        if (mode == 0) {
            item {
                OutlinedTextField(
                    value = serverUrl,
                    onValueChange = { serverUrl = it },
                    label = { Text("Xtream server URL") },
                    placeholder = { Text("https://your-provider.example") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors(),
                    singleLine = true,
                )
            }
            item {
                OutlinedTextField(
                    value = user,
                    onValueChange = { user = it },
                    label = { Text("Username") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors(),
                    singleLine = true,
                )
            }
            item {
                OutlinedTextField(
                    value = pass,
                    onValueChange = { pass = it },
                    label = { Text("Password") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors(),
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
            }
            item {
                Button(
                    onClick = { vm.saveXtream(name, serverUrl, user, pass) },
                    colors = ButtonDefaults.buttonColors(containerColor = Gold, contentColor = VoidBlack),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Save & load live channels") }
            }
        } else {
            item {
                OutlinedTextField(
                    value = m3u,
                    onValueChange = { m3u = it },
                    label = { Text("M3U URL") },
                    placeholder = { Text("https://…/get.php?…") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors(),
                    singleLine = true,
                )
            }
            item {
                Button(
                    onClick = { vm.saveM3u(name, m3u) },
                    colors = ButtonDefaults.buttonColors(containerColor = Gold, contentColor = VoidBlack),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Save & load M3U") }
            }
        }
        item {
            state.playlist?.let {
                Text("Active: ${it.name} · ${it.type}", color = TextPrimary)
            }
            state.channelStatus?.let { Text(it, color = Muted) }
            state.channelError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }

        item {
            Spacer(Modifier.height(12.dp))
            Text("Score leagues", color = Gold, style = MaterialTheme.typography.titleMedium)
            Text("Toggle leagues for the Scores dashboard (ESPN).", color = Muted, style = MaterialTheme.typography.bodySmall)
        }
        items(SportLeague.ALL) { league ->
            val on = league.id in state.selectedLeagueIds
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (on) Gold.copy(alpha = 0.15f) else Panel)
                    .clickable { vm.toggleLeague(league.id) }
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(league.label, color = TextPrimary, modifier = Modifier.weight(1f))
                Text(if (on) "ON" else "OFF", color = if (on) Gold else Muted, fontWeight = FontWeight.Bold)
            }
        }

        item {
            Spacer(Modifier.height(16.dp))
            Text("About", color = Gold, style = MaterialTheme.typography.titleMedium)
            Text(
                "SportsDash Android — Scores (ESPN) + IPTV Guide (libVLC / LGPL). " +
                    "Matches iOS product: Scores · Guide · Settings. https://www.videolan.org/",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

// endregion

@Composable
private fun SetupBanner(title: String, body: String) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(12.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Gold.copy(alpha = 0.12f))
            .padding(12.dp),
    ) {
        Text(title, color = Gold, fontWeight = FontWeight.Bold)
        Text(body, color = Muted, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun PlayerScreen(
    channel: IptvChannel,
    url: String,
    engineLabel: String,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val controller = remember { VlcPlayerController(context) }

    DisposableEffect(url) {
        controller.play(url)
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
            .background(Color.Black),
    ) {
        AndroidView(
            factory = { ctx ->
                createVlcVideoLayout(ctx).also { layout -> controller.attach(layout) }
            },
            modifier = Modifier.fillMaxSize(),
            update = { layout -> controller.attach(layout) },
        )
        Row(
            Modifier
                .fillMaxWidth()
                .align(Alignment.TopCenter)
                .background(Color.Black.copy(alpha = 0.55f))
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onClose) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
            }
            Column(Modifier = Modifier.weight(1f)) {
                Text(channel.name, color = Color.White, fontWeight = FontWeight.Bold, maxLines = 1)
                Text(engineLabel, color = Gold, style = MaterialTheme.typography.labelSmall)
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
private fun fieldColors() = OutlinedTextFieldDefaults.colors(
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
