package com.samirpatel.sportsdash.ui.theme

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.samirpatel.sportsdash.core.sports.TeamInfo

fun Modifier.gridDotGround(step: Dp = 6.dp, dot: Dp = 1.dp): Modifier = this
    .background(VoidBlack)
    .drawBehind {
        val s = step.toPx()
        val r = (dot.toPx() / 2f).coerceAtLeast(0.5f)
        var y = 0f
        while (y < size.height) {
            var x = 0f
            while (x < size.width) {
                drawCircle(GridDot, r, Offset(x, y))
                x += s
            }
            y += s
        }
    }

fun Modifier.jumbotronPanel(border: Color = Border, width: Dp = 2.dp): Modifier = this
    .background(PanelGradient, RectangleShape)
    .border(width, border, RectangleShape)

fun Modifier.teamEdges(away: Color, home: Color, width: Dp = TeamEdgeWidth): Modifier = this.drawWithContent {
    drawContent()
    val w = width.toPx()
    drawRect(away, size = androidx.compose.ui.geometry.Size(w, size.height))
    drawRect(
        home,
        topLeft = Offset(size.width - w, 0f),
        size = androidx.compose.ui.geometry.Size(w, size.height),
    )
}

fun teamAccent(team: TeamInfo): Color =
    parseTeamHex(team.colorHex) ?: hashedAccent(if (team.id.isBlank()) team.name else team.id)

fun brandStripe(group: String?): Color {
    val g = group.orEmpty().lowercase()
    return when {
        g.contains("movie") || g.contains("film") || g.contains("cinema") || g.contains("hbo") ->
            Color(0xFF6E2B8D)
        g.contains("news") || g.contains("cnn") -> Color(0xFF1D4E89)
        g.contains("sport") || g.contains("espn") || g.contains("nfl") || g.contains("nba") ||
            g.contains("mlb") || g.contains("soccer") || g.contains("football") ||
            g.contains("bein") || g.contains("sky") || g.contains("fs1") || g.contains("golf") ->
            Color(0xFFE31837)
        else -> Border
    }
}

@Composable
fun JumbotronScreenTitle(first: String, gold: String, modifier: Modifier = Modifier, size: Int = 40) {
    Row(modifier = modifier, verticalAlignment = Alignment.Bottom) {
        Text(
            first,
            color = TextPrimary,
            fontFamily = BebasNeue,
            fontSize = size.sp,
            letterSpacing = 0.04.em,
            maxLines = 1,
        )
        Text(
            gold,
            color = Gold,
            fontFamily = BebasNeue,
            fontSize = size.sp,
            letterSpacing = 0.04.em,
            maxLines = 1,
        )
    }
}

@Composable
fun JumbotronLed(
    text: String,
    size: Int = 26,
    color: Color = Gold,
    glow: Boolean = true,
    dimmed: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text,
        modifier = modifier,
        color = color.copy(alpha = if (dimmed) 0.5f else 1f),
        fontFamily = OrbitronBlack,
        fontWeight = FontWeight.Black,
        fontSize = size.sp,
        maxLines = 1,
        overflow = TextOverflow.Clip,
        style = TextStyle(
            shadow = if (glow && !dimmed) Shadow(color = color.copy(alpha = 0.8f), blurRadius = 12f) else null,
        ),
    )
}

@Composable
fun JumbotronWatchButton(
    filled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val bg = if (filled) Gold else Color.Transparent
    val fg = if (filled) VoidBlack else Gold
    Box(
        modifier = modifier
            .height(if (filled) 36.dp else 30.dp)
            .defaultMinSize44()
            .background(bg)
            .then(if (filled) Modifier else Modifier.border(2.dp, Gold))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = if (filled) 14.dp else 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "WATCH",
            color = fg,
            fontFamily = BebasNeue,
            fontSize = if (filled) 18.sp else 15.sp,
            letterSpacing = 0.08.em,
        )
    }
}

private fun Modifier.defaultMinSize44(): Modifier = this.height(44.dp)

