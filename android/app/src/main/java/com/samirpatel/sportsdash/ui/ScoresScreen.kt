package com.samirpatel.sportsdash.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.ui.unit.em
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
import com.samirpatel.sportsdash.core.sports.ScoreboardGrouping
import com.samirpatel.sportsdash.core.sports.SportScoreSection
import com.samirpatel.sportsdash.core.sports.TeamInfo
import com.samirpatel.sportsdash.ui.theme.BebasNeue
import com.samirpatel.sportsdash.ui.theme.Border
import com.samirpatel.sportsdash.ui.theme.Danger
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.JumbotronLampCard
import com.samirpatel.sportsdash.ui.theme.JumbotronLed
import com.samirpatel.sportsdash.ui.theme.JumbotronMessagePanel
import com.samirpatel.sportsdash.ui.theme.JumbotronScreenTitle
import com.samirpatel.sportsdash.ui.theme.JumbotronSkeleton
import com.samirpatel.sportsdash.ui.theme.JumbotronSwitchboard
import com.samirpatel.sportsdash.ui.theme.JumbotronWatchButton
import com.samirpatel.sportsdash.ui.theme.LampKind
import com.samirpatel.sportsdash.ui.theme.LiveMint
import com.samirpatel.sportsdash.ui.theme.Muted
import com.samirpatel.sportsdash.ui.theme.OrbitronBlack
import com.samirpatel.sportsdash.ui.theme.Panel
import com.samirpatel.sportsdash.ui.theme.ScoreRowHeight
import com.samirpatel.sportsdash.ui.theme.ScreenInset
import com.samirpatel.sportsdash.ui.theme.SpaceMono
import com.samirpatel.sportsdash.ui.theme.TextPrimary
import com.samirpatel.sportsdash.ui.theme.TextSecondary
import com.samirpatel.sportsdash.ui.theme.TvCardHeight
import com.samirpatel.sportsdash.ui.theme.TvCardWidth
import com.samirpatel.sportsdash.ui.theme.TvEdgeBar
import com.samirpatel.sportsdash.ui.theme.TvHairline
import com.samirpatel.sportsdash.ui.theme.TvHeroWidth
import com.samirpatel.sportsdash.ui.theme.TvScreenInset
import com.samirpatel.sportsdash.ui.theme.VoidBlack
import com.samirpatel.sportsdash.ui.theme.jumbotronPanel
import com.samirpatel.sportsdash.ui.theme.teamAccent
import com.samirpatel.sportsdash.ui.theme.teamEdges
import com.samirpatel.sportsdash.ui.tv.tvFocusGroup
import com.samirpatel.sportsdash.ui.tv.tvFocusRing

