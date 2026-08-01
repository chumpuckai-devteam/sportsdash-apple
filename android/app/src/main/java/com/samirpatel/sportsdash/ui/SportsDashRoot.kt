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
import androidx.compose.material.icons.filled.Settings
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.samirpatel.sportsdash.AppUiState
import com.samirpatel.sportsdash.AppViewModel
import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.player.VlcPlayerController
import com.samirpatel.sportsdash.core.player.createVlcVideoLayout
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SportsDashRoot(vm: AppViewModel) {
    val state by vm.state.collectAsState()
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
                    Text(
                        "SportsDash",
                        fontWeight = FontWeight.Bold,
                        color = Gold,
                    )
                },
                actions = {
                    if (tab == 0) {
                        IconButton(onClick = { vm.refreshChannels() }) {
                            Icon(Icons.Default.Refresh, contentDescription = "Refresh", tint = Gold)
                        }
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
                NavigationBarItem(
                    selected = tab == 0,
                    onClick = { tab = 0 },
                    icon = { Icon(Icons.Default.LiveTv, contentDescription = null) },
                    label = { Text("Channels") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Gold,
                        selectedTextColor = Gold,
                        indicatorColor = Panel,
                        unselectedIconColor = Muted,
                        unselectedTextColor = Muted,
                    ),
                )
                NavigationBarItem(
                    selected = tab == 1,
                    onClick = { tab = 1 },
                    icon = { Icon(Icons.Default.Settings, contentDescription = null) },
                    label = { Text("Settings") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Gold,
                        selectedTextColor = Gold,
                        indicatorColor = Panel,
                        unselectedIconColor = Muted,
                        unselectedTextColor = Muted,
                    ),
                )
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
        ) {
            when (tab) {
                0 -> ChannelsScreen(vm = vm, state = state)
                else -> SettingsScreen(vm = vm, state = state)
            }
        }
    }
}

@Composable
private fun ChannelsScreen(vm: AppViewModel, state: AppUiState) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(VoidBlack),
    ) {
        when {
            state.playlist == null -> {
                EmptyPlaylistHint()
            }
            state.isLoading && state.channels.isEmpty() -> {
                state.status?.let {
                    Text(
                        it,
                        color = Muted,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
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
                if (state.groups.size > 1) {
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(state.groups) { g ->
                            FilterChip(
                                selected = state.selectedGroup == g,
                                onClick = { vm.selectGroup(g) },
                                label = { Text(g) },
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
                state.status?.let {
                    Text(
                        it,
                        color = Muted,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                }
                state.error?.let {
                    Text(
                        it,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(16.dp),
                    )
                }
                val channels = vm.filteredChannels()
                LazyColumn(
                    contentPadding = PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(channels, key = { it.id }) { ch ->
                        ChannelRow(channel = ch, onPlay = { vm.play(ch) })
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
        Icon(
            Icons.Default.PlayArrow,
            contentDescription = null,
            tint = Gold,
            modifier = Modifier.size(28.dp),
        )
        Column(
            modifier = Modifier
                .padding(start = 12.dp)
                .weight(1f),
        ) {
            Text(channel.name, color = TextPrimary, fontWeight = FontWeight.SemiBold)
            channel.group?.let {
                Text(it, color = Muted, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun EmptyPlaylistHint() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "No playlist yet",
            color = TextPrimary,
            style = MaterialTheme.typography.titleLarge,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Open Settings and add your Xtream host + credentials (or an M3U URL). Same panels as iOS SportsDash.",
            color = Muted,
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text("→ Settings tab", color = Gold, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun SettingsScreen(vm: AppViewModel, state: AppUiState) {
    var mode by remember { mutableIntStateOf(0) } // 0 xtream, 1 m3u
    var name by remember { mutableStateOf(state.playlist?.name ?: "My IPTV") }
    var host by remember { mutableStateOf(state.playlist?.host ?: "") }
    var user by remember { mutableStateOf(state.playlist?.username ?: "") }
    var pass by remember { mutableStateOf("") }
    var m3u by remember { mutableStateOf(state.playlist?.m3uUrl ?: "") }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedBorderColor = Gold,
        unfocusedBorderColor = Muted,
        focusedLabelColor = Gold,
        unfocusedLabelColor = Muted,
        cursorColor = Gold,
        focusedTextColor = TextPrimary,
        unfocusedTextColor = TextPrimary,
    )

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(VoidBlack)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text("Playlist", color = Gold, style = MaterialTheme.typography.titleMedium)
            Text(
                "libVLC hard engine (LGPL) — same family as iOS MobileVLCKit. TS live preferred.",
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
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = Gold,
                        selectedLabelColor = VoidBlack,
                    ),
                )
                FilterChip(
                    selected = mode == 1,
                    onClick = { mode = 1 },
                    label = { Text("M3U URL") },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = Gold,
                        selectedLabelColor = VoidBlack,
                    ),
                )
            }
        }
        item {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name") },
                modifier = Modifier.fillMaxWidth(),
                colors = fieldColors,
                singleLine = true,
            )
        }
        if (mode == 0) {
            item {
                OutlinedTextField(
                    value = host,
                    onValueChange = { host = it },
                    label = { Text("Host (e.g. 305.halfvex.com)") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors,
                    singleLine = true,
                )
            }
            item {
                OutlinedTextField(
                    value = user,
                    onValueChange = { user = it },
                    label = { Text("Username") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors,
                    singleLine = true,
                )
            }
            item {
                OutlinedTextField(
                    value = pass,
                    onValueChange = { pass = it },
                    label = { Text("Password") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors,
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
            }
            item {
                Button(
                    onClick = { vm.saveXtream(name, host, user, pass) },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Gold,
                        contentColor = VoidBlack,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Save & load live channels")
                }
            }
        } else {
            item {
                OutlinedTextField(
                    value = m3u,
                    onValueChange = { m3u = it },
                    label = { Text("M3U URL") },
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors,
                    singleLine = true,
                )
            }
            item {
                Button(
                    onClick = { vm.saveM3u(name, m3u) },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Gold,
                        contentColor = VoidBlack,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Save & load M3U")
                }
            }
        }
        item {
            state.playlist?.let {
                Text("Active: ${it.name} · ${it.type}", color = TextPrimary)
            }
            state.status?.let { Text(it, color = Muted) }
            state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
        item {
            Spacer(modifier = Modifier.height(24.dp))
            Text("About", color = Gold, style = MaterialTheme.typography.titleMedium)
            Text(
                "SportsDash Android v1 dogfood. Playback uses libVLC (© VideoLAN, LGPLv2.1+). " +
                    "iOS/tvOS share the same engine family. https://www.videolan.org/",
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
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
                createVlcVideoLayout(ctx).also { layout ->
                    controller.attach(layout)
                }
            },
            modifier = Modifier.fillMaxSize(),
            update = { layout -> controller.attach(layout) },
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.TopCenter)
                .background(Color.Black.copy(alpha = 0.55f))
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onClose) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(channel.name, color = Color.White, fontWeight = FontWeight.Bold)
                Text(engineLabel, color = Gold, style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}