@Composable
fun JumbotronToggle(
    isOn: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    tv: Boolean = false,
) {
    val boxW = if (tv) TvToggleWidth else 52.dp
    val boxH = if (tv) TvToggleHeight else 26.dp
    val knobW = if (tv) 30.dp else 22.dp
    val knobH = if (tv) 26.dp else 18.dp
    val hit = if (tv) TvRowMin else 44.dp
    val hair = if (tv) TvHairline else 2.dp
    Box(
        modifier = modifier
            .width(boxW)
            .height(hit)
            .clickable(onClick = onToggle)
            .padding(vertical = ((hit - boxH) / 2)),
        contentAlignment = if (isOn) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(
            modifier = Modifier
                .width(boxW)
                .height(boxH)
                .background(VoidBlack)
                .border(hair, if (isOn) Gold else Border)
                .shadow(if (isOn) 6.dp else 0.dp, RectangleShape, ambientColor = LedGlow, spotColor = LedGlow),
        )
        Box(
            modifier = Modifier
                .padding(2.dp)
                .size(width = knobW, height = knobH)
                .background(if (isOn) Gold else Border),
        )
    }
}

@Composable
fun JumbotronTabBar(
    selected: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    tv: Boolean = false,
) {
    val barH = if (tv) TvTabBarHeight else TabBarHeight
    val labelSize = if (tv) 28.sp else 20.sp
    val lampW = if (tv) 36.dp else 28.dp
    val lampH = if (tv) 5.dp else 4.dp
    val hair = if (tv) TvHairline else 2.dp
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(barH)
            .background(PanelGradient)
            .drawBehind {
                drawRect(Border, size = androidx.compose.ui.geometry.Size(size.width, hair.toPx()))
            }
            .padding(bottom = if (tv) 18.dp else 14.dp, top = 8.dp),
        horizontalArrangement = Arrangement.SpaceAround,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        listOf(0 to "SCORES", 1 to "GUIDE", 2 to "SETTINGS").forEach { (idx, label) ->
            val on = selected == idx
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .weight(1f)
                    .height(if (tv) TvRowMin else 44.dp)
                    .clickable { onSelect(idx) }
                    .semantics { this.selected = on },
            ) {
                Box(
                    modifier = Modifier
                        .width(lampW)
                        .height(lampH)
                        .background(if (on) Gold else Border)
                        .shadow(if (on) 4.dp else 0.dp, ambientColor = LedGlow, spotColor = LedGlow),
                )
                Text(
                    label,
                    color = if (on) Gold else Muted,
                    fontFamily = BebasNeue,
                    fontSize = labelSize,
                    letterSpacing = 0.04.em,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
    }
}

@Composable
fun JumbotronSideNav(
    selected: Int,
    onSelect: (Int) -> Unit,
    expanded: Boolean,
    modifier: Modifier = Modifier,
) {
    val width by animateDpAsState(
        if (expanded) 280.dp else 72.dp,
        animationSpec = tween(180),
        label = "tv-rail-width",
    )
    val padH by animateDpAsState(
        if (expanded) 18.dp else 12.dp,
        animationSpec = tween(180),
        label = "tv-rail-pad",
    )
    Column(
        modifier = modifier
            .width(width)
            .fillMaxHeight()
            .background(PanelGradient)
            .drawBehind {
                val w = TvHairline.toPx()
                drawRect(
                    Border,
                    topLeft = Offset(size.width - w, 0f),
                    size = androidx.compose.ui.geometry.Size(w, size.height),
                )
            }
            .padding(top = 48.dp, bottom = 28.dp, start = padH, end = padH),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        listOf(0 to "SCORES", 1 to "GUIDE", 2 to "SETTINGS").forEach { (idx, label) ->
            val on = selected == idx
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(66.dp)
                    .clickable { onSelect(idx) }
                    .padding(horizontal = if (expanded) 16.dp else 8.dp)
                    .semantics { this.selected = on },
            ) {
                Box(
                    modifier = Modifier
                        .width(6.dp)
                        .height(28.dp)
                        .background(if (on) Gold else Border)
                        .then(
                            if (expanded && on) {
                                Modifier.shadow(4.dp, ambientColor = LedGlow, spotColor = LedGlow)
                            } else {
                                Modifier
                            },
                        ),
                )
                if (expanded) {
                    Spacer(modifier = Modifier.width(16.dp))
                    Text(
                        label,
                        color = if (on) Gold else Muted,
                        fontFamily = BebasNeue,
                        fontSize = 28.sp,
                        letterSpacing = 0.04.em,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

@Composable
fun JumbotronSwitchboard(
    selected: String,
    onSelect: (String) -> Unit,
    teams: List<TeamInfo>,
    onFavorites: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        listOf("LIVE", "UPCOMING", "FINAL").forEach { label ->
            val on = selected == label
            val bg by animateColorAsState(
                if (on) Gold else Panel,
                animationSpec = tween(150),
                label = "sw-$label",
            )
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(44.dp)
                    .background(bg)
                    .then(if (on) Modifier else Modifier.border(2.dp, Border))
                    .clickable { onSelect(label) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    color = if (on) VoidBlack else Muted,
                    fontFamily = BebasNeue,
                    fontSize = 18.sp,
                    letterSpacing = 0.04.em,
                )
            }
        }
        Box(
            modifier = Modifier
                .width(66.dp)
                .height(38.dp)
                .jumbotronPanel(Gold.copy(alpha = 0.5f))
                .clickable(onClick = onFavorites),
            contentAlignment = Alignment.Center,
        ) {
            if (teams.isEmpty()) {
                Text("★ PICK", color = Gold, fontFamily = BebasNeue, fontSize = 12.sp)
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    teams.take(3).forEachIndexed { idx, team ->
                        Box(
                            modifier = Modifier
                                .size(16.dp)
                                .background(teamAccent(team))
                                .then(if (idx == 0) Modifier.border(1.dp, Gold) else Modifier),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                team.abbreviation.take(3),
                                color = TextPrimary,
                                fontFamily = BebasNeue,
                                fontSize = 8.sp,
                            )
                        }
                    }
                    if (teams.size > 3) {
                        Text("+${teams.size - 3}", color = Gold, fontFamily = BebasNeue, fontSize = 12.sp)
                    }
                }
            }
        }
    }
}

@Composable
fun JumbotronMessagePanel(
    title: String,
    subtitle: String,
    cta: String,
    tick: Color = Gold,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .jumbotronPanel(if (tick == Danger) Danger.copy(alpha = 0.55f) else Border)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(4.dp).height(16.dp).background(tick))
            Spacer(Modifier.width(8.dp))
            Text(title, color = TextPrimary, fontFamily = BebasNeue, fontSize = 22.sp, letterSpacing = 0.04.em)
        }
        Text(
            subtitle,
            color = Muted,
            fontFamily = SpaceMono,
            fontSize = 11.sp,
            modifier = Modifier.padding(top = 8.dp),
        )
        Box(
            modifier = Modifier
                .padding(top = 10.dp)
                .height(44.dp)
                .border(2.dp, Gold)
                .clickable(onClick = onClick)
                .padding(horizontal = 10.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(cta, color = Gold, fontFamily = BebasNeue, fontSize = 16.sp)
        }
    }
}

