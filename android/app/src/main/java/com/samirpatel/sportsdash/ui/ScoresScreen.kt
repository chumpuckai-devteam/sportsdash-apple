package com.samirpatel.sportsdash.ui

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sports
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.core.sports.TeamInfo
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack

@Composable
fun ScoresScreen(vm: AppViewModel, state: AppUiState) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(VoidBlack),
    ) {
        if (state.playlist == null) {
            SetupBanner(
                title = "Add IPTV in Settings",
                body = "Scores work without a playlist. Add Xtream/M3U under Settings to watch streams.",
            )
        }

        LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                ScoreFilterChip(
                    label = "Live",
                    selected = state.scoresFilter == ScoresFilter.LIVE,
                    onClick = { vm.setScoresFilter(ScoresFilter.LIVE) },
                )
            }
            item {
                ScoreFilterChip(
                    label = "Upcoming",
                    selected = state.scoresFilter == ScoresFilter.UPCOMING,
                    onClick = { vm.setScoresFilter(ScoresFilter.UPCOMING) },
                )
            }
            item {
                ScoreFilterChip(
                    label = "Final",
                    selected = state.scoresFilter == ScoresFilter.FINAL,
                    onClick = { vm.setScoresFilter(ScoresFilter.FINAL) },
                )
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
                        Icon(
                            imageVector = Icons.Default.Sports,
                            contentDescription = null,
                            tint = Muted,
                            modifier = Modifier.size(40.dp),
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = when (state.scoresFilter) {
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
                        items(items = games, key = { it.id }) { game ->
                            GameRow(game = game)
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
private fun GameRow(game: Game) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Panel)
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
                        text = "${game.away.displayScore}  –  ${game.home.displayScore}",
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 22.sp,
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
        Column(horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start) {
            Text(
                text = team.rowLabel,
                color = TextPrimary,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(text = team.abbreviation, color = Muted, fontSize = 11.sp)
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
