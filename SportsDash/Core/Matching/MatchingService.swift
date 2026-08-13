import Foundation

/// Port of Flutter `MatchingService` (v1 subset): event groups, teams, broadcasts.
/// Updated for smarter geo/broadcast/golf US-centric matching (Aug 2026). Apple+Android parity.
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
                // Same geo/golf gates as score() — do not reinsert foreign ESPN via event-group floor.
                if isGeoForeign(ch.name) && isUSCentricLeague(game.league) && !skipGeoPenaltyForLeague(game.league) {
                    continue
                }
                if !passesNonH2HGate(game: game, channel: ch, awardedCleanBroadcast: false) {
                    continue
                }
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
        case .pga:
            return ["pga", "pga tour", "golf", "golf channel", "pgatour", "fedex cup", "fedex"]
        case .lpga:
            return ["lpga", "golf", "golf channel"]
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
        let g = group.lowercased()
        let sp = game.league.sportPath.lowercased()
        let isGolfLike = sp == "golf" || sp == "racing"
        if (isGolfLike) {
            let hasGolf = hasGolfRelatedToken(g, "")
            if (g.contains("sport") && !hasGolf) {
                return false
            }
        }
        if g.contains("sport") { return true }
        if g.contains(sp) { return true }
        if g.contains(game.league.label.lowercased()) { return true }
        for a in leagueAliases(game.league) where a.count >= 3 && tokenOrPhrase(g, a) {
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

        // Smarter broadcast matching: prefer longer names (Golf Channel over ESPN), word-boundary, geo filter for generics
        let sortedBroadcasts = game.broadcasts.sorted { $0.count > $1.count }
        var awardedBroadcast = false
        for b in sortedBroadcasts {
            let key = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if key.count < 2 { continue }
            let matches = tokenOrPhrase(blob, key) || blob.contains(key)
            if !matches { continue }
            let generics: Set<String> = ["espn", "fox", "nbc", "abc", "cbs", "tnt", "tbs", "usa", "fs1", "fs2", "golf", "nbcsn", "peacock"]
            if generics.contains(key) && isGeoForeign(channel.name) {
                continue  // do not award +40 for geo-foreign generic e.g. "ARG | ESPN 2"
            }
            score += 40
            reasons.append("Broadcast: \(b)")
            awardedBroadcast = true
            break
        }

        // Geo-foreign penalty for US-centric (pga etc + golf/racing)
        if isGeoForeign(channel.name) &&
            isUSCentricLeague(game.league) &&
            !skipGeoPenaltyForLeague(game.league) {
            score -= 35
            reasons.append("Geo-foreign penalty")
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

        // Sports group +12 with golf special: suppress "sport" alone for golf unless group has golf token or clean US broadcast
        if !inEvent {
            let isGolfLike = game.league.sportPath == "golf" || game.league.sportPath == "racing"
            let baseContext = groupHasSportsContext(group, game)
            let groupGolfSignal = hasGolfRelatedToken(group, "")
            let cleanBroadcastGolf = isGolfLike && awardedBroadcast && !isGeoForeign(channel.name)
            if (baseContext) {
                let allow = !isGolfLike || groupGolfSignal || cleanBroadcastGolf
                if (allow) {
                    score += 12
                    reasons.append("Sports group")
                }
            } else if (cleanBroadcastGolf) {
                // give context bonus for clean US broadcast (e.g. bare ESPN) even if group context suppressed for golf
                score += 12
                reasons.append("Sports group")
            }
        }

        if name.contains("4k") || name.contains("uhd") { score += 8 }
        else if name.contains("hd") || name.contains("fhd") { score += 5 }

        // Golf / non-H2H specific: require golf token OR clean US broadcast OR event token; else zero for golf
        if game.league.sportPath == "golf" || game.league.sportPath == "racing" {
            let hasGolfToken = hasGolfRelatedToken(name, group)
            let hasCleanUS = awardedBroadcast && !isGeoForeign(channel.name)
            let hasEvent = hasEventNameToken(game.eventName, name)
            if !hasGolfToken && !hasCleanUS && !hasEvent {
                score = 0
                reasons = ["No golf signal (generic/foreign only)"]
            }
        }

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

    
    private func passesNonH2HGate(game: Game, channel: IptvChannel, awardedCleanBroadcast: Bool) -> Bool {
        let sp = game.league.sportPath.lowercased()
        guard sp == "golf" || sp == "racing" else { return true }
        let blob = "\(channel.name.lowercased()) \((channel.group ?? "").lowercased())"
        if hasGolfRelatedToken(blob, channel.name) { return true }
        if awardedCleanBroadcast && !isGeoForeign(channel.name) { return true }
        if let event = game.eventName?.lowercased(), !event.isEmpty {
            let tokens = event.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 }
            for t in tokens where tokenOrPhrase(blob, t) || blob.contains(t) {
                return true
            }
        }
        return false
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

    // --- new helpers for parity with Android ---

    private func isGeoForeign(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let idx = n.firstIndex(of: "|") {
            let before = String(n[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let cc = before.replacingOccurrences(of: " ", with: "")
            if cc.count >= 2 && cc.count <= 3 {
                let friendly: Set<String> = ["us", "usa", "uk", "gb", "ca", "au", "ie", "nz", "en"]
                return !friendly.contains(cc)
            }
        }
        return false
    }

    private func isUSCentricLeague(_ league: SportLeague) -> Bool {
        let id = league.rawValue.lowercased()
        let usIds: Set<String> = ["mlb", "nba", "nfl", "nhl", "pga", "lpga", "mls", "ncaaf", "ncaab"]
        if usIds.contains(id) { return true }
        let sp = league.sportPath.lowercased()
        return sp == "golf" || sp == "racing"
    }

    private func skipGeoPenaltyForLeague(_ league: SportLeague) -> Bool {
        let id = league.rawValue.lowercased()
        let skip: Set<String> = ["epl", "ucl", "uel", "worldcup", "laliga", "bundesliga", "seriea", "ligue1"]
        return league.sportPath.lowercased() == "soccer" && skip.contains(id)
    }

    private func hasGolfRelatedToken(_ name: String, _ group: String) -> Bool {
        let blob = "\(name) \(group)".lowercased()
        let tokens = ["golf", "pga", "lpga", "masters", "ryder", "fedex", "pgatour", "st. jude", "st jude"]
        return tokens.contains { t in tokenOrPhrase(blob, t) || blob.contains(t) }
    }

    private func hasEventNameToken(_ eventName: String?, _ channelName: String) -> Bool {
        guard let ev = eventName?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !ev.isEmpty else { return false }
        let tokens = ev.split(whereSeparator: { " ,.:-".contains($0) }).filter { $0.count >= 4 }.map(String.init)
        let ch = channelName.lowercased()
        return tokens.contains { ch.contains($0) }
    }
}

private extension IptvChannel {
    var searchBlob: String {
        "\(name.lowercased()) \((group ?? "").lowercased())"
    }
}
