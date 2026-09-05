import SwiftUI

/// Player overlay ticker: sport → league → live games, with tap-to-collapse like the scores dashboard.
struct LiveScoresStrip: View, Equatable {
    let ordered: [Game]
    var sections: [SportScoreSection] = []
    var currentGameId: String?
    var favoriteTeamIds: Set<String> = []
    var lastPlayedGameIds: [String] = []
    /// Android D parity — compact horizontal pills under exit bar (top of player).
    var compactTopStyle: Bool = false
    var onGameTap: (Game) -> Void

    /// Collapsed sport section keys (`soccer`, `baseball`, …).
    @State private var collapsedSports: Set<String> = []
    /// Collapsed league keys (`worldcup`, `mlb`, …).
    @State private var collapsedLeagues: Set<String> = []

    static func == (lhs: LiveScoresStrip, rhs: LiveScoresStrip) -> Bool {
        lhs.ordered == rhs.ordered
            && lhs.sections == rhs.sections
            && lhs.currentGameId == rhs.currentGameId
            && lhs.favoriteTeamIds == rhs.favoriteTeamIds
            && lhs.lastPlayedGameIds == rhs.lastPlayedGameIds
            && lhs.compactTopStyle == rhs.compactTopStyle
    }

    /// Sort/group off-main. Nothing in `body` may sort.
    static func buildTicker(
        games: [Game],
        currentGameId: String?,
        favoriteTeamIds: Set<String>,
        lastPlayedGameIds: [String]
    ) -> (ordered: [Game], sections: [SportScoreSection]) {
        var live = games.filter { $0.isLive && $0.isTickerEligible }
        live.sort { a, b in
            func rank(_ g: Game) -> Int {
                let fav = favoriteTeamIds.contains(g.home.id) || favoriteTeamIds.contains(g.away.id)
                let cur = g.id == currentGameId
                if fav && cur { return 0 }
                if fav { return 1 }
                if cur { return 2 }
                return 3
            }
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            let aLp = lastPlayedGameIds.firstIndex(of: a.id) ?? 9999
            let bLp = lastPlayedGameIds.firstIndex(of: b.id) ?? 9999
            if aLp != bLp { return aLp < bLp }
            return a.startTime < b.startTime
        }
        let ordered = Array(live.prefix(40))
        var sections = ScoreboardGrouping.sportSections(from: ordered, favoriteTeamIds: favoriteTeamIds)
        for i in sections.indices {
            for j in sections[i].leagues.indices {
                sections[i].leagues[j].games.sort { a, b in
                    let aNow = a.id == currentGameId ? 0 : 1
                    let bNow = b.id == currentGameId ? 0 : 1
                    if aNow != bNow { return aNow < bNow }
                    let aLp = lastPlayedGameIds.firstIndex(of: a.id) ?? 9999
                    let bLp = lastPlayedGameIds.firstIndex(of: b.id) ?? 9999
                    if aLp != bLp { return aLp < bLp }
                    let aFav = (favoriteTeamIds.contains(a.home.id) || favoriteTeamIds.contains(a.away.id)) ? 0 : 1
                    let bFav = (favoriteTeamIds.contains(b.home.id) || favoriteTeamIds.contains(b.away.id)) ? 0 : 1
                    if aFav != bFav { return aFav < bFav }
                    return a.startTime < b.startTime
                }
            }
        }
        return (ordered, sections)
    }

    var body: some View {
        Group {
            if compactTopStyle {
                compactPills
            } else {
                legacyStrip
            }
        }
    }

