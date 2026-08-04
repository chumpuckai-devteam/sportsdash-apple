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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Sports
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
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
import com.samirpatel.sportsdash.core.sports.LeagueShelf
import com.samirpatel.sportsdash.core.sports.SportScoreSection
import com.samirpatel.sportsdash.core.sports.TeamInfo
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.VoidBlack

private sealed class ScoreRow {
    data class SportHeader(val section: SportScoreSection, val collapsed: Boolean) : ScoreRow()
    data class LeagueHeader(val shelf: LeagueShelf, val sportKey: String) : ScoreRow()
    data class GameItem(val game: Game, val rowKey: String) : ScoreRow()
    data object MyTeamsHeader : ScoreRow()
}

@Composable
fun ScoresScreen(
    vm: AppViewModel,
    state: AppUiState,
    landscape: Boolean = false,
    onGoSettings: () -> Unit = {},
) {
    var teamFavGame by remember { mutableStateOf<Game?>(null) }
    // CSV survives rotation; defaults expanded like iOS @State.
    var collapsedSportsCsv by rememberSaveable { mutableStateOf("") }
    val collapsedSports = remember(collapsedSportsCsv) {
        collapsedSportsCsv.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSet()
    }

    fun toggleSport(key: String) {
        val next = collapsedSports.toMutableSet()
        if (!next.add(key)) next.remove(key)
        collapsedSportsCsv = next.sorted().joinToString(",")
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(VoidBlack),
        ) {
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
                    label = "Upcoming",
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

            // Variant A: favorite-team logo rail (ESPN / Bleacher Report)
            FavoriteTeamsRail(
                teams = vm.favoriteTeamsRail(),
                onAddHint = {
                    // Guide user: pick any game and long-press to star a team.
                    teamFavGame = state.games.firstOrNull { !vm.gameHasFavoriteTeam(it) }
                        ?: state.games.firstOrNull()
                },
            )

            val sections = vm.sportScoreSections()
            val favoritePin = vm.myGamesPin()
            when {
                state.isLoadingScores && state.games.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = Gold)
                    }
                }

                sections.isEmpty() && favoritePin.isEmpty() -> {
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
                            Text(text = emptyFilterMessage(state.scoresFilter), color = Muted)
                            Text(
                                text = "Long-press a game to ★ a team",
                                color = Muted,
                                fontSize = 12.sp,
                                modifier = Modifier.padding(top = 6.dp),
                            )
                        }
                    }
                }

                else -> {
                    val rows = flattenScoreRows(
                        sections = sections,
                        collapsedSports = collapsedSports,
                        favoritePin = favoritePin,
                        favoritesOnly = false,
                    )
                    LazyColumn(
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(
                            items = rows,
                            key = { row ->
                                when (row) {
                                    is ScoreRow.SportHeader -> "sport-${row.section.sportKey}"
                                    is ScoreRow.LeagueHeader -> "league-${row.sportKey}-${row.shelf.key}"
                                    is ScoreRow.GameItem -> row.rowKey
                                    ScoreRow.MyTeamsHeader -> "my-games"
                                }
                            },
                        ) { row ->
                            when (row) {
                                is ScoreRow.SportHeader -> SportSectionHeader(
                                    section = row.section,
                                    collapsed = row.collapsed,
                                    onToggle = { toggleSport(row.section.sportKey) },
                                )
                                is ScoreRow.LeagueHeader -> LeagueSectionHeader(shelf = row.shelf)
                                is ScoreRow.GameItem -> GameRow(
                                    game = row.game,
                                    isFavoriteMatch = vm.gameHasFavoriteTeam(row.game),
                                    isAwayFavorite = vm.isTeamFavorite(row.game.away.id),
                                    isHomeFavorite = vm.isTeamFavorite(row.game.home.id),
                                    onClick = { vm.openStreamPicker(row.game) },
                                    onLongClick = { teamFavGame = row.game },
                                )
                                ScoreRow.MyTeamsHeader -> MyTeamsSectionHeader(
                                    liveCount = favoritePin.count { it.isLive },
                                )
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

        teamFavGame?.let { g ->
            androidx.compose.material3.AlertDialog(
                onDismissRequest = { teamFavGame = null },
                title = { Text("${g.away.rowLabel} @ ${g.home.rowLabel}", color = TextPrimary) },
                text = {
                    Text(
                        "Favorite teams appear first in Live, Upcoming, and Final.",
                        color = Muted,
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        vm.toggleTeamFavorite(g.home.id)
                        teamFavGame = null
                    }) {
                        Text(
                            if (vm.isTeamFavorite(g.home.id)) "Unstar ${g.home.rowLabel}"
                            else "★ Star ${g.home.rowLabel}",
                            color = Gold,
                        )
                    }
                },
                dismissButton = {
                    Row {
                        TextButton(onClick = {
                            vm.toggleTeamFavorite(g.away.id)
                            teamFavGame = null
                        }) {
                            Text(
                                if (vm.isTeamFavorite(g.away.id)) "Unstar ${g.away.rowLabel}"
                                else "★ ${g.away.rowLabel}",
                                color = Gold,
                            )
                        }
                        TextButton(onClick = { teamFavGame = null }) {
                            Text("Cancel", color = Muted)
                        }
                    }
                },
                containerColor = Panel,
            )
        }
    }
}

private fun emptyFilterMessage(filter: ScoresFilter): String = when (filter) {
    ScoresFilter.LIVE -> "No live games right now"
    ScoresFilter.UPCOMING -> "Nothing upcoming for selected leagues"
    ScoresFilter.FINAL -> "No finals in current boards"
}

private fun flattenScoreRows(
    sections: List<SportScoreSection>,
    collapsedSports: Set<String>,
    favoritePin: List<Game>,
    favoritesOnly: Boolean,
): List<ScoreRow> {
    val out = ArrayList<ScoreRow>()
    if (favoritesOnly) {
        out.add(ScoreRow.MyTeamsHeader)
        for (section in sections) {
            for (shelf in section.leagues) {
                out.add(ScoreRow.LeagueHeader(shelf, section.sportKey))
                for (g in shelf.games) {
                    out.add(ScoreRow.GameItem(g, rowKey = "favsec-${shelf.key}-${g.id}"))
                }
            }
        }
        return out
    }
    val pinIds = favoritePin.map { it.id }.toSet()
    if (favoritePin.isNotEmpty()) {
        out.add(ScoreRow.MyTeamsHeader)
        for (g in favoritePin) {
            out.add(ScoreRow.GameItem(g, rowKey = "fav-${g.id}"))
        }
    }
    for (section in sections) {
        val collapsed = section.sportKey in collapsedSports
        out.add(ScoreRow.SportHeader(section, collapsed))
        if (collapsed) continue
        for (shelf in section.leagues) {
            val rest = shelf.games.filter { it.id !in pinIds }
            if (rest.isEmpty()) continue
            out.add(ScoreRow.LeagueHeader(shelf, section.sportKey))
            for (g in rest) {
                out.add(ScoreRow.GameItem(g, rowKey = "g-${section.sportKey}-${shelf.key}-${g.id}"))
            }
        }
    }
    return out
}

@Composable
private fun MyTeamsSectionHeader(liveCount: Int = 0) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp, bottom = 2.dp)
            .semantics { heading() },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Star,
            contentDescription = null,
            tint = Gold,
            modifier = Modifier.size(16.dp),
        )
        Text(
            text = "My Games",
            color = Gold,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp,
        )
        if (liveCount > 0) {
            Text(
                text = "$liveCount Live",
                color = LiveMint,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
            )
        }
    }
}

