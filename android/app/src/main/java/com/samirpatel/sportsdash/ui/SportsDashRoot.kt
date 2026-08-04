package com.samirpatel.sportsdash.ui

import android.content.res.Configuration
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Sports
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import com.samirpatel.sportsdash.AppViewModel
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.VoidBlack

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SportsDashRoot(vm: AppViewModel) {
    val state by vm.state.collectAsState()
    var tab by remember { mutableIntStateOf(0) }

    val playing = state.playing
    val playUrl = state.playUrl
    // Fullscreen only when not floating mini-player
    if (playing != null && playUrl != null && !state.floating) {
        PlayerScreen(
            channel = playing,
            url = playUrl,
            engineLabel = state.engineLabel,
            liveGames = vm.liveGames(),
            currentGameId = state.playingGameId,
            showScoresTicker = state.showScoresTicker,
            nowTitle = vm.nowTitle(playing.id),
            nextTitle = vm.nextTitle(playing.id),
            onClose = { vm.stopPlayback() },
            onPopOut = { vm.popOutPlayer() },
            onTickerGame = { game -> vm.playFromTicker(game) },
            onReplay = {
                vm.play(playing, gameId = state.playingGameId)
            },
            onToggleScoresTicker = { vm.toggleScoresTicker() },
            displayName = vm.displayChannelName(playing.name),
            favoriteTeamIds = state.favoriteTeamIds,
        )
        return
    }

    val landscape =
        LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE

    val navColors = NavigationBarItemDefaults.colors(
        selectedIconColor = Gold,
        selectedTextColor = Gold,
        indicatorColor = Panel,
        unselectedIconColor = Muted,
        unselectedTextColor = Muted,
    )

    // Zero default insets — avoids a thin unused top/bottom strip when bars are hidden
    // in landscape (the "little line" users saw above content).
    Scaffold(
        containerColor = VoidBlack,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            if (!landscape) {
                TopAppBar(
                    title = {
                        Text("SportsDash", fontWeight = FontWeight.Bold, color = Gold)
                    },
                    actions = {
                        IconButton(
                            onClick = {
                                when (tab) {
                                    0 -> vm.refreshScores()
                                    1 -> {
                                        vm.refreshChannels()
                                        vm.reloadEpg(force = true)
                                    }
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
                    windowInsets = WindowInsets.safeDrawing,
                )
            }
        },
        bottomBar = {
            if (!landscape) {
                NavigationBar(
                    containerColor = Panel,
                    windowInsets = WindowInsets.safeDrawing,
                ) {
                    NavigationBarItem(
                        selected = tab == 0,
                        onClick = { tab = 0 },
                        icon = { Icon(Icons.Default.Sports, contentDescription = "Scores") },
                        label = { Text("Scores") },
                        colors = navColors,
                    )
                    NavigationBarItem(
                        selected = tab == 1,
                        onClick = { tab = 1 },
                        icon = { Icon(Icons.Default.LiveTv, contentDescription = "Guide") },
                        label = { Text("Guide") },
                        colors = navColors,
                    )
                    NavigationBarItem(
                        selected = tab == 2,
                        onClick = { tab = 2 },
                        icon = { Icon(Icons.Default.Settings, contentDescription = "Settings") },
                        label = { Text("Settings") },
                        colors = navColors,
                    )
                }
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .then(if (landscape) Modifier.statusBarsPadding() else Modifier)
                .fillMaxSize(),
        ) {
            when (tab) {
                0 -> ScoresScreen(
                    vm = vm,
                    state = state,
                    landscape = landscape,
                    onGoSettings = { tab = 2 },
                )
                1 -> GuideScreen(
                    vm = vm,
                    state = state,
                    landscape = landscape,
                    onGoSettings = { tab = 2 },
                    onGoScores = { tab = 0 },
                )
                else -> SettingsScreen(vm = vm, state = state)
            }

            // Floating mini-player over tabs (iOS pop-out parity)
            if (state.floating && playing != null && playUrl != null) {
                FloatingPlayerBar(
                    channel = playing,
                    url = playUrl,
                    title = vm.displayChannelName(playing.name),
                    onExpand = { vm.expandFloatingPlayer() },
                    onDismiss = { vm.dismissFloatingPlayer() },
                    modifier = Modifier.align(Alignment.BottomCenter),
                )
            }
        }
    }
}