    /// Overlay pills — transparent strip background; full-bleed video underneath.
    private var compactPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if ordered.isEmpty {
                    Text("No other live games")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                        .padding(.horizontal, 4)
                }
                ForEach(ordered) { g in
                    Button { onGameTap(g) } label: {
                        HStack(spacing: 5) {
                            miniLogo(g.away)
                            Text("\(g.away.abbreviation) \(g.away.displayScore)–\(g.home.displayScore) \(g.home.abbreviation)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(g.id == currentGameId ? SportsColors.voidBlack : .white)
                                .lineLimit(1)
                            miniLogo(g.home)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            g.id == currentGameId
                                ? SportsColors.gold
                                : SportsColors.panel,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .background(Color.clear) // never reserve/scrim over video
    }

    private func miniLogo(_ team: TeamInfo) -> some View {
        Group {
            if let raw = team.logoURL, let url = URL(string: raw) {
                TeamLogo(url: url, size: 18) {
                    Text(String(team.abbreviation.prefix(2)))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(SportsColors.gold)
                }
            } else {
                Text(String(team.abbreviation.prefix(2)))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SportsColors.gold)
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
    }

    private var legacyStrip: some View {
        VStack(spacing: 6) {
            if let current = ordered.first(where: { $0.id == currentGameId })
                ?? ordered.first {
                hero(current)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 10) {
                    if sections.isEmpty {
                        Text("No other live games")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .padding(.horizontal)
                    }
                    ForEach(sections) { section in
                        sportChip(section)
                        if !collapsedSports.contains(section.sportKey) {
                            ForEach(section.leagues) { league in
                                leagueChip(league)
                                if !collapsedLeagues.contains(league.key) {
                                    ForEach(league.games) { g in
                                        card(g)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: 120)
        }
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.5), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Hierarchy chips

    private func sportChip(_ section: SportScoreSection) -> some View {
        let collapsed = collapsedSports.contains(section.sportKey)
        let count = section.leagues.reduce(0) { $0 + $1.games.count }
        return Button {
            toggleSport(section.sportKey)
        } label: {
            VStack(spacing: 4) {
                Text(section.emoji).font(.title3)
                Text(section.sportTitle.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(SportsColors.gold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                HStack(spacing: 3) {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SportsColors.muted)
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(SportsColors.muted)
                }
            }
            .frame(width: 72, height: 104)
            // Content-layer opaque panel — not Liquid Glass.
            .background(SportsColors.voidBlack.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SportsColors.gold.opacity(collapsed ? 0.25 : 0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.sportTitle), \(count) live")
        .accessibilityHint(collapsed ? "Expand sport" : "Collapse sport")
    }

    private func leagueChip(_ league: LeagueShelf) -> some View {
        let collapsed = collapsedLeagues.contains(league.key)
        return Button {
            toggleLeague(league.key)
        } label: {
            VStack(spacing: 4) {
                Text(league.title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(SportsColors.gold)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                Text("\(league.games.count) LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SportsColors.live)
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SportsColors.muted)
            }
            .padding(.horizontal, 8)
            .frame(width: 78, height: 104)
            .background(SportsColors.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SportsColors.border.opacity(collapsed ? 0.35 : 0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(league.title), \(league.games.count) live")
        .accessibilityHint(collapsed ? "Expand league" : "Collapse league")
    }

    // MARK: - Hero / cards

    private func hero(_ game: Game) -> some View {
        VStack(spacing: 2) {
            Text("\(game.league.sportSectionTitle.uppercased())  ·  \(game.league.label)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(SportsColors.gold)
            if game.usesMatchupLayout {
                Text("\(game.away.name)  \(game.away.score ?? 0)–\(game.home.score ?? 0)  \(game.home.name)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text(game.eventName ?? game.league.label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func card(_ g: Game) -> some View {
        let isCurrent = g.id == currentGameId
        return Button {
            onGameTap(g)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(g.league.label.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(SportsColors.gold)
                        .lineLimit(1)
                    Spacer()
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(SportsColors.live)
                    } else if lastPlayedGameIds.contains(g.id) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(SportsColors.muted)
                    }
                }
                HStack {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(SportsColors.live)
                    Spacer()
                    Text(g.statusLine)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SportsColors.textSecondary)
                        .lineLimit(1)
                }
                if g.usesMatchupLayout {
                    teamLine(g.away)
                    teamLine(g.home)
                } else {
                    Text(g.eventName ?? g.league.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SportsColors.text)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(width: 158, height: 104, alignment: .topLeading)
            // Opaque elevated content card — never Liquid Glass over video.
            .sportsContentCard(radius: 12, emphasized: isCurrent)
        }
        .buttonStyle(.plain)
    }

    private func teamLine(_ t: TeamInfo) -> some View {
        HStack {
            Text(t.name.count <= 18 ? t.name : t.abbreviation)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.text)
                .lineLimit(1)
            Spacer()
            Text(t.displayScore)
                .font(.subheadline.weight(.heavy).monospacedDigit())
                .foregroundStyle(SportsColors.text)
        }
    }

    // MARK: - Helpers

    private func toggleSport(_ key: String) {
        if collapsedSports.contains(key) {
            collapsedSports.remove(key)
        } else {
            collapsedSports.insert(key)
        }
    }

    private func toggleLeague(_ key: String) {
        if collapsedLeagues.contains(key) {
            collapsedLeagues.remove(key)
        } else {
            collapsedLeagues.insert(key)
        }
    }

}