@Composable
private fun FavoriteTeamsRail(
    teams: List<TeamInfo>,
    onAddHint: () -> Unit,
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        items(items = teams, key = { it.id }) { team ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.width(56.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(52.dp)
                        .clip(CircleShape)
                        .background(Panel)
                        .border(2.dp, Gold.copy(alpha = 0.65f), CircleShape)
                        .padding(6.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    TeamLogo(url = team.logoUrl, abbrev = team.abbreviation, size = 40.dp)
                }
                Text(
                    text = team.rowLabel,
                    color = Muted,
                    fontSize = 10.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        item(key = "add-fave") {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .width(56.dp)
                    .clickable(onClick = onAddHint),
            ) {
                Box(
                    modifier = Modifier
                        .size(52.dp)
                        .clip(CircleShape)
                        .background(Panel)
                        .border(2.dp, Muted.copy(alpha = 0.5f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("+", color = Muted, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                }
                Text(
                    text = if (teams.isEmpty()) "Add ★" else "Add",
                    color = Muted,
                    fontSize = 10.sp,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun SportSectionHeader(
    section: SportScoreSection,
    collapsed: Boolean,
    onToggle: () -> Unit,
) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp)
            .clip(shape)
            .background(Panel.copy(alpha = 0.72f))
            .border(
                width = 1.dp,
                color = if (collapsed) Muted.copy(alpha = 0.35f) else Gold.copy(alpha = 0.45f),
                shape = shape,
            )
            .clickable(onClick = onToggle)
            .padding(horizontal = 14.dp, vertical = 12.dp)
            .semantics { heading() },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = section.emoji, fontSize = 22.sp)
        Spacer(modifier = Modifier.width(10.dp))
        Text(
            text = section.sportTitle,
            color = TextPrimary,
            fontWeight = FontWeight.Black,
            fontSize = 18.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (section.liveCount > 0) {
            Text(
                text = "${section.liveCount} Live",
                color = LiveMint,
                fontWeight = FontWeight.Bold,
                fontSize = 11.sp,
                modifier = Modifier.padding(end = 8.dp),
            )
        }
        Text(
            text = "${section.gameCount}",
            color = Muted,
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .background(Panel.copy(alpha = 0.95f))
                .padding(horizontal = 8.dp, vertical = 4.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Box(
            modifier = Modifier
                .size(24.dp)
                .clip(CircleShape)
                .background(Gold.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = if (collapsed) Icons.Default.KeyboardArrowRight else Icons.Default.KeyboardArrowDown,
                contentDescription = if (collapsed) "Expand ${section.sportTitle}" else "Collapse ${section.sportTitle}",
                tint = Gold,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

@Composable
private fun LeagueSectionHeader(shelf: LeagueShelf) {
    val live = shelf.games.count { it.isLive }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp, start = 4.dp, end = 4.dp)
            .semantics { heading() },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = shelf.title.uppercase(),
            color = Muted,
            fontWeight = FontWeight.Bold,
            fontSize = 11.sp,
            letterSpacing = 0.6.sp,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (live > 0) {
            Text(
                text = "$live Live",
                color = LiveMint,
                fontWeight = FontWeight.SemiBold,
                fontSize = 11.sp,
            )
        } else {
            Text(
                text = "${shelf.games.size}",
                color = Muted,
                fontWeight = FontWeight.SemiBold,
                fontSize = 11.sp,
            )
        }
    }
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
                        Text(text = "Watch stream", color = Gold, fontWeight = FontWeight.Bold)
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
                        Icon(Icons.Default.Close, contentDescription = "Close", tint = Muted)
                    }
                }
                Spacer(modifier = Modifier.height(12.dp))
                when {
                    !hasPlaylist -> Text(
                        text = "Add Xtream or M3U under Settings, then tap this game again.",
                        color = Muted,
                    )
                    matches.isEmpty() -> Text(
                        text = "No strong IPTV matches. Open Guide and pick a sports channel manually.",
                        color = Muted,
                    )
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
                                Icon(Icons.Default.PlayArrow, contentDescription = null, tint = Gold)
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

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GameRow(
    game: Game,
    isFavoriteMatch: Boolean,
    isAwayFavorite: Boolean = false,
    isHomeFavorite: Boolean = false,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(if (isFavoriteMatch) Gold.copy(alpha = 0.12f) else Panel)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(14.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TeamCell(team = game.away, modifier = Modifier.weight(1f), alignEnd = false, starred = isAwayFavorite)
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
            TeamCell(team = game.home, modifier = Modifier.weight(1f), alignEnd = true, starred = isHomeFavorite)
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
    starred: Boolean = false,
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (starred && alignEnd) {
                    Text("★", color = Gold, fontSize = 11.sp, modifier = Modifier.padding(end = 2.dp))
                }
                Text(
                    text = team.rowLabel,
                    color = TextPrimary,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (starred && !alignEnd) {
                    Text("★", color = Gold, fontSize = 11.sp, modifier = Modifier.padding(start = 2.dp))
                }
            }
            Text(text = team.abbreviation, color = Muted, fontSize = 11.sp)
        }
        if (alignEnd) {
            Spacer(modifier = Modifier.width(8.dp))
            TeamLogo(url = team.logoUrl, abbrev = team.abbreviation)
        }
    }
}

@Composable
private fun TeamLogo(
    url: String?,
    abbrev: String,
    size: androidx.compose.ui.unit.Dp = 36.dp,
) {
    if (!url.isNullOrBlank()) {
        AsyncImage(
            model = url,
            contentDescription = abbrev,
            modifier = Modifier.size(size).clip(RoundedCornerShape(8.dp)),
            contentScale = ContentScale.Fit,
        )
    } else {
        Box(
            modifier = Modifier
                .size(size)
                .clip(RoundedCornerShape(8.dp))
                .background(VoidBlack),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = abbrev.take(3).ifBlank { "?" },
                color = Gold,
                fontSize = (size.value * 0.28f).sp,
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
