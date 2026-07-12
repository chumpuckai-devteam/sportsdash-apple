import Foundation

/// Port of Flutter `MatchingService` (v1 subset): event groups, teams, broadcasts.
struct MatchingService: Sendable {
    var minScore: Double = 48
    var eventGroupFloor: Double = 70
    var defaultLimit: Int = 10

    func matchGameToChannels(_ game: Game, channels: [IptvChannel], limit: Int? = nil) -> [ChannelMatch] {
        let cap = limit ?? defaultLimit
        let eventGroups = detectEventGroups(game: game, channels: channels)
        var scored: [ChannelMatch] = []

        for ch in channels {
            let result = score(game: game, channel: ch, eventGroupKeys: eventGroups)
            if result.score >= minScore {
                scored.append(result)
            }
        }

        if !eventGroups.isEmpty {
            let seen = Set(scored.map(\.channel.id))
            for ch in channels where !seen.contains(ch.id) {
                let g = (ch.group ?? "").lowercased().trimmingCharacters(in: .whitespaces)
                guard eventGroups.contains(g) else { continue }
                if isExcluded(ch.searchBlob) { continue }
                scored.append(
                    ChannelMatch(
                        channel: ch,
                        score: eventGroupFloor,
                        reason: "Event group: \(ch.group ?? "")"
                    )
                )
            }
        }

        scored.sort {
            let aEvent = $0.reason.contains("Event group")
            let bEvent = $1.reason.contains("Event group")
            if aEvent != bEvent { return aEvent && !bEvent }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.channel.name.localizedCaseInsensitiveCompare($1.channel.name) == .orderedAscending
        }

        if scored.count > cap {
            return Array(scored.prefix(cap))
        }
        return scored
    }

    private func detectEventGroups(game: Game, channels: [IptvChannel]) -> Set<String> {
        let needles = eventNeedles(game)
        var groups = Set<String>()
        for ch in channels {
            guard let g = ch.group?.trimmingCharacters(in: .whitespaces), !g.isEmpty else { continue }
            if isExcluded(g) { continue }
            groups.insert(g.lowercased())
        }
        var matched = Set<String>()
        for g in groups where groupMatches(g, needles: needles, game: game) {
            matched.insert(g)
        }
        return matched
    }

    private func eventNeedles(_ game: Game) -> [String] {
        var out: [String] = []
        func add(_ s: String?) {
            guard let t = s?.lowercased().trimmingCharacters(in: .whitespaces), t.count >= 3 else { return }
            if !out.contains(t) { out.append(t) }
        }
        add(game.league.label)
        add(game.league.rawValue)
        if let event = game.eventName?.lowercased(),
           !event.contains(" vs ") && !event.contains(" at ") {
            add(event)
        }
        out.append(contentsOf: leagueAliases(game.league))
        return out
    }

    private func leagueAliases(_ league: SportLeague) -> [String] {
        switch league {
        case .worldcup:
            return ["world cup", "fifa world cup", "fifa", "mundial", "worldcup"]
        case .ucl:
            return ["champions league", "uefa champions", "ucl"]
        case .uel:
            return ["europa league", "uel"]
        case .epl:
            return ["premier league", "epl"]
        case .mlb:
            return ["mlb", "baseball"]
        case .nba:
            return ["nba"]
        case .nfl:
            return ["nfl"]
        case .nhl:
            return ["nhl"]
        default:
            return [league.label.lowercased(), league.sportPath]
        }
    }

    private func groupMatches(_ group: String, needles: [String], game: Game) -> Bool {
        if isExcluded(group) { return false }
        for n in needles where n.count >= 3 {
            if tokenOrPhrase(group, n) {
                if n.count <= 3 && !groupHasSportsContext(group, game) { continue }
                return true
            }
        }
        return false
    }

    private func groupHasSportsContext(_ group: String, _ game: Game) -> Bool {
        if group.contains("sport") { return true }
        if group.contains(game.league.sportPath) { return true }
        if group.contains(game.league.label.lowercased()) { return true }
        for a in leagueAliases(game.league) where a.count >= 3 && tokenOrPhrase(group, a) {
            return true
        }
        return false
    }

    private func score(game: Game, channel: IptvChannel, eventGroupKeys: Set<String>) -> ChannelMatch {
        let name = channel.name.lowercased()
        let group = (channel.group ?? "").lowercased()
        let blob = "\(name) \(group)"
        var score: Double = 0
        var reasons: [String] = []
        var inEvent = false

        if isExcluded(blob) {
            return ChannelMatch(channel: channel, score: 0, reason: "Excluded")
        }

        if !group.isEmpty, eventGroupKeys.contains(group) {
            inEvent = true
            score += eventGroupFloor
            reasons.append("Event group: \(channel.group ?? "")")
        }

        for b in game.broadcasts {
            let key = b.lowercased()
            if key.count >= 2, blob.contains(key) {
                score += 40
                reasons.append("Broadcast: \(b)")
                break
            }
        }

        if game.usesMatchupLayout {
            for team in [game.home, game.away] {
                let tn = team.name.lowercased()
                if tn.count > 3, name.contains(tn) {
                    score += 50
                    reasons.append("Team: \(team.name)")
                } else {
                    let nick = tn.split(separator: " ").last.map(String.init) ?? ""
                    if nick.count > 3, name.contains(nick) {
                        score += 28
                        reasons.append("Nickname: \(nick)")
                    }
                }
            }
            let homeHit = teamHit(game.home, name)
            let awayHit = teamHit(game.away, name)
            if homeHit && awayHit {
                score += 40
                reasons.append("Both teams")
            }
        }

        if !inEvent, groupHasSportsContext(group, game) {
            score += 12
            reasons.append("Sports group")
        }

        if name.contains("4k") || name.contains("uhd") { score += 8 }
        else if name.contains("hd") || name.contains("fhd") { score += 5 }

        return ChannelMatch(
            channel: channel,
            score: score,
            reason: reasons.isEmpty ? "Weak match" : reasons.joined(separator: " · ")
        )
    }

    private func teamHit(_ team: TeamInfo, _ name: String) -> Bool {
        let n = team.name.lowercased()
        let nick = n.split(separator: " ").last.map(String.init) ?? ""
        return (n.count > 3 && name.contains(n)) || (nick.count > 3 && name.contains(nick))
    }

    private func tokenOrPhrase(_ hay: String, _ needle: String) -> Bool {
        let n = needle.lowercased()
        let h = hay.lowercased()
        if n.contains(" ") { return h.contains(n) }
        // word boundary-ish
        return h.range(of: "\\b\(NSRegularExpression.escapedPattern(for: n))\\b", options: .regularExpression) != nil
    }

    private func isExcluded(_ blob: String) -> Bool {
        let s = blob.lowercased()
        if s.range(of: #"\b(radio|sirius|podcast)\b"#, options: .regularExpression) != nil {
            return true
        }
        if s.range(of: #"\b(news|cnn|msnbc|shopping|xxx|adult)\b"#, options: .regularExpression) != nil {
            if s.range(of: #"\b(sport|mlb|nba|nfl|soccer|fifa|espn)\b"#, options: .regularExpression) != nil {
                return false
            }
            return true
        }
        return false
    }
}

private extension IptvChannel {
    var searchBlob: String {
        "\(name.lowercased()) \((group ?? "").lowercased())"
    }
}