private sealed class ScoreRow {
    data class SportHeader(val section: SportScoreSection, val collapsed: Boolean) : ScoreRow()
    data class LeagueHeader(val shelf: LeagueShelf, val sportKey: String) : ScoreRow()
    data class GameItem(val game: Game, val rowKey: String) : ScoreRow()
    data object MyTeamsHeader : ScoreRow()
    data class Hero(val game: Game) : ScoreRow()
    data object Lamp : ScoreRow()
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
            if (isTelevision) {
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
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = ScreenInset, vertical = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    JumbotronScreenTitle(first = "SCORE", gold = "BOARD")
                    JumbotronSwitchboard(
                        selected = when (state.scoresFilter) {
                            ScoresFilter.LIVE -> "LIVE"
                            ScoresFilter.UPCOMING -> "UPCOMING"
                            ScoresFilter.FINAL -> "FINAL"
                        },
                        onSelect = {
                            vm.setScoresFilter(
                                when (it) {
                                    "UPCOMING" -> ScoresFilter.UPCOMING
                                    "FINAL" -> ScoresFilter.FINAL
                                    else -> ScoresFilter.LIVE
                                },
                            )
                        },
                        teams = vm.favoriteTeamsRail(),
                        onFavorites = { showTeamPicker = true },
                    )
                    if (state.scoresWarning != null && state.scoresError == null) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Box(Modifier.width(4.dp).height(12.dp).background(Danger))
                            Text(
                                state.scoresWarning!!,
                                color = Danger,
                                fontFamily = SpaceMono,
                                fontSize = 10.sp,
                            )
                        }
                    }
                }
            }

            if (isTelevision && !landscape && state.playlist == null) {
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
            if (isTelevision && scoresErr != null) {
                Text(
                    text = scoresErr,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 2.dp),
                )
            }
            val scoresWarn = state.scoresWarning
            if (isTelevision && scoresWarn != null && scoresErr == null) {
                Text(
                    text = scoresWarn,
                    color = Muted,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 1.dp),
                )
            }

            val sections = vm.sportScoreSections()
            val favoritePin = vm.myGamesPin()
            when {
                state.isLoadingScores && state.games.isEmpty() -> {
                    if (isTelevision) {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator(color = Gold)
                        }
                    } else {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = ScreenInset),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            if (state.playlist == null) {
                                ScoresLampCard(state = state, onGoSettings = onGoSettings)
                            }
                            JumbotronSkeleton()
                            JumbotronSkeleton()
                            JumbotronSkeleton()
                        }
                    }
                }

                sections.isEmpty() && favoritePin.isEmpty() -> {
                    if (isTelevision) {
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
                            }
                        }
                    } else {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = ScreenInset),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            if (state.playlist == null) {
                                ScoresLampCard(state = state, onGoSettings = onGoSettings)
                            }
                            if (scoresErr != null) {
                                JumbotronMessagePanel(
                                    title = "SCORES UNAVAILABLE",
                                    subtitle = scoresErr,
                                    cta = "RETRY",
                                    tick = Danger,
                                    onClick = { vm.refreshScores() },
                                )
                            } else {
                                JumbotronMessagePanel(
                                    title = emptyFilterMessage(state.scoresFilter).uppercase(),
                                    subtitle = "Star a team to pin My Game, or switch filters.",
                                    cta = if (state.scoresFilter == ScoresFilter.LIVE) "UPCOMING ▸" else "LEAGUES ▸",
                                    onClick = {
                                        if (state.scoresFilter == ScoresFilter.LIVE) {
                                            vm.setScoresFilter(ScoresFilter.UPCOMING)
                                        } else {
                                            onGoSettings()
                                        }
                                    },
                                )
                            }
                        }
                    }
                }

                else -> {
                    if (isTelevision) {
                        // Netflix-style horizontal card rails for Android TV
                        ScoresTVBrowse(
                            favoritePin = favoritePin,
                            sections = sections,
                            isFavorite = { g -> vm.gameHasFavoriteTeam(g) },
                            hasMatch = { g -> vm.hasStreamMatch(g) },
                            filter = state.scoresFilter,
                            onGameClick = { g -> vm.openStreamPicker(g) },
                            onGameLongClick = { g -> teamFavGame = g },
                        )
                    } else {
                        val rows = flattenScoreRows(
                            sections = sections,
                            collapsedSports = collapsedSports,
                            favoritePin = favoritePin,
                            favoritesOnly = false,
                            jumbotron = true,
                            showLamp = state.playlist == null,
                        )
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = ScreenInset, vertical = 6.dp),
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
                                        is ScoreRow.Hero -> "hero-${row.game.id}"
                                        ScoreRow.Lamp -> "lamp"
                                    }
                                },
                            ) { row ->
                                when (row) {
                                    is ScoreRow.SportHeader -> {}
                                    is ScoreRow.LeagueHeader -> JumbotronLeagueHead(shelf = row.shelf, filter = state.scoresFilter)
                                    is ScoreRow.GameItem -> JumbotronGameRow(
                                        game = row.game,
                                        isAwayFavorite = vm.isTeamFavorite(row.game.away.id),
                                        isHomeFavorite = vm.isTeamFavorite(row.game.home.id),
                                        hasMatch = vm.hasStreamMatch(row.game),
                                        onClick = { vm.openStreamPicker(row.game) },
                                        onLongClick = { teamFavGame = row.game },
                                    )
                                    ScoreRow.MyTeamsHeader -> {}
                                    is ScoreRow.Hero -> JumbotronHero(
                                        game = row.game,
                                        isAwayFavorite = vm.isTeamFavorite(row.game.away.id),
                                        isHomeFavorite = vm.isTeamFavorite(row.game.home.id),
                                        matchCount = vm.streamMatchCount(row.game),
                                        onClick = { vm.openStreamPicker(row.game) },
                                    )
                                    ScoreRow.Lamp -> ScoresLampCard(state = state, onGoSettings = onGoSettings)
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
    jumbotron: Boolean = false,
    showLamp: Boolean = false,
): List<ScoreRow> {
    val out = ArrayList<ScoreRow>()
    if (jumbotron && showLamp) out.add(ScoreRow.Lamp)
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
        if (jumbotron) {
            out.add(ScoreRow.Hero(favoritePin.first()))
            for (g in favoritePin.drop(1)) {
                out.add(ScoreRow.GameItem(g, rowKey = "fav-${g.id}"))
            }
        } else {
            out.add(ScoreRow.MyTeamsHeader)
            for (g in favoritePin) {
                out.add(ScoreRow.GameItem(g, rowKey = "fav-${g.id}"))
            }
        }
    }
    for (section in sections) {
        val collapsed = section.sportKey in collapsedSports
        if (!jumbotron) out.add(ScoreRow.SportHeader(section, collapsed))
        if (collapsed && !jumbotron) continue
        for (shelf in section.leagues) {
            val rest = shelf.games.filter { it.id !in pinIds }
            out.add(ScoreRow.LeagueHeader(shelf, section.sportKey))
            if (rest.isEmpty()) continue
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
            .padding(horizontal = 6.dp, vertical = 2.dp)
            .tvFocusGroup(enabled = isTelevision),
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
            tvFocus = isTelevision,
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
    tvFocus: Boolean = false,
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
                    .tvFocusRing(enabled = tvFocus, shape = CircleShape, scaleFocused = 1.08f)
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
                    .tvFocusRing(enabled = tvFocus, shape = CircleShape, scaleFocused = 1.08f)
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
    tvFocus: Boolean = false,
    onToggle: () -> Unit,
) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp)
            .tvFocusRing(enabled = tvFocus, shape = shape)
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
        when {
            shelf.games.isEmpty() -> {
                Text(
                    text = "None scheduled",
                    color = Muted,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 11.sp,
                )
            }
            live > 0 -> {
                Text(
                    text = "$live Live",
                    color = LiveMint,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 11.sp,
                )
            }
            else -> {
                Text(
                    text = "${shelf.games.size}",
                    color = Muted,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 11.sp,
                )
            }
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
                                    .tvFocusRing(enabled = true, shape = RoundedCornerShape(12.dp))
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
private fun ScoresLampCard(state: AppUiState, onGoSettings: () -> Unit) {
    val playlist = if (state.playlist == null) LampKind.PENDING else if (state.channelError != null) LampKind.BLOCKED else LampKind.DONE
    val epg = when {
        state.epgReady -> LampKind.DONE
        else -> LampKind.PENDING
    }
    val fav = if (state.favoriteTeamIds.isEmpty()) LampKind.PENDING else LampKind.DONE
    val done = listOf(playlist, epg, fav).count { it == LampKind.DONE }
    JumbotronLampCard(
        playlist = playlist,
        epg = epg,
        favorites = fav,
        setupCount = done,
        cta = when {
            state.playlist == null -> "ADD PLAYLIST ▸"
            state.favoriteTeamIds.isEmpty() -> "PICK TEAMS ▸"
            else -> "SETTINGS ▸"
        },
        onCta = onGoSettings,
    )
}

private fun Game.jumbotronDigits(): Pair<String, String> =
    if (isUpcoming) "–" to "–" else {
        (if (away.displayScore == "—") "–" else away.displayScore) to
            (if (home.displayScore == "—") "–" else home.displayScore)
    }

private fun Game.jumbotronLosing(team: TeamInfo): Boolean {
    val a = away.score ?: return false
    val h = home.score ?: return false
    if (!isLive && !isFinal) return false
    if (a == h) return false
    return if (team.id == away.id) a < h else h < a
}

private fun Game.jumbotronLed(): String = when {
    isFinal -> "FINAL"
    isUpcoming -> statusLine.uppercase()
    !clock.isNullOrBlank() -> if (clock.contains("'")) clock else "$clock'"
    !period.isNullOrBlank() -> "Q$period"
    else -> statusLine.uppercase()
}

@Composable
private fun JumbotronLeagueHead(shelf: LeagueShelf, filter: ScoresFilter) {
    val live = shelf.games.count { it.isLive }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(4.dp).height(16.dp).background(Gold))
        Spacer(Modifier.width(8.dp))
        Text(
            shelf.title.uppercase(),
            color = TextSecondary,
            fontFamily = BebasNeue,
            fontSize = 20.sp,
            letterSpacing = 0.04.em,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        when (filter) {
            ScoresFilter.LIVE -> if (live > 0) JumbotronLed("$live LIVE", size = 10, color = LiveMint, glow = true)
            ScoresFilter.UPCOMING -> JumbotronLed("${shelf.games.size} UPCOMING", size = 10, color = Muted, glow = false)
            ScoresFilter.FINAL -> JumbotronLed("${shelf.games.size} FINAL", size = 10, color = Muted, glow = false)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun JumbotronGameRow(
    game: Game,
    isAwayFavorite: Boolean,
    isHomeFavorite: Boolean,
    hasMatch: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val digits = game.jumbotronDigits()
    val a11y = "${game.away.rowLabel}, ${digits.first}, ${game.jumbotronLed()}, ${game.home.rowLabel}, ${digits.second}${if (hasMatch) ", Watch" else ""}"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(ScoreRowHeight)
            .jumbotronPanel()
            .teamEdges(teamAccent(game.away), teamAccent(game.home))
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .semantics(mergeDescendants = true) { contentDescription = a11y }
            .padding(start = 16.dp, end = if (hasMatch) 8.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            game.away.abbreviation + if (isAwayFavorite) " ★" else "",
            color = TextPrimary,
            fontFamily = BebasNeue,
            fontSize = 22.sp,
            letterSpacing = 0.04.em,
            modifier = Modifier.width(60.dp),
            maxLines = 1,
        )
        JumbotronLed(
            digits.first,
            size = 26,
            color = if (game.isUpcoming) Muted else Gold,
            glow = !game.isUpcoming,
            dimmed = game.jumbotronLosing(game.away),
            modifier = Modifier.width(44.dp),
        )
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.weight(1f)) {
            JumbotronLed(
                game.jumbotronLed(),
                size = 12,
                color = if (game.isLive) LiveMint else Muted,
                glow = game.isLive,
            )
        }
        JumbotronLed(
            digits.second,
            size = 26,
            color = if (game.isUpcoming) Muted else Gold,
            glow = !game.isUpcoming,
            dimmed = game.jumbotronLosing(game.home),
            modifier = Modifier.width(44.dp),
        )
        Text(
            (if (isHomeFavorite) "★ " else "") + game.home.abbreviation,
            color = TextPrimary,
            fontFamily = BebasNeue,
            fontSize = 22.sp,
            letterSpacing = 0.04.em,
            modifier = Modifier.width(60.dp),
            maxLines = 1,
        )
        if (hasMatch) {
            JumbotronWatchButton(filled = false, onClick = onClick)
        }
    }
}

@Composable
private fun JumbotronHero(
    game: Game,
    isAwayFavorite: Boolean,
    isHomeFavorite: Boolean,
    matchCount: Int,
    onClick: () -> Unit,
) {
    val digits = game.jumbotronDigits()
    val away = teamAccent(game.away).copy(alpha = 0.55f)
    val home = teamAccent(game.home).copy(alpha = 0.60f)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                androidx.compose.ui.graphics.Brush.horizontalGradient(
                    0f to away,
                    0.34f to Panel.copy(alpha = 0.95f),
                    0.66f to Panel.copy(alpha = 0.95f),
                    1f to home,
                ),
            )
            .border(2.dp, LiveMint.copy(alpha = 0.45f))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                "★ MY GAME · ${game.league.label.uppercase()}",
                color = Gold,
                fontFamily = BebasNeue,
                fontSize = 16.sp,
            )
            JumbotronLed(
                if (game.isLive) "● LIVE" else if (game.isFinal) "FINAL" else game.statusLine.uppercase(),
                size = 11,
                color = if (game.isLive) LiveMint else Muted,
                glow = game.isLive,
            )
        }
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(game.away.rowLabel.uppercase(), color = TextPrimary, fontFamily = BebasNeue, fontSize = 32.sp, maxLines = 1)
                Text(game.away.abbreviation + if (isAwayFavorite) " ★" else "", color = TextSecondary, fontFamily = SpaceMono, fontSize = 10.sp)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(84.dp)) {
                Text(if (game.isUpcoming) "START" else "CLOCK", color = Muted, fontFamily = BebasNeue, fontSize = 13.sp)
                JumbotronLed(
                    if (game.isUpcoming) game.statusLine.uppercase() else (game.clock ?: "LIVE"),
                    size = 22,
                    color = if (game.isLive) LiveMint else if (game.isUpcoming) Muted else Gold,
                    glow = game.isLive,
                )
            }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.End) {
                Text(game.home.rowLabel.uppercase(), color = TextPrimary, fontFamily = BebasNeue, fontSize = 32.sp, maxLines = 1)
                Text(game.home.abbreviation + if (isHomeFavorite) " ★" else "", color = TextSecondary, fontFamily = SpaceMono, fontSize = 10.sp)
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.weight(1f).background(VoidBlack).border(1.dp, Border).padding(vertical = 6.dp),
                contentAlignment = Alignment.Center,
            ) {
                JumbotronLed(digits.first, size = 58, color = if (game.isUpcoming) Muted else Gold, glow = !game.isUpcoming, dimmed = game.jumbotronLosing(game.away))
            }
            Spacer(Modifier.width(84.dp))
            Box(
                Modifier.weight(1f).background(VoidBlack).border(1.dp, Border).padding(vertical = 6.dp),
                contentAlignment = Alignment.Center,
            ) {
                JumbotronLed(digits.second, size = 58, color = if (game.isUpcoming) Muted else Gold, glow = !game.isUpcoming, dimmed = game.jumbotronLosing(game.home))
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(top = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                if (game.broadcasts.isNotEmpty()) {
                    Text(game.broadcasts.take(2).joinToString(" · "), color = TextSecondary, fontFamily = SpaceMono, fontSize = 10.sp)
                }
                if (matchCount > 0) {
                    JumbotronLed(if (matchCount == 1) "1 STREAM OK" else "$matchCount STREAMS OK", size = 10, color = LiveMint, glow = true)
                } else {
                    Text("NO STREAM MATCHED", color = Muted, fontFamily = SpaceMono, fontSize = 10.sp)
                }
            }
            if (matchCount > 0) {
                JumbotronWatchButton(filled = true, onClick = onClick)
            }
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

// ─── Android TV Netflix-style Scores browse ───────────────────────────────────

@Composable
private fun ScoresTVBrowse(
    favoritePin: List<Game>,
    sections: List<SportScoreSection>,
    isFavorite: (Game) -> Boolean,
    hasMatch: (Game) -> Boolean = { false },
    filter: ScoresFilter = ScoresFilter.LIVE,
    onGameClick: (Game) -> Unit,
    onGameLongClick: (Game) -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        if (favoritePin.isNotEmpty()) {
            item(key = "rail-my-games") {
                ScoresTVRail(
                    title = "★ MY GAMES",
                    tick = Gold,
                    games = favoritePin,
                    isFavorite = isFavorite,
                    heroFirst = true,
                    hasMatch = hasMatch,
                    filter = filter,
                    onGameClick = onGameClick,
                    onGameLongClick = onGameLongClick,
                )
            }
        }
        // Use pure extracted transform: per-league rails (not flat per sport).
        // This ensures every section.leagues shelf gets its own titled rail
        // with league label + cards or "None scheduled".
        val tvRails = ScoreboardGrouping.tvScoreRails(sections)
        tvRails.forEach { rail ->
            item(key = rail.key) {
                ScoresTVRail(
                    title = rail.title,
                    games = rail.games,
                    isFavorite = isFavorite,
                    hasMatch = hasMatch,
                    filter = filter,
                    onGameClick = onGameClick,
                    onGameLongClick = onGameLongClick,
                )
            }
        }
    }
}

