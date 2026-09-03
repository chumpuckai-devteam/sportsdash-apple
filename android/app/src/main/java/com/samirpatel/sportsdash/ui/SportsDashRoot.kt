package com.samirpatel.sportsdash.ui

import android.content.res.Configuration
import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusGroup
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.onPreviewKeyEvent
import com.samirpatel.sportsdash.ui.tv.tvFocusRing
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.samirpatel.sportsdash.AppUiState
import com.samirpatel.sportsdash.AppViewModel
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.JumbotronSideNav
import com.samirpatel.sportsdash.ui.theme.JumbotronTabBar
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack
import com.samirpatel.sportsdash.ui.theme.gridDotGround

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SportsDashRoot(
    vm: AppViewModel,
    isTelevision: Boolean = false,
) {
    val state by vm.state.collectAsState()
    var tab by remember { mutableIntStateOf(0) }

    val playing = state.playing
    val playUrl = state.playUrl
    // Fullscreen only when not floating mini-player
    if (playing != null && playUrl != null && !state.floating) {
        Box(modifier = Modifier.fillMaxSize()) {
            PlayerScreen(
                channel = playing,
                url = playUrl,
                engineLabel = state.engineLabel,
                liveGames = vm.liveGamesForTicker(),
                currentGameId = state.playingGameId,
                tickerMode = state.scoresTickerMode,
                isTelevision = isTelevision,
                nowTitle = vm.nowTitle(playing.id),
                nextTitle = vm.nextTitle(playing.id),
                onClose = { vm.stopPlayback() },
                onPopOut = if (isTelevision) { {} } else { { vm.popOutPlayer() } },
                onTickerGame = { game -> vm.playFromTicker(game) },
                onReplay = {
                    vm.play(playing, gameId = state.playingGameId)
                },
                onToggleScoresTicker = { vm.toggleScoresTicker() },
                displayName = vm.displayChannelName(playing.name),
                favoriteTeamIds = state.favoriteTeamIds,
                onPlayerAppear = { vm.playerDidAppear() },
                onPlayerDisappear = { vm.playerDidDisappear() },
            )
            // Stream picker over fullscreen player (ticker game switch)
            val pickerGame = state.streamPickerGame
            if (pickerGame != null) {
                StreamPickerDialog(
                    game = pickerGame,
                    matches = state.streamMatches,
                    hasPlaylist = state.playlist != null,
                    onClose = { vm.dismissStreamPicker() },
                    onPlay = { match -> vm.playMatch(match, pickerGame) },
                )
            }
        }
        return
    }

    val landscape =
        LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    // Android TV is always "leanback landscape" — keep shell chrome for D-pad nav.
    val hideShellChrome = landscape && !isTelevision

    if (isTelevision) {
        TelevisionShell(
            vm = vm,
            state = state,
            tab = tab,
            onTab = { tab = it },
            landscape = true,
        )
        return
    }

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
        topBar = {},
        bottomBar = {
            if (!hideShellChrome) {
                JumbotronTabBar(
                    selected = tab,
                    onSelect = { tab = it },
                    tv = isTelevision,
                )
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .then(if (hideShellChrome || !isTelevision) Modifier.statusBarsPadding() else Modifier)
                .fillMaxSize(),
        ) {
            if (hideShellChrome) {
                LandscapeTabStrip(tab = tab, onSelect = { tab = it })
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .then(
                        if (isTelevision) {
                            Modifier.gridDotGround(
                                step = com.samirpatel.sportsdash.ui.theme.TvGridStep,
                                dot = com.samirpatel.sportsdash.ui.theme.TvGridDot,
                            )
                        } else {
                            Modifier.gridDotGround()
                        },
                    ),
            ) {
                when (tab) {
                    0 -> ScoresScreen(
                        vm = vm,
                        state = state,
                        landscape = landscape || isTelevision,
                        isTelevision = isTelevision,
                        onGoSettings = { tab = 2 },
                    )
                    1 -> GuideScreen(
                        vm = vm,
                        state = state,
                        landscape = landscape || isTelevision,
                        isTelevision = isTelevision,
                        onGoSettings = { tab = 2 },
                        onGoScores = { tab = 0 },
                    )
                    else -> SettingsScreen(vm = vm, state = state, isTelevision = isTelevision)
                }

                // Floating mini-player over tabs (iOS pop-out parity)
                if (state.floating && playing != null && playUrl != null && !isTelevision) {
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
}

@Composable
private fun TelevisionShell(
    vm: AppViewModel,
    state: AppUiState,
    tab: Int,
    onTab: (Int) -> Unit,
    landscape: Boolean,
) {
    val railRequester = remember { FocusRequester() }
    var railFocused by remember { mutableStateOf(false) }
    BackHandler(enabled = !railFocused) {
        railRequester.requestFocus()
    }
    Row(
        modifier = Modifier
            .fillMaxSize()
            .gridDotGround(
                step = com.samirpatel.sportsdash.ui.theme.TvGridStep,
                dot = com.samirpatel.sportsdash.ui.theme.TvGridDot,
            )
            .onPreviewKeyEvent { ev ->
                val n = ev.nativeKeyEvent
                if (n.action == KeyEvent.ACTION_DOWN && n.repeatCount >= 8) {
                    val code = n.keyCode
                    if (code == KeyEvent.KEYCODE_BACK || code == KeyEvent.KEYCODE_DPAD_LEFT) {
                        railRequester.requestFocus()
                        true
                    } else {
                        false
                    }
                } else {
                    false
                }
            },
    ) {
        JumbotronSideNav(
            selected = tab,
            onSelect = onTab,
            modifier = Modifier
                .focusRequester(railRequester)
                .focusGroup()
                .focusable()
                .onFocusChanged { railFocused = it.hasFocus }
        )
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxSize(),
        ) {
            when (tab) {
                0 -> ScoresScreen(
                    vm = vm,
                    state = state,
                    landscape = landscape,
                    isTelevision = true,
                    onGoSettings = { onTab(2) },
                )
                1 -> GuideScreen(
                    vm = vm,
                    state = state,
                    landscape = landscape,
                    isTelevision = true,
                    onGoSettings = { onTab(2) },
                    onGoScores = { onTab(0) },
                )
                else -> SettingsScreen(vm = vm, state = state, isTelevision = true)
            }
        }
    }
}

@Composable
private fun LandscapeTabStrip(tab: Int, onSelect: (Int) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Panel)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        listOf(
            0 to "Scores",
            1 to "Guide",
            2 to "Settings",
        ).forEach { (idx, label) ->
            val selected = tab == idx
            Text(
                text = label,
                color = if (selected) VoidBlack else TextPrimary,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (selected) Gold else Color.Transparent)
                    .clickable { onSelect(idx) }
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            )
        }
    }
}
