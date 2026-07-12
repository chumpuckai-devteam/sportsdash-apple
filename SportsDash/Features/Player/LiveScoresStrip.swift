import SwiftUI

/// Player overlay ticker: sport → league → live games, with tap-to-collapse like the scores dashboard.
struct LiveScoresStrip: View {
    let games: [Game]
    var currentGameId: String?
    var favoriteTeamIds: Set<String> = []
    var lastPlayedGameIds: [String] = []
    var onGameTap: (Game) -> Void

    /// Collapsed sport section keys (`soccer`, `baseball`, …).
    @State private var collapsedSports: Set<String> = []
    /// Collapsed league keys (`worldcup`, `mlb`, …).
    @State private var collapsedLeagues: Set<String> = []

    private var liveOrdered: [Game] {
        var live = games.filter(\.isLive)
        live.sort { a, b in
            let aNow = a.id == currentGameId ? 0 : 1
            let bNow = b.id == currentGameId ? 0 : 1
            if aNow != bNow { return aNow < bNow }
            let aLp = lastPlayedRank(a.id)
            let bLp = lastPlayedRank(b.id)
            if aLp != bLp { return aLp < bLp }
            let aFav = isFav(a) ? 0 : 1
            let bFav = isFav(b) ? 0 : 1
            if aFav != bFav { return aFav < bFav }
            return a.startTime < b.startTime
        }
        return Array(live.prefix(40))
    }

    /// Same sport → league shelves as the scores dashboard, live-only.
    private var shelves: [LeagueShelf] {
        ScoreboardGrouping.leagueShelves(from: liveOrdered)
    }

    private var sportSections: [StripSportSection] {
        var sections: [StripSportSection] = []
        var current: StripSportSection?
        for shelf in shelves {
            if current?.sportKey != shelf.sportKey {
                if let current { sections.append(current) }
                current = StripSportSection(
                    sportKey: shelf.sportKey,
                    sportTitle: shelf.sportTitle,
                    emoji: shelf.games.first?.league.emoji ?? "🏟️",
                    leagues: [shelf]
                )
            } else {
                current?.leagues.append(shelf)
            }
        }
        if let current { sections.append(current) }
        return sections
    }

    var body: some View {
        VStack(spacing: 6) {
            if let current = games.first(where: { $0.id == currentGameId }) {
                hero(current)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 10) {
                    if sportSections.isEmpty {
                        Text("No other live games")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .padding(.horizontal)
                    }
                    ForEach(sportSections) { section in
                        sportChip(section)
                        if !collapsedSports.contains(section.sportKey) {
                            ForEach(section.leagues) { league in
                                leagueChip(league)
                                if !collapsedLeagues.contains(league.key) {
                                    ForEach(sortedGames(league.games)) { g in
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
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Hierarchy chips

    private func sportChip(_ section: StripSportSection) -> some View {
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
            .background(SportsColors.voidBlack.opacity(0.8))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SportsColors.gold.opacity(collapsed ? 0.25 : 0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .background(SportsColors.panel.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SportsColors.border.opacity(collapsed ? 0.35 : 0.7), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .background(SportsColors.panelElevated.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrent ? SportsColors.live : SportsColors.border, lineWidth: isCurrent ? 1.8 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private func sortedGames(_ games: [Game]) -> [Game] {
        games.sorted { a, b in
            let aNow = a.id == currentGameId ? 0 : 1
            let bNow = b.id == currentGameId ? 0 : 1
            if aNow != bNow { return aNow < bNow }
            let aLp = lastPlayedRank(a.id)
            let bLp = lastPlayedRank(b.id)
            if aLp != bLp { return aLp < bLp }
            return a.startTime < b.startTime
        }
    }

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

    private func isFav(_ g: Game) -> Bool {
        favoriteTeamIds.contains(g.home.id) || favoriteTeamIds.contains(g.away.id)
    }

    private func lastPlayedRank(_ id: String) -> Int {
        lastPlayedGameIds.firstIndex(of: id) ?? 9999
    }
}

// MARK: - Strip model

private struct StripSportSection: Identifiable {
    var id: String { sportKey }
    let sportKey: String
    let sportTitle: String
    let emoji: String
    var leagues: [LeagueShelf]
}