@Composable
fun JumbotronLampCard(
    playlist: LampKind,
    epg: LampKind,
    favorites: LampKind,
    setupCount: Int,
    cta: String,
    onCta: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Brush.horizontalGradient(
                    0f to Color(0xFFE31837).copy(alpha = 0.35f),
                    0.4f to Panel.copy(alpha = 0.95f),
                ),
            )
            .border(2.dp, Gold.copy(alpha = 0.45f))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            lampRow("PLAYLIST", playlist)
            lampRow("EPG", epg)
            lampRow("FAVORITES", favorites)
        }
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text("SETUP ", color = TextPrimary, fontFamily = BebasNeue, fontSize = 22.sp)
                JumbotronLed("$setupCount/3", size = 20, color = Gold, glow = true)
            }
            Box(
                modifier = Modifier
                    .padding(top = 4.dp)
                    .background(Gold)
                    .clickable(onClick = onCta)
                    .padding(horizontal = 10.dp, vertical = 8.dp),
            ) {
                Text(cta, color = VoidBlack, fontFamily = BebasNeue, fontSize = 16.sp)
            }
        }
    }
}

enum class LampKind { DONE, PENDING, BLOCKED }

@Composable
private fun lampRow(title: String, kind: LampKind) {
    val c = when (kind) {
        LampKind.DONE -> LiveMint
        LampKind.PENDING -> Gold
        LampKind.BLOCKED -> Danger
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            modifier = Modifier
                .size(10.dp)
                .background(c, CircleShape)
                .shadow(4.dp, CircleShape, ambientColor = c, spotColor = c),
        )
        Text(title, color = TextPrimary, fontFamily = SpaceMono, fontSize = 11.sp)
    }
}

@Composable
fun JumbotronSectionLabel(title: String, tick: Color) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(top = 4.dp),
    ) {
        Box(Modifier.width(4.dp).height(14.dp).background(tick))
        Text(title, color = Muted, fontFamily = BebasNeue, fontSize = 16.sp, letterSpacing = 0.12.em)
    }
}

@Composable
fun JumbotronSkeleton(height: Dp = 58.dp) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(height)
            .jumbotronPanel(),
    )
}
