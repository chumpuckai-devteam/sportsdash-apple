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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Sports
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import com.samirpatel.sportsdash.AppUiState
import com.samirpatel.sportsdash.AppViewModel
import com.samirpatel.sportsdash.ScoresFilter
import com.samirpatel.sportsdash.core.matching.ChannelMatch
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.core.sports.TeamInfo
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack

private sealed class ScoreRow {
    data class Header(val title: String, val id: String) : ScoreRow()
    data class GameItem(val game: Game) : ScoreRow()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScoresScreen(
    vm: AppViewModel,
    state: AppUiState,
    landscape: Boolean = false,
    openMenu: Boolean = false,
    onMenuConsumed: () -> Unit = {},
    onOpenMenu: () -> Unit = {},
    onGoSettings: () -> Unit = {},
) {
    var showMenu by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    LaunchedEffect(openMenu) {
        if (openMenu) {
            showMenu = true
            onMenuConsumed()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(VoidBlack),
        ) {
            // Compact action row — no fat banner + sticky filter strip eating landscape
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                ScoreFilterChip(
                    label = "Live",
                    selected = state.scoresFilter == ScoresFilter.LIVE,
                    onClick = { vm.setScoresFilter(ScoresFilter.LIVE) },
                )
                ScoreFilterChip(
                    label = "Up",
                    selected = state.scoresFilter == ScoresFilter.UPCOMING,
                    onClick = { vm.setScoresFilter(ScoresFilter.UPCOMING) },
                )
                ScoreFilterChip(
                    label = "Final",
                    selected = state.scoresFilter == ScoresFilter.FINAL,
                    onClick = { vm.setScoresFilter(ScoresFilter.FINAL) },
                )
                Text(
                    text = state.scoresStatus ?: "Scores",
                    color = Muted,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = {
                    showMenu = true
                    onOpenMenu()
                }) {
                    Icon(Icons.Default.Menu, contentDescription = "Scores menu", tint = Gold)
                }
            }

            if (!landscape && state.playlist == null) {
                Text(
                    text = "Add IPTV in Settings to watch from scores.",
                    color = Muted,
                    fontSize = 12.sp,
                    modifier = Modifier
                        .padding(horizontal = 12.dp, vertical = 2.dp)
                        .clickable(onClick = onGoSettings),
                )
            }

            val scoresErr = state.scoresError
            if (scoresErr != null) {
                Text(
                    text = scoresErr,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                )
            }

            val byLeague = vm.gamesByLeague()
            when {
                state.isLoadingScores && state.games.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = Gold)
                    }
                }

