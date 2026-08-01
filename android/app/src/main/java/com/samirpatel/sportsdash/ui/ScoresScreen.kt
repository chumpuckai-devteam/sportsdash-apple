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
import androidx.compose.foundation.lazy.items as listItems
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScoresScreen(vm: AppViewModel, state: AppUiState) {
    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(VoidBlack),
        ) {
            if (state.playlist == null) {
                SetupBanner(
                    title = "Add IPTV in Settings",
                    body = "Tap a game to pick a matching channel once your playlist is loaded.",
                )
            } else {
                SetupBanner(
                    title = "Watch from Scores",
                    body = "Tap any game → choose a matched IPTV channel → plays in VLC.",
                )
            }

            LazyRow(
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item {
                    ScoreFilterChip("Live", state.scoresFilter == ScoresFilter.LIVE) {
                        vm.setScoresFilter(ScoresFilter.LIVE)
                    }
                }
                item {
                    ScoreFilterChip("Upcoming", state.scoresFilter == ScoresFilter.UPCOMING) {
                        vm.setScoresFilter(ScoresFilter.UPCOMING)
                    }
                }
                item {
                    ScoreFilterChip("Final", state.scoresFilter == ScoresFilter.FINAL) {
                        vm.setScoresFilter(ScoresFilter.FINAL)
                    }
                }
            }

            state.scoresStatus?.let { status ->
                Text(
                    text = status,
                    color = Muted,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
            state.scoresError?.let { err ->
                Text(
                    text = err,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp),
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
                }
                else -> {
                    LazyColumn(
                        contentPadding = PaddingValues(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        byLeague.forEach { (league, games) ->
                            item(key = "hdr-${league.id}") {
                                Text(
                                    text = league.label.uppercase(),
                                    color = Muted,
                                    fontWeight = FontWeight.SemiBold,
                                    fontSize = 12.sp,
                                    modifier = Modifier.padding(vertical = 4.dp),
                                )
                            }
                            listItems(items = games, key = { it.id }) { game ->
                                GameRow(game = game, onClick = { vm.openStreamPicker(game) })
                            }
                        }
                    }
                }
            }
        }

        // Stream picker sheet
        val pickerGame = state.streamPickerGame
        if (pickerGame != null) {
            ModalBottomSheet(
                onDismissRequest = { vm.dismissStreamPicker() },
                sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
                containerColor = Panel,
            ) {
                StreamPickerContent(
                    game = pickerGame,
                    matches = state.streamMatches,
                    hasPlaylist = state.playlist != null,
                    onClose = { vm.dismissStreamPicker() },
                    onPlay = { match -> vm.playMatch(match, pickerGame) },
                )
            }
        }
    }
}

@Composable
private fun StreamPickerContent(
    game: Game,
    matches: List<ChannelMatch>,
    hasPlaylist: Boolean,
    onClose: () -> Unit,
    onPlay: (ChannelMatch) -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(bottom = 32.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier = Modifier.weight(1f)) {
                Text("Watch stream", color = Gold, fontWeight = FontWeight.Bold)
                Text(
                    game.matchupLabel + " · " + game.league.label,
                    color = TextPrimary,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(game.statusLine, color = if (game.isLive) LiveMint else Muted, fontSize = 12.sp)
            }
            IconButton(onClick = onClose) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = Muted)
            }
        }
        Spacer(Modifier.height(12.dp))
        when {
            !hasPlaylist -> {
                Text(
                    "Add Xtream or M3U under Settings, then come back and tap this game.",
                    color = Muted,
                )
            }
            matches.isEmpty() -> {
                Text(
                    "No strong IPTV matches for this game. Open Guide and pick a sports channel manually.",
                    color = Muted,
                )
            }
            else -> {
                Text(
                    "${matches.size} matched channels — tap to play",
                    color = Muted,
                    style = MaterialTheme.typography.bodySmall,
                )
                Spacer(Modifier.height(8.dp))
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
                        Icon(Icons.Default.PlayArrow, null, tint = Gold)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier = Modifier.weight(1f)) {
                            Text(match.channel.name, color = TextPrimary, fontWeight = FontWeight.SemiBold)
                            Text(
                                "${match.reason} · score ${match.score.toInt()}",
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

@Composable
private fun ScoreFilterChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label) },
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
            TeamCell(game.away, Modifier.weight(1f), alignEnd = false)
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
                        text = "${game.away.displayScore}  –  ${game.home.displayScore}",
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 22.sp,
                    )
                } else {
                    Text("TAP TO WATCH", color = Gold, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
            }
            TeamCell(game.home, Modifier.weight(1f), alignEnd = true)
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
private fun TeamCell(team: TeamInfo, modifier: Modifier, alignEnd: Boolean) {
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
            modifier = Modifier.size(36.dp).clip(RoundedCornerShape(8.dp)),
            contentScale = ContentScale.Fit,
        )
    } else {
        Box(
            Modifier.size(36.dp).clip(RoundedCornerShape(8.dp)).background(VoidBlack),
            contentAlignment = Alignment.Center,
        ) {
            Text(abbrev.take(3), color = Gold, fontSize = 10.sp, fontWeight = FontWeight.Bold)
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
        Text(title, color = Gold, fontWeight = FontWeight.Bold)
        Text(body, color = Muted, style = MaterialTheme.typography.bodySmall)
    }
}
