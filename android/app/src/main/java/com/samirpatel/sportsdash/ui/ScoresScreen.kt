package com.samirpatel.sportsdash.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
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
import kotlinx.coroutines.launch
import com.samirpatel.sportsdash.core.sports.SportLeague
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.contentDescription
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
import com.samirpatel.sportsdash.ui.tv.tvFocusRing

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
    isTelevision: Boolean = false,
    onGoSettings: () -> Unit = {},
) {
    var teamFavGame by remember { mutableStateOf<Game?>(null) }
    var showTeamPicker by remember { mutableStateOf(false) }
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
            // Condensed chrome: landscape = filters stacked left + faves row right;
            // portrait = one tight row of filters then compact faves rail.
            ScoresTopChrome(
                landscape = landscape,
                isTelevision = isTelevision,
                filter = state.scoresFilter,
                status = state.scoresStatus,
                teams = vm.favoriteTeamsRail(),
                onFilter = { vm.setScoresFilter(it) },
                onOpenPicker = { showTeamPicker = true },
                onTeamClick = { showTeamPicker = true },
            )

            if (!landscape && state.playlist == null) {
                Text(
                    text = "Add IPTV in Settings to watch from scores.",
                    color = Muted,
                    fontSize = 11.sp,
                    modifier = Modifier
                        .padding(horizontal = 12.dp, vertical = 1.dp)
                        .clickable(onClick = onGoSettings),
                )
            }

            val scoresErr = state.scoresError
            if (scoresErr != null) {
                Text(
                    text = scoresErr,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
                )
            }

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
                        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
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
                                    tvFocus = isTelevision,
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
                        "Star a team from this game, or use + Add for Sport → League → Team.",
                        color = Muted,
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        vm.toggleTeamFavorite(g.home)
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
                            vm.toggleTeamFavorite(g.away)
                            teamFavGame = null
                        }) {
                            Text(
                                if (vm.isTeamFavorite(g.away.id)) "Unstar ${g.away.rowLabel}"
                                else "★ ${g.away.rowLabel}",
                                color = Gold,
                            )
                        }
                        TextButton(onClick = {
                            teamFavGame = null
                            showTeamPicker = true
                        }) {
                            Text("Browse…", color = Gold)
                        }
                        TextButton(onClick = { teamFavGame = null }) {
                            Text("Cancel", color = Muted)
                        }
                    }
                },
                containerColor = Panel,
            )
        }

        if (showTeamPicker) {
            FavoriteTeamPickerDialog(
                vm = vm,
                favoriteIds = state.favoriteTeamIds,
                onDismiss = { showTeamPicker = false },
                onToggle = { team -> vm.toggleTeamFavorite(team) },
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
private fun ScoresTopChrome(
    landscape: Boolean,
    isTelevision: Boolean = false,
    filter: ScoresFilter,
    status: String?,
    teams: List<TeamInfo>,
    onFilter: (ScoresFilter) -> Unit,
    onOpenPicker: () -> Unit,
    onTeamClick: (TeamInfo) -> Unit,
) {
    // One short row: Live | Upcoming | Final | scrollable faves…  (never stacked)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        ScoreFilterChip(label = "Live", selected = filter == ScoresFilter.LIVE, onClick = { onFilter(ScoresFilter.LIVE) }, compact = true, tvFocus = isTelevision)
        ScoreFilterChip(label = "Upcoming", selected = filter == ScoresFilter.UPCOMING, onClick = { onFilter(ScoresFilter.UPCOMING) }, compact = true, tvFocus = isTelevision)
        ScoreFilterChip(label = "Final", selected = filter == ScoresFilter.FINAL, onClick = { onFilter(ScoresFilter.FINAL) }, compact = true, tvFocus = isTelevision)
        FavoriteTeamsRail(
            teams = teams,
            onOpenPicker = onOpenPicker,
            onTeamClick = onTeamClick,
            compact = true,
            logosOnly = true,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun FavoriteTeamsRail(
    teams: List<TeamInfo>,
    onOpenPicker: () -> Unit,
    onTeamClick: (TeamInfo) -> Unit = {},
    compact: Boolean = false,
    logosOnly: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val mark = if (logosOnly || compact) 30.dp else 40.dp
    val cell = if (logosOnly) 34.dp else if (compact) 48.dp else 56.dp
    LazyRow(
        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
        horizontalArrangement = Arrangement.spacedBy(if (logosOnly) 6.dp else 8.dp),
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(items = teams, key = { it.id }) { team ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .width(cell)
                    .clickable { onTeamClick(team) },
            ) {
                Box(
                    modifier = Modifier
                        .size(mark)
                        .clip(CircleShape)
                        .background(Panel)
                        .padding(3.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    TeamLogo(url = team.logoUrl, abbrev = team.abbreviation, size = mark - 6.dp)
                }
                if (!logosOnly) {
                    Text(
                        text = team.rowLabel,
                        color = Muted,
                        fontSize = 10.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }
        }
        item(key = "add-fave") {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .width(cell)
                    .clickable(onClick = onOpenPicker),
            ) {
                Box(
                    modifier = Modifier
                        .size(mark)
                        .clip(CircleShape)
                        .background(Panel),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("+", color = Muted, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
                if (!logosOnly) {
                    Text(
                        text = if (teams.isEmpty()) "Add ★" else "Add",
                        color = Muted,
                        fontSize = 10.sp,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }
        }
    }
}

private enum class FavPickerStep { Sport, League, Team }

@Composable
private fun FavoriteTeamPickerDialog(
    vm: AppViewModel,
    favoriteIds: Set<String>,
    onDismiss: () -> Unit,
    onToggle: (TeamInfo) -> Unit,
) {
    var step by remember { mutableStateOf(FavPickerStep.Sport) }
    var sportName by remember { mutableStateOf<String?>(null) }
    var league by remember { mutableStateOf<SportLeague?>(null) }
    var teams by remember { mutableStateOf<List<TeamInfo>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val groups = remember { vm.sportGroupsForPicker() }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.94f)
                .fillMaxHeight(0.82f),
            shape = RoundedCornerShape(18.dp),
            color = Panel,
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (step != FavPickerStep.Sport) {
                        TextButton(onClick = {
                            when (step) {
                                FavPickerStep.Team -> {
                                    step = FavPickerStep.League
                                    teams = emptyList()
                                    error = null
                                }
                                FavPickerStep.League -> {
                                    step = FavPickerStep.Sport
                                    sportName = null
                                    league = null
                                }
                                else -> Unit
                            }
                        }) { Text("Back", color = Gold) }
                    }
                    Text(
                        text = when (step) {
                            FavPickerStep.Sport -> "Add favorite · Sport"
                            FavPickerStep.League -> "Add favorite · ${sportName ?: "League"}"
                            FavPickerStep.Team -> "Add favorite · ${league?.label ?: "Team"}"
                        },
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "Close", tint = Muted)
                    }
                }
                Text(
                    text = when (step) {
                        FavPickerStep.Sport -> "1. Choose a sport"
                        FavPickerStep.League -> "2. Choose a league"
                        FavPickerStep.Team -> "3. Tap a team to star / unstar"
                    },
                    color = Muted,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
                error?.let {
                    Text(text = it, color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(horizontal = 16.dp))
                }
                if (loading) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = Gold)
                    }
                } else {
                    LazyColumn(
                        contentPadding = PaddingValues(12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                    ) {
                        when (step) {
                            FavPickerStep.Sport -> {
                                items(groups, key = { it.first }) { (name, _) ->
                                    PickerRow(
                                        title = name,
                                        subtitle = "${groups.first { it.first == name }.second.size} leagues",
                                        onClick = {
                                            sportName = name
                                            step = FavPickerStep.League
                                        },
                                    )
                                }
                            }
                            FavPickerStep.League -> {
                                val leagues = groups.firstOrNull { it.first == sportName }?.second.orEmpty()
                                items(leagues, key = { it.id }) { lg ->
                                    PickerRow(
                                        title = lg.label,
                                        subtitle = lg.id.uppercase(),
                                        onClick = {
                                            league = lg
                                            step = FavPickerStep.Team
                                            loading = true
                                            error = null
                                            scope.launch {
                                                val list = vm.loadTeamsForLeague(lg)
                                                teams = list
                                                loading = false
                                                if (list.isEmpty()) {
                                                    error = "No teams returned for ${lg.label}. Try again later."
                                                }
                                            }
                                        },
                                    )
                                }
                            }
                            FavPickerStep.Team -> {
                                items(teams, key = { it.id }) { team ->
                                    val starred = team.id in favoriteIds
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(
                                                if (starred) Gold.copy(alpha = 0.14f) else VoidBlack,
                                            )
                                            .clickable { onToggle(team) }
                                            .padding(horizontal = 12.dp, vertical = 10.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        TeamLogo(url = team.logoUrl, abbrev = team.abbreviation, size = 36.dp)
                                        Spacer(modifier = Modifier.width(12.dp))
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                team.name.ifBlank { team.rowLabel },
                                                color = TextPrimary,
                                                fontWeight = FontWeight.SemiBold,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                            Text(team.abbreviation, color = Muted, fontSize = 12.sp)
                                        }
                                        Text(
                                            if (starred) "★" else "☆",
                                            color = Gold,
                                            fontSize = 20.sp,
                                            fontWeight = FontWeight.Bold,
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
}

@Composable
private fun PickerRow(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(VoidBlack)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Text(subtitle, color = Muted, fontSize = 12.sp)
        }
        Icon(
            imageVector = Icons.Default.KeyboardArrowRight,
            contentDescription = null,
            tint = Gold,
        )
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
            .padding(top = 4.dp)
            .clip(shape)
            .background(Panel.copy(alpha = 0.72f))
            .clickable(onClick = onToggle)
            .padding(horizontal = 12.dp, vertical = 8.dp)
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
fun StreamPickerDialog(
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
private fun ScoreFilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    compact: Boolean = false,
    tvFocus: Boolean = false,
) {
    // Custom compact chip — Material FilterChip is too tall for dense chrome.
    val shape = RoundedCornerShape(50)
    Text(
        text = label,
        color = if (selected) VoidBlack else TextPrimary,
        fontWeight = FontWeight.SemiBold,
        fontSize = if (compact) 11.sp else 12.sp,
        maxLines = 1,
        modifier = Modifier
            .tvFocusRing(enabled = tvFocus, shape = shape)
            .clip(shape)
            .background(if (selected) Gold else Panel)
            .clickable(onClick = onClick)
            .padding(
                horizontal = if (compact) 10.dp else 12.dp,
                vertical = if (compact) 5.dp else 8.dp,
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
    tvFocus: Boolean = false,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val a11y = buildString {
        append(game.away.rowLabel)
        append(" ")
        if (game.isLive || game.isFinal) append(game.away.displayScore)
        append(" at ")
        append(game.home.rowLabel)
        append(" ")
        if (game.isLive || game.isFinal) append(game.home.displayScore)
        append(". ")
        append(game.statusLine)
        append(". Double tap to watch.")
    }
    Column(modifier = Modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .tvFocusRing(enabled = tvFocus, shape = RoundedCornerShape(12.dp))
                .clip(RoundedCornerShape(12.dp))
                .background(
                    if (isFavoriteMatch) Gold.copy(alpha = 0.08f) else Color.Transparent,
                )
                .combinedClickable(onClick = onClick, onLongClick = onLongClick)
                .semantics(mergeDescendants = true) {
                    contentDescription = a11y
                }
                .padding(horizontal = 8.dp, vertical = 10.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TeamSide(
                    team = game.away,
                    score = if (game.isLive || game.isFinal) game.away.displayScore else null,
                    starred = isAwayFavorite,
                    alignEnd = false,
                    modifier = Modifier.weight(1f),
                )
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier
                        .padding(horizontal = 6.dp)
                        .widthIn(min = 72.dp),
                ) {
                    Text(
                        text = "WATCH",
                        color = VoidBlack,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .background(Gold, RoundedCornerShape(6.dp))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                    Text(
                        text = game.statusLine,
                        color = if (game.isLive) LiveMint else Muted,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 11.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
                TeamSide(
                    team = game.home,
                    score = if (game.isLive || game.isFinal) game.home.displayScore else null,
                    starred = isHomeFavorite,
                    alignEnd = true,
                    modifier = Modifier.weight(1f),
                )
            }
        }
        if (game.broadcasts.isNotEmpty()) {
            Text(
                text = game.broadcasts.take(3).joinToString(" · "),
                color = Muted,
                fontSize = 11.sp,
                modifier = Modifier.padding(start = 12.dp, end = 12.dp, bottom = 6.dp),
            )
        }
    }
}

/** iOS-style side: outside-corner star + logo + short label + large score. */
@Composable
private fun TeamSide(
    team: TeamInfo,
    score: String?,
    starred: Boolean,
    alignEnd: Boolean,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = if (alignEnd) Arrangement.End else Arrangement.Start,
        ) {
            if (!alignEnd) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    TeamLogo(url = team.logoUrl, abbrev = team.abbreviation, size = 34.dp)
                    Text(
                        text = team.rowLabel,
                        color = TextPrimary,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.widthIn(max = 72.dp),
                    )
                }
                if (score != null) {
                    Text(
                        text = score,
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 26.sp,
                        modifier = Modifier.padding(start = 6.dp),
                    )
                }
            } else {
                if (score != null) {
                    Text(
                        text = score,
                        color = TextPrimary,
                        fontWeight = FontWeight.Bold,
                        fontSize = 26.sp,
                        modifier = Modifier.padding(end = 6.dp),
                    )
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    TeamLogo(url = team.logoUrl, abbrev = team.abbreviation, size = 34.dp)
                    Text(
                        text = team.rowLabel,
                        color = TextPrimary,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.widthIn(max = 72.dp),
                    )
                }
            }
        }
        if (starred) {
            Text(
                text = "★",
                color = Gold,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.align(if (alignEnd) Alignment.TopEnd else Alignment.TopStart),
            )
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