                byLeague.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                imageVector = Icons.Default.Sports,
                                contentDescription = null,
                                tint = Muted,
                                modifier = Modifier.size(40.dp),
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = emptyFilterMessage(state.scoresFilter),
                                color = Muted,
                            )
                        }
                    }
                }

                else -> {
                    val rows = flattenScoreRows(byLeague)
                    LazyColumn(
                        contentPadding = PaddingValues(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(
                            items = rows,
                            key = { row ->
                                when (row) {
                                    is ScoreRow.Header -> "h-${row.id}"
                                    is ScoreRow.GameItem -> row.game.id
                                }
                            },
                        ) { row ->
                            when (row) {
                                is ScoreRow.Header -> {
                                    Text(
                                        text = row.title,
                                        color = Muted,
                                        fontWeight = FontWeight.SemiBold,
                                        fontSize = 12.sp,
                                        modifier = Modifier.padding(vertical = 4.dp),
                                    )
                                }

                                is ScoreRow.GameItem -> {
                                    GameRow(
                                        game = row.game,
                                        onClick = { vm.openStreamPicker(row.game) },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

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

        if (showMenu) {
            ModalBottomSheet(
                onDismissRequest = { showMenu = false },
                sheetState = sheetState,
                containerColor = Panel,
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .padding(bottom = 28.dp),
                ) {
                    Text("Scores", color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("Filter", color = Muted, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ScoreFilterChip("Live", state.scoresFilter == ScoresFilter.LIVE) {
                            vm.setScoresFilter(ScoresFilter.LIVE)
                        }
                        ScoreFilterChip("Upcoming", state.scoresFilter == ScoresFilter.UPCOMING) {
                            vm.setScoresFilter(ScoresFilter.UPCOMING)
                        }
                        ScoreFilterChip("Final", state.scoresFilter == ScoresFilter.FINAL) {
                            vm.setScoresFilter(ScoresFilter.FINAL)
                        }
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    TextButton(onClick = {
                        vm.refreshScores()
                        showMenu = false
                    }) { Text("Refresh scores", color = Gold) }
                    if (state.playlist == null) {
                        TextButton(onClick = {
                            showMenu = false
                            onGoSettings()
                        }) { Text("Add IPTV in Settings", color = Gold) }
                    }
                    TextButton(onClick = { showMenu = false }) {
                        Text("Done", color = Gold)
                    }
                }
            }
        }
    }
}

private fun emptyFilterMessage(filter: ScoresFilter): String = when (filter) {
    ScoresFilter.LIVE -> "No live games right now"
    ScoresFilter.UPCOMING -> "Nothing upcoming for selected leagues"
    ScoresFilter.FINAL -> "No finals in current boards"
}

private fun flattenScoreRows(
    byLeague: Map<com.samirpatel.sportsdash.core.sports.SportLeague, List<Game>>,
): List<ScoreRow> {
    val out = ArrayList<ScoreRow>()
    byLeague.forEach { (league, games) ->
        out.add(ScoreRow.Header(title = league.label.uppercase(), id = league.id))
        games.forEach { g -> out.add(ScoreRow.GameItem(g)) }
    }
    return out
}

@Composable
private fun StreamPickerDialog(
    game: Game,
    matches: List<ChannelMatch>,
    hasPlaylist: Boolean,
    onClose: () -> Unit,
    onPlay: (ChannelMatch) -> Unit,
) {
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.94f)
                .padding(16.dp),
            shape = RoundedCornerShape(16.dp),
            color = Panel,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Watch stream",
                            color = Gold,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            text = "${game.matchupLabel} · ${game.league.label}",
                            color = TextPrimary,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = game.statusLine,
                            color = if (game.isLive) LiveMint else Muted,
                            fontSize = 12.sp,
                        )
                    }
                    IconButton(onClick = onClose) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Close",
                            tint = Muted,
                        )
                    }
                }
                Spacer(modifier = Modifier.height(12.dp))
                when {
                    !hasPlaylist -> {
                        Text(
                            text = "Add Xtream or M3U under Settings, then tap this game again.",
                            color = Muted,
                        )
                    }

                    matches.isEmpty() -> {
                        Text(
                            text = "No strong IPTV matches. Open Guide and pick a sports channel manually.",
                            color = Muted,
                        )
                    }

                    else -> {
                        Text(
                            text = "${matches.size} matched channels — tap to play",
                            color = Muted,
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        matches.forEach { match ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(VoidBlack)
                                    .clickable { onPlay(match) }
                                    .padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(
                                    imageVector = Icons.Default.PlayArrow,
                                    contentDescription = null,
                                    tint = Gold,
                                )
                                Spacer(modifier = Modifier.width(10.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = match.channel.name,
                                        color = TextPrimary,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    Text(
                                        text = "${match.reason} · score ${match.score.toInt()}",
                                        color = Muted,
                                        fontSize = 11.sp,
                                        maxLines = 2,
                                    )
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
private fun ScoreFilterChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(text = label) },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = Gold,
            selectedLabelColor = VoidBlack,
            containerColor = Panel,
            labelColor = TextPrimary,
        ),
    )
}

@Composable
private fun GameRow(game: Game, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Panel)
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TeamCell(
                team = game.away,
                modifier = Modifier.weight(1f),
                alignEnd = false,
            )
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(horizontal = 8.dp),
            ) {
                Text(
                    text = game.statusLine,
                    color = if (game.isLive) LiveMint else Muted,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (game.isLive || game.isFinal) {
                    Text(
                        text = "${game.away.displayScore}  -  ${game.home.displayScore}",
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 22.sp,
                    )
                } else {
                    Text(
                        text = "TAP TO WATCH",
                        color = Gold,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
            TeamCell(
                team = game.home,
                modifier = Modifier.weight(1f),
                alignEnd = true,
            )
        }
        if (game.broadcasts.isNotEmpty()) {
            Text(
                text = game.broadcasts.take(3).joinToString(" · "),
                color = Muted,
                fontSize = 11.sp,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun TeamCell(
    team: TeamInfo,
    modifier: Modifier,
    alignEnd: Boolean,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (alignEnd) Arrangement.End else Arrangement.Start,
    ) {
        if (!alignEnd) {
            TeamLogo(url = team.logoUrl, abbrev = team.abbreviation)
            Spacer(modifier = Modifier.width(8.dp))
        }
        Column(
            horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start,
        ) {
            Text(
                text = team.rowLabel,
                color = TextPrimary,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = team.abbreviation,
                color = Muted,
                fontSize = 11.sp,
            )
        }
        if (alignEnd) {
            Spacer(modifier = Modifier.width(8.dp))
            TeamLogo(url = team.logoUrl, abbrev = team.abbreviation)
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
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(VoidBlack),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = abbrev.take(3),
                color = Gold,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
fun SetupBanner(title: String, body: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(12.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Gold.copy(alpha = 0.12f))
            .padding(12.dp),
    ) {
        Text(text = title, color = Gold, fontWeight = FontWeight.Bold)
        Text(text = body, color = Muted, style = MaterialTheme.typography.bodySmall)
    }
}
