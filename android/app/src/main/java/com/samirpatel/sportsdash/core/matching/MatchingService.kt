package com.samirpatel.sportsdash.core.matching

import com.samirpatel.sportsdash.core.model.IptvChannel
import com.samirpatel.sportsdash.core.sports.Game
import com.samirpatel.sportsdash.core.sports.SportLeague
import com.samirpatel.sportsdash.core.sports.TeamInfo

data class ChannelMatch(
    val channel: IptvChannel,
    val score: Double,
    val reason: String,
)

/**
 * Port of iOS MatchingService (v1 subset): event groups, teams, broadcasts.
 */
class MatchingService(
    private val minScore: Double = 48.0,
    private val eventGroupFloor: Double = 70.0,
    private val defaultLimit: Int = 12,
) {
    fun matchGameToChannels(
        game: Game,
        channels: List<IptvChannel>,
        limit: Int = defaultLimit,
    ): List<ChannelMatch> {
        if (channels.isEmpty()) return emptyList()
        val eventGroups = detectEventGroups(game, channels)
        val scored = mutableListOf<ChannelMatch>()
        for (ch in channels) {
            val result = score(game, ch, eventGroups)
            if (result.score >= minScore) scored.add(result)
        }
        if (eventGroups.isNotEmpty()) {
            val seen = scored.map { it.channel.id }.toSet()
            for (ch in channels) {
                if (ch.id in seen) continue
                val g = ch.group?.lowercase()?.trim().orEmpty()
                if (g.isEmpty() || g !in eventGroups) continue
                if (isExcluded(ch.searchBlob)) continue
                scored.add(
                    ChannelMatch(
                        channel = ch,
                        score = eventGroupFloor,
                        reason = "Event group: ${ch.group}",
                    ),
                )
            }
        }
        scored.sortWith(
            compareByDescending<ChannelMatch> { it.reason.contains("Event group") }
                .thenByDescending { it.score }
                .thenBy { it.channel.name.lowercase() },
        )
        return scored.take(limit)
    }

    private fun detectEventGroups(game: Game, channels: List<IptvChannel>): Set<String> {
        val needles = eventNeedles(game)
        val groups = channels.mapNotNull { ch ->
            ch.group?.trim()?.takeIf { it.isNotEmpty() && !isExcluded(it) }?.lowercase()
        }.toSet()
        return groups.filter { groupMatches(it, needles, game) }.toSet()
    }

    private fun eventNeedles(game: Game): List<String> {
        val out = mutableListOf<String>()
        fun add(s: String?) {
            val t = s?.lowercase()?.trim() ?: return
            if (t.length >= 3 && t !in out) out.add(t)
        }
        add(game.league.label)
        add(game.league.id)
        val event = game.eventName?.lowercase()
        if (event != null && !event.contains(" vs ") && !event.contains(" at ")) {
            add(event)
        }
        out.addAll(leagueAliases(game.league))
        return out
    }

    private fun leagueAliases(league: SportLeague): List<String> = when (league.id) {
        "worldcup" -> listOf("world cup", "fifa world cup", "fifa", "mundial", "worldcup")
        "ucl" -> listOf("champions league", "uefa champions", "ucl")
        "uel" -> listOf("europa league", "uel")
        "epl" -> listOf("premier league", "epl")
        "mlb" -> listOf("mlb", "baseball")
        "nba" -> listOf("nba")
        "nfl" -> listOf("nfl")
        "nhl" -> listOf("nhl")
        else -> listOf(league.label.lowercase(), league.sportPath)
    }

    private fun groupMatches(group: String, needles: List<String>, game: Game): Boolean {
        if (isExcluded(group)) return false
        for (n in needles) {
            if (n.length < 3) continue
            if (tokenOrPhrase(group, n)) {
                if (n.length <= 3 && !groupHasSportsContext(group, game)) continue
                return true
            }
        }
        return false
    }

    private fun groupHasSportsContext(group: String, game: Game): Boolean {
        if (group.contains("sport")) return true
        if (group.contains(game.league.sportPath)) return true
        if (group.contains(game.league.label.lowercase())) return true
        return leagueAliases(game.league).any { a -> a.length >= 3 && tokenOrPhrase(group, a) }
    }

    private fun score(
        game: Game,
        channel: IptvChannel,
        eventGroupKeys: Set<String>,
    ): ChannelMatch {
        val name = channel.name.lowercase()
        val group = channel.group?.lowercase().orEmpty()
        val blob = "$name $group"
        var score = 0.0
        val reasons = mutableListOf<String>()
        var inEvent = false

        if (isExcluded(blob)) {
            return ChannelMatch(channel, 0.0, "Excluded")
        }
        if (group.isNotEmpty() && group in eventGroupKeys) {
            inEvent = true
            score += eventGroupFloor
            reasons.add("Event group: ${channel.group}")
        }
        for (b in game.broadcasts) {
            val key = b.lowercase()
            if (key.length >= 2 && blob.contains(key)) {
                score += 40
                reasons.add("Broadcast: $b")
                break
            }
        }
        // H2H sports (not golf/racing)
        if (game.league.sportPath != "golf" && game.league.sportPath != "racing") {
            for (team in listOf(game.home, game.away)) {
                val tn = team.name.lowercase()
                if (tn.length > 3 && name.contains(tn)) {
                    score += 50
                    reasons.add("Team: ${team.name}")
                } else {
                    val nick = tn.split(" ").lastOrNull().orEmpty()
                    if (nick.length > 3 && name.contains(nick)) {
                        score += 28
                        reasons.add("Nickname: $nick")
                    }
                }
            }
            if (teamHit(game.home, name) && teamHit(game.away, name)) {
                score += 40
                reasons.add("Both teams")
            }
        }
        if (!inEvent && groupHasSportsContext(group, game)) {
            score += 12
            reasons.add("Sports group")
        }
        when {
            name.contains("4k") || name.contains("uhd") -> score += 8
            name.contains("hd") || name.contains("fhd") -> score += 5
        }
        return ChannelMatch(
            channel = channel,
            score = score,
            reason = if (reasons.isEmpty()) "Weak match" else reasons.joinToString(" · "),
        )
    }

    private fun teamHit(team: TeamInfo, name: String): Boolean {
        val n = team.name.lowercase()
        val nick = n.split(" ").lastOrNull().orEmpty()
        return (n.length > 3 && name.contains(n)) || (nick.length > 3 && name.contains(nick))
    }

    private fun tokenOrPhrase(hay: String, needle: String): Boolean {
        val n = needle.lowercase()
        val h = hay.lowercase()
        if (n.contains(" ")) return h.contains(n)
        return Regex("\\b${Regex.escape(n)}\\b").containsMatchIn(h)
    }

    private fun isExcluded(blob: String): Boolean {
        val s = blob.lowercase()
        if (Regex("\\b(radio|sirius|podcast)\\b").containsMatchIn(s)) return true
        if (Regex("\\b(news|cnn|msnbc|shopping|xxx|adult)\\b").containsMatchIn(s)) {
            if (Regex("\\b(sport|mlb|nba|nfl|soccer|fifa|espn)\\b").containsMatchIn(s)) {
                return false
            }
            return true
        }
        return false
    }
}

private val IptvChannel.searchBlob: String
    get() = listOfNotNull(name, group).joinToString(" ").lowercase()
