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
 * Updated for smarter geo/broadcast/golf US-centric matching (Aug 2026).
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
                // Same geo/golf gates as score() — do not reinsert foreign ESPN via event-group floor.
                if (isGeoForeign(ch.name) && isUSCentricLeague(game.league) && !skipGeoPenaltyForLeague(game.league)) {
                    continue
                }
                if (!passesNonH2HGate(game, ch, awardedCleanBroadcast = false)) {
                    continue
                }
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
        "pga" -> listOf("pga", "pga tour", "golf", "golf channel", "pgatour", "fedex cup", "fedex")
        "lpga" -> listOf("lpga", "golf", "golf channel")
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
        val g = group.lowercase()
        val sp = game.league.sportPath.lowercase()
        val isGolfLike = sp == "golf" || sp == "racing"
        if (isGolfLike) {
            val hasGolf = hasGolfRelatedToken(g, "")
            if (g.contains("sport") && !hasGolf) {
                return false
            }
        }
        if (g.contains("sport")) return true
        if (g.contains(sp)) return true
        if (g.contains(game.league.label.lowercase())) return true
        return leagueAliases(game.league).any { a -> a.length >= 3 && tokenOrPhrase(g, a) }
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

        // Smarter broadcast matching with word-boundary preference and geo filter
        val sortedBroadcasts = game.broadcasts.sortedByDescending { it.length }
        var awardedBroadcast = false
        for (b in sortedBroadcasts) {
            val key = b.lowercase().trim()
            if (key.length < 2) continue
            val matches = tokenOrPhrase(blob, key) || blob.contains(key)
            if (!matches) continue
            // Generic network tokens: no full +40 if geo-foreign (LatAm XX| ESPN etc)
            val generics = setOf("espn", "fox", "nbc", "abc", "cbs", "tnt", "tbs", "usa", "fs1", "fs2", "golf", "nbcsn", "peacock")
            if (key in generics && isGeoForeign(channel.name)) {
                continue  // skip award for foreign geo
            }
            score += 40
            reasons.add("Broadcast: $b")
            awardedBroadcast = true
            break
        }

        // Geo-foreign channel penalty for US-centric leagues/sports (incl golf)
        if (isGeoForeign(channel.name) &&
            isUSCentricLeague(game.league) &&
            !skipGeoPenaltyForLeague(game.league)
        ) {
            score -= 35
            reasons.add("Geo-foreign penalty")
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

        // Sports group +12 with golf special: suppress "sport" alone for golf unless group has golf token or we have clean US broadcast
        if (!inEvent) {
            val isGolfLike = game.league.sportPath == "golf" || game.league.sportPath == "racing"
            val baseContext = groupHasSportsContext(group, game)
            val groupGolfSignal = hasGolfRelatedToken(group, "")
            val cleanBroadcastGolf = isGolfLike && awardedBroadcast && !isGeoForeign(channel.name)
            if (baseContext) {
                val allow = !isGolfLike || groupGolfSignal || cleanBroadcastGolf
                if (allow) {
                    score += 12
                    reasons.add("Sports group")
                }
            } else if (cleanBroadcastGolf) {
                // give context bonus for clean US broadcast (e.g. bare ESPN) even if group context suppressed for golf
                score += 12
                reasons.add("Sports group")
            }
        }

        when {
            name.contains("4k") || name.contains("uhd") -> score += 8
            name.contains("hd") || name.contains("fhd") -> score += 5
        }

        // Golf / non-H2H specific gate (and racing)
        if (game.league.sportPath == "golf" || game.league.sportPath == "racing") {
            val hasGolfToken = hasGolfRelatedToken(name, group)
            val hasCleanUS = awardedBroadcast && !isGeoForeign(channel.name)
            val hasEvent = hasEventNameToken(game.eventName, name)
            if (!hasGolfToken && !hasCleanUS && !hasEvent) {
                // channel only matched via generic ESPN + sports group without golf signal -> drop
                score = 0.0
                reasons.clear()
                reasons.add("No golf signal (generic/foreign only)")
            }
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

    
    /** Golf/racing: require golf-related token, clean US broadcast, or event token — used by score + event-group backfill. */
    private fun passesNonH2HGate(game: Game, channel: IptvChannel, awardedCleanBroadcast: Boolean): Boolean {
        val sp = game.league.sportPath.lowercase()
        if (sp != "golf" && sp != "racing") return true
        val blob = listOfNotNull(channel.name, channel.group).joinToString(" ").lowercase()
        if (hasGolfRelatedToken(blob, channel.name)) return true
        if (awardedCleanBroadcast && !isGeoForeign(channel.name)) return true
        val event = game.eventName?.lowercase().orEmpty()
        if (event.isNotBlank()) {
            val tokens = event.split(Regex("[^a-z0-9]+")).filter { it.length >= 4 }
            if (tokens.any { tokenOrPhrase(blob, it) || blob.contains(it) }) return true
        }
        return false
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

    // --- new helpers for geo, golf, US centric ---

    private fun isGeoForeign(name: String): Boolean {
        val n = name.trim()
        val m = Regex("^([A-Za-z]{2,3})\\s*\\|").find(n)
        if (m != null) {
            val cc = m.groupValues[1].lowercase()
            val friendly = setOf("us", "usa", "uk", "gb", "ca", "au", "ie", "nz", "en")
            return cc !in friendly
        }
        return false
    }

    private fun isUSCentricLeague(league: SportLeague): Boolean {
        val id = league.id.lowercase()
        val usIds = setOf("mlb", "nba", "nfl", "nhl", "pga", "lpga", "mls", "ncaaf", "ncaab")
        if (id in usIds) return true
        val sp = league.sportPath.lowercase()
        return sp == "golf" || sp == "racing"
    }

    private fun skipGeoPenaltyForLeague(league: SportLeague): Boolean {
        val id = league.id.lowercase()
        val skip = setOf("epl", "ucl", "uel", "worldcup", "laliga", "bundesliga", "seriea", "ligue1")
        return league.sportPath.lowercase() == "soccer" && id in skip
    }

    private fun hasGolfRelatedToken(name: String, group: String): Boolean {
        val blob = "$name $group".lowercase()
        val tokens = listOf("golf", "pga", "lpga", "masters", "ryder", "fedex", "pgatour", "st. jude", "st jude")
        return tokens.any { t -> tokenOrPhrase(blob, t) || blob.contains(t) }
    }

    private fun hasEventNameToken(eventName: String?, channelName: String): Boolean {
        val ev = eventName?.lowercase()?.trim() ?: return false
        if (ev.isEmpty()) return false
        // tokens length >=4
        val tokens = ev.split(Regex("[\\s,.:-]+")).filter { it.length >= 4 }
        val ch = channelName.lowercase()
        return tokens.any { t -> ch.contains(t) }
    }
}

private val IptvChannel.searchBlob: String
    get() = listOfNotNull(name, group).joinToString(" ").lowercase()