@Composable
private fun ScoresTVRail(
    title: String,
    emoji: String = "",
    tick: Color = Gold,
    games: List<Game>,
    isFavorite: (Game) -> Boolean,
    heroFirst: Boolean = false,
    hasMatch: (Game) -> Boolean = { false },
    filter: ScoresFilter = ScoresFilter.LIVE,
    onGameClick: (Game) -> Unit,
    onGameLongClick: (Game) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = TvScreenInset, vertical = 4.dp),
        ) {
            Box(Modifier.width(6.dp).height(24.dp).background(tick))
            Spacer(Modifier.width(12.dp))
            Text(
                text = title.uppercase(),
                color = TextSecondary,
                fontFamily = BebasNeue,
                fontSize = 30.sp,
                letterSpacing = 0.04.em,
                modifier = Modifier.weight(1f),
            )
            val live = games.count { it.isLive }
            if (filter == ScoresFilter.LIVE && live > 0) {
                JumbotronLed("$live LIVE", size = 16, color = LiveMint, glow = true)
            } else if (games.isNotEmpty()) {
                JumbotronLed("${games.size}", size = 16, color = Muted, glow = false)
            }
        }
        if (games.isEmpty()) {
            Text(
                text = "None scheduled",
                color = Muted,
                fontFamily = SpaceMono,
                fontSize = 16.sp,
                modifier = Modifier.padding(horizontal = TvScreenInset, vertical = 8.dp),
            )
        } else {
            LazyRow(
                contentPadding = PaddingValues(horizontal = TvScreenInset, vertical = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .tvFocusGroup(),
            ) {
                items(items = games, key = { it.id }) { game ->
                    val idx = games.indexOfFirst { it.id == game.id }
                    ScoresTVGameCard(
                        game = game,
                        isFavoriteMatch = isFavorite(game),
                        hasMatch = hasMatch(game),
                        isHero = heroFirst && idx == 0,
                        onClick = { onGameClick(game) },
                        onLongClick = { onGameLongClick(game) },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ScoresTVGameCard(
    game: Game,
    isFavoriteMatch: Boolean,
    hasMatch: Boolean = false,
    isHero: Boolean = false,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val digits = game.jumbotronDigits()
    val w = if (isHero) TvHeroWidth else TvCardWidth
    val away = teamAccent(game.away)
    val home = teamAccent(game.home)
    Box(
        modifier = Modifier
            .width(w)
            .height(TvCardHeight)
            .then(
                if (isHero) {
                    Modifier.background(
                        androidx.compose.ui.graphics.Brush.horizontalGradient(
                            0f to away.copy(alpha = 0.55f),
                            0.34f to Panel.copy(alpha = 0.95f),
                            0.66f to Panel.copy(alpha = 0.95f),
                            1f to home.copy(alpha = 0.60f),
                        ),
                    )
                } else {
                    Modifier.jumbotronPanel(width = TvHairline)
                },
            )
            .then(if (isHero) Modifier.border(TvHairline, LiveMint.copy(alpha = 0.45f)) else Modifier)
            .teamEdges(away, home, TvEdgeBar)
            .tvFocusRing()
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .semantics {
                contentDescription =
                    "${game.away.rowLabel}, ${digits.first}, ${game.jumbotronLed()}, ${game.home.rowLabel}, ${digits.second}${if (hasMatch) ", Watch" else ""}"
            }
            .padding(horizontal = 18.dp, vertical = 12.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    (if (isHero) game.away.rowLabel else game.away.abbreviation).uppercase() +
                        if (isFavoriteMatch) " ★" else "",
                    color = TextPrimary,
                    fontFamily = BebasNeue,
                    fontSize = if (isHero) 44.sp else 34.sp,
                    maxLines = 1,
                    modifier = Modifier.weight(1f),
                )
                JumbotronLed(
                    game.jumbotronLed(),
                    size = 18,
                    color = if (game.isLive) LiveMint else Muted,
                    glow = game.isLive,
                )
                Text(
                    (if (isHero) game.home.rowLabel else game.home.abbreviation).uppercase(),
                    color = TextPrimary,
                    fontFamily = BebasNeue,
                    fontSize = if (isHero) 44.sp else 34.sp,
                    maxLines = 1,
                    modifier = Modifier.weight(1f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.End,
                )
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.weight(1f).height(if (isHero) 96.dp else 66.dp)
                        .background(VoidBlack).border(TvHairline, Border),
                    contentAlignment = Alignment.Center,
                ) {
                    JumbotronLed(
                        digits.first,
                        size = if (isHero) 64 else 44,
                        color = if (game.isUpcoming) Muted else Gold,
                        glow = !game.isUpcoming,
                        dimmed = game.jumbotronLosing(game.away),
                    )
                }
                Spacer(Modifier.width(24.dp))
                Box(
                    Modifier.weight(1f).height(if (isHero) 96.dp else 66.dp)
                        .background(VoidBlack).border(TvHairline, Border),
                    contentAlignment = Alignment.Center,
                ) {
                    JumbotronLed(
                        digits.second,
                        size = if (isHero) 64 else 44,
                        color = if (game.isUpcoming) Muted else Gold,
                        glow = !game.isUpcoming,
                        dimmed = game.jumbotronLosing(game.home),
                    )
                }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (hasMatch) game.broadcasts.take(2).joinToString(" · ").ifBlank { game.matchupLabel }
                    else "NO STREAM MATCHED",
                    color = if (hasMatch) TextSecondary else Muted,
                    fontFamily = SpaceMono,
                    fontSize = 13.sp,
                    maxLines = 1,
                    modifier = Modifier.weight(1f),
                )
                if (hasMatch) {
                    JumbotronWatchButton(filled = true, onClick = onClick)
                }
            }
        }
    }
}

@Composable
private fun ScoresTVTeamBlock(
    team: TeamInfo,
    score: String?,
    modifier: Modifier = Modifier,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier,
    ) {
        val logo = team.logoUrl
        if (!logo.isNullOrBlank()) {
            AsyncImage(
                model = logo,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(48.dp),
            )
        } else {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(VoidBlack),
            ) {
                Text(
                    text = team.abbreviation.take(3).uppercase(),
                    color = Gold,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                )
            }
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = team.rowLabel,
            color = TextPrimary,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (score != null) {
            Text(
                text = score,
                color = TextPrimary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Black,
            )
        }
    }
}
