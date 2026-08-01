import SwiftUI

struct ScoresView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedGame: Game?
    /// Collapsed sport section keys (`soccer`, `baseball`, …) — same idea as `LiveScoresStrip`.
    @State private var collapsedSports: Set<String> = []
    @State private var showLeaguesSettings = false

    var body: some View {
        NavigationStack {
            scoresRoot
                .sportsScreenBackground()
                .navigationTitle("Scores")
                #if os(iOS)
                .sportsNavTitleMode(large: true)
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await appModel.refreshScores() }
                        } label: {
                            if appModel.isLoadingScores {
                                ProgressView().controlSize(.small).tint(SportsColors.gold)
                            } else {
                                #if os(tvOS)
                                Image(systemName: "arrow.clockwise")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(SportsColors.gold)
                                    .accessibilityLabel("Refresh")
                                #else
                                Label("Refresh", systemImage: "arrow.clockwise")
                                #endif
                            }
                        }
                        .disabled(appModel.isLoadingScores)
                        .sportsToolbarControl()
                    }
                }
                .sheet(item: $selectedGame) { game in
                    GameDetailSheet(game: game)
                        .environmentObject(appModel)
                        .sportsSheetChrome()
                }
                #if os(iOS)
                .navigationDestination(isPresented: $showLeaguesSettings) {
                    ScoresSettingsView()
                }
                #endif
        }
    }

    @ViewBuilder
    private var scoresRoot: some View {
        if appModel.isLoadingScores && appModel.games.isEmpty {
            ProgressView()
                .tint(SportsColors.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = appModel.scoresError, appModel.games.isEmpty {
            ScrollView {
                VStack(spacing: 22) {
                    if SetupChecklist.isIncomplete(appModel) {
                        SetupChecklistCard()
                            .padding(.horizontal, 16)
                    }
                    ContentUnavailableView(
                        "Scores unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(err)
                    )
                    .frame(maxWidth: .infinity, minHeight: SetupChecklist.isIncomplete(appModel) ? 240 : 320)
                }
                .padding(.vertical, 12)
            }
            .sportsRefreshable { await appModel.refreshScores() }
        } else {
            scoresContent
        }
    }

    private var scoresContent: some View {
        let showFaves = !appModel.favoriteGames.isEmpty
            && (appModel.dashboardFilter == .all
                || appModel.dashboardFilter == .live
                || appModel.dashboardFilter == .upcoming
                || appModel.dashboardFilter == .favorites)
        let sections: [SportScoreSection] = appModel.dashboardFilter == .favorites
            ? []
            : Self.buildSections(
                games: appModel.filteredGames,
                filter: appModel.dashboardFilter,
                selectedLeagues: appModel.selectedLeagues
            )

        return VStack(spacing: 0) {
            filterBar
            scoresContextStrip
                .padding(.bottom, 4)
            Divider().overlay(SportsColors.border.opacity(0.35))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if SetupChecklist.isIncomplete(appModel) {
                        SetupChecklistCard()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    if showFaves {
                        leagueBlock(
                            title: "My teams",
                            systemImage: "star.fill",
                            goldTitle: true,
                            games: appModel.favoriteGames
                        )
                    }

                    if sections.isEmpty && !showFaves {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: "sportscourt",
                            description: Text(emptySubtitle)
                        )
                        .frame(maxWidth: .infinity, minHeight: SetupChecklist.isIncomplete(appModel) ? 180 : 280)
                    } else {
                        ForEach(sections) { section in
                            sportSectionBlock(section)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.bottom, 28)
            }
            .sportsRefreshable { await appModel.refreshScores() }
        }
    }

    /// Leagues summary + updated time + edit entry (P0.2).
    private var scoresContextStrip: some View {
        let leagues = appModel.selectedLeagues.isEmpty
            ? SportLeague.defaults
            : appModel.selectedLeagues
        let labels = leagues.map(\.label)
        let summary: String = {
            if labels.isEmpty { return "No leagues selected" }
            if labels.count <= 3 { return labels.joined(separator: " · ") }
            return labels.prefix(3).joined(separator: " · ") + " +\(labels.count - 3)"
        }()

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SportsColors.textSecondary)
                    .lineLimit(1)
                if appModel.isLoadingScores {
                    Text("Updating scores…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SportsColors.gold)
                } else if let updated = appModel.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SportsColors.muted)
                } else {
                    Text("Pull to refresh")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SportsColors.muted)
                }
            }
            Spacer(minLength: 8)
            #if os(iOS)
            Button {
                showLeaguesSettings = true
            } label: {
                Text("Leagues")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SportsColors.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .sportsGlass(in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit leagues")
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(SportsColors.voidBlack.opacity(0.92))
    }

    /// Group games by sport → league; on Upcoming, keep empty shelves for selected
    /// leagues so MLB (etc.) never "disappears" when the slate is quiet.
    private static func buildSections(
        games: [Game],
        filter: DashboardFilter,
        selectedLeagues: [SportLeague]
    ) -> [SportScoreSection] {
        var sections = ScoreboardGrouping.sportSections(from: games)
        guard filter == .upcoming else { return sections }

        let selected = selectedLeagues.isEmpty ? SportLeague.defaults : selectedLeagues
        let present = Set(sections.flatMap { $0.leagues.map(\.key) })
        let missing = selected.filter { !present.contains($0.rawValue) }
        guard !missing.isEmpty else { return sections }

        // Attach empty league shelves under the right sport bucket.
        for league in ScoreboardGrouping.leagueOrder where missing.contains(league) {
            let emptyShelf = LeagueShelf(
                key: league.rawValue,
                title: league.label,
                sportKey: league.sportPath,
                sportTitle: league.sportSectionTitle,
                showSportHeader: true,
                games: []
            )
            if let idx = sections.firstIndex(where: { $0.sportKey == league.sportPath }) {
                if !sections[idx].leagues.contains(where: { $0.key == league.rawValue }) {
                    sections[idx].leagues.append(emptyShelf)
                }
            } else {
                sections.append(
                    SportScoreSection(
                        sportKey: league.sportPath,
                        sportTitle: league.sportSectionTitle,
                        emoji: league.emoji,
                        leagues: [emptyShelf]
                    )
                )
            }
        }
        // Keep sport order stable (first appearance in leagueOrder).
        let sportOrder = ScoreboardGrouping.leagueOrder.map(\.sportPath)
        sections.sort { a, b in
            let ia = sportOrder.firstIndex(of: a.sportKey) ?? 999
            let ib = sportOrder.firstIndex(of: b.sportKey) ?? 999
            return ia < ib
        }
        return sections
    }

    // MARK: - Sport → league hierarchy (collapsible sports)

    @ViewBuilder
    private func sportSectionBlock(_ section: SportScoreSection) -> some View {
        let collapsed = collapsedSports.contains(section.sportKey)
        VStack(alignment: .leading, spacing: 14) {
            sportHeader(section, collapsed: collapsed)
            if !collapsed {
                ForEach(section.leagues) { shelf in
                    leagueBlock(
                        title: shelf.title,
                        systemImage: nil,
                        goldTitle: false,
                        games: shelf.games
                    )
                }
            }
        }
    }

    private func sportHeader(_ section: SportScoreSection, collapsed: Bool) -> some View {
        let gameCount = section.leagues.reduce(0) { $0 + $1.games.count }
        let liveCount = section.leagues.reduce(0) { $0 + $1.games.filter(\.isLive).count }

        return Button {
            toggleSport(section.sportKey)
        } label: {
            #if os(tvOS)
            SportsTVFocused { focused in
                sportHeaderLabel(section, collapsed: collapsed, liveCount: liveCount, gameCount: gameCount, focused: focused)
            }
            #else
            sportHeaderLabel(section, collapsed: collapsed, liveCount: liveCount, gameCount: gameCount, focused: false)
            #endif
        }
        #if os(tvOS)
        .sportsTVFocusClean()
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(section.sportTitle), \(gameCount) games")
        .accessibilityHint(collapsed ? "Expand sport" : "Collapse sport")
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func sportHeaderLabel(
        _ section: SportScoreSection,
        collapsed: Bool,
        liveCount: Int,
        gameCount: Int,
        focused: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Text(section.emoji)
                .font(.title3)
            Text(section.sportTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
            Spacer(minLength: 8)
            if liveCount > 0 {
                Text("\(liveCount) Live")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.75) : SportsColors.live)
            }
            Text("\(gameCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.7) : SportsColors.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((focused ? SportsColors.voidBlack.opacity(0.12) : SportsColors.panel.opacity(0.9)))
                .clipShape(Capsule())
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.7) : SportsColors.gold)
                .frame(width: 22, height: 22)
                .background(
                    (focused ? SportsColors.voidBlack.opacity(0.12) : SportsColors.gold.opacity(0.15)),
                    in: Circle()
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        #if os(iOS)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SportsColors.panel.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SportsColors.border.opacity(0.45), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        #endif
        #if os(tvOS)
        .frame(minHeight: SportsTVMetrics.minFocusSize)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(focused ? SportsColors.gold : Color.clear)
        }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SportsColors.goldDim, lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        .padding(.horizontal, SportsTVMetrics.scoreHorizontalInset - 16)
        #endif
        .contentShape(Rectangle())
    }

    private func toggleSport(_ key: String) {
        #if os(iOS)
        withAnimation(.snappy(duration: 0.22)) {
            if collapsedSports.contains(key) {
                collapsedSports.remove(key)
            } else {
                collapsedSports.insert(key)
            }
        }
        #else
        if collapsedSports.contains(key) {
            collapsedSports.remove(key)
        } else {
            collapsedSports.insert(key)
        }
        #endif
    }

    private var filterBar: some View {
        #if os(tvOS)
        // No horizontal ScrollView — plain chips inside ScrollView often can't take focus on tvOS.
        HStack(spacing: 16) {
            ForEach(DashboardFilter.allCases) { f in
                let liveCount = appModel.games.filter(\.isLive).count
                let upcomingCount = appModel.games.filter(\.isUpcoming).count
                SportsFilterChip(
                    title: f.label,
                    count: f == .live ? liveCount : (f == .upcoming ? upcomingCount : nil),
                    selected: appModel.dashboardFilter == f
                ) {
                    appModel.dashboardFilter = f
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .focusSection()
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DashboardFilter.allCases) { f in
                    let liveCount = appModel.games.filter(\.isLive).count
                    let upcomingCount = appModel.games.filter(\.isUpcoming).count
                    SportsFilterChip(
                        title: f.label,
                        count: f == .live ? liveCount : (f == .upcoming ? upcomingCount : nil),
                        selected: appModel.dashboardFilter == f
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            appModel.dashboardFilter = f
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        #endif
    }

    /// Borderless grouped list — soft surface, hairline dividers only (no per-card boxes).
    private func leagueBlock(
        title: String,
        systemImage: String?,
        goldTitle: Bool,
        games: [Game]
    ) -> some View {
        let live = games.filter(\.isLive).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SportsColors.gold)
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(goldTitle ? SportsColors.gold : SportsColors.muted)
                    .textCase(goldTitle ? nil : .uppercase)
                    .tracking(goldTitle ? 0 : 0.6)
                Spacer()
                if live > 0 {
                    Text("\(live) Live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SportsColors.live)
                } else if games.isEmpty {
                    Text("None scheduled")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SportsColors.muted)
                } else {
                    Text("\(games.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SportsColors.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .padding(.top, 2)

            if games.isEmpty {
                Text("No upcoming games in the next week for this league.")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 12) {
                    ForEach(games) { game in
                        GameScoreFocusRow(
                            game: game,
                            isFavorite: appModel.isFavorite(game),
                            onSelect: { selectedGame = game },
                            onFavorite: {
                                if !game.home.id.isEmpty {
                                    appModel.toggleFavorite(teamId: game.home.id)
                                }
                                if !game.away.id.isEmpty {
                                    appModel.toggleFavorite(teamId: game.away.id)
                                }
                            }
                        )
                    }
                }
                #if os(tvOS)
                .frame(maxWidth: SportsTVMetrics.scoreCardMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SportsTVMetrics.scoreHorizontalInset)
                .focusSection()
                #else
                .sportsSoftSurface(radius: 22)
                .padding(.horizontal, 12)
                #endif
            }
        }
    }

    private var emptyTitle: String {
        switch appModel.dashboardFilter {
        case .live: return "No live games"
        case .upcoming: return "No upcoming games"
        case .favorites: return "No favorite games"
        case .all: return "No games"
        }
    }

    private var emptySubtitle: String {
        switch appModel.dashboardFilter {
        case .favorites:
            return "Star a team on a matchup to build My teams."
        case .upcoming:
            let leagues = appModel.selectedLeagues.isEmpty
                ? SportLeague.defaults
                : appModel.selectedLeagues
            let labels = leagues.prefix(4).map(\.label).joined(separator: ", ")
            let more = leagues.count > 4 ? " +\(leagues.count - 4) more" : ""
            return "No scheduled games in the next few days for \(labels)\(more). Pull to refresh or adjust leagues in Settings."
        case .live:
            return "Nothing in progress right now. Check Upcoming or pull to refresh."
        case .all:
            return "Pull to refresh or enable more leagues in Settings."
        }
    }
}

// MARK: - Grouping models

struct LeagueShelf: Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var sportKey: String
    var sportTitle: String
    var showSportHeader: Bool
    var games: [Game]
}

/// Sport bucket used by Scores dashboard collapse (and shared strip grouping).
struct SportScoreSection: Identifiable {
    var id: String { sportKey }
    let sportKey: String
    let sportTitle: String
    let emoji: String
    var leagues: [LeagueShelf]
}

enum ScoreboardGrouping {
    static let leagueOrder: [SportLeague] = SportLeague.allCases

    static func leagueShelves(from games: [Game]) -> [LeagueShelf] {
        var buckets: [SportLeague: [Game]] = [:]
        for g in games {
            buckets[g.league, default: []].append(g)
        }
        for k in buckets.keys {
            buckets[k]?.sort {
                if $0.isLive != $1.isLive { return $0.isLive && !$1.isLive }
                return $0.startTime < $1.startTime
            }
        }
        var shelves: [LeagueShelf] = []
        var lastSport: String?
        for league in leagueOrder {
            guard let list = buckets[league], !list.isEmpty else { continue }
            let sport = league.sportPath
            let showHeader = sport != lastSport
            lastSport = sport
            shelves.append(
                LeagueShelf(
                    key: league.rawValue,
                    title: league.label,
                    sportKey: sport,
                    sportTitle: league.sportSectionTitle,
                    showSportHeader: showHeader,
                    games: list
                )
            )
        }
        return shelves
    }

    /// Collapse consecutive league shelves into sport → league sections.
    static func sportSections(from games: [Game]) -> [SportScoreSection] {
        let shelves = leagueShelves(from: games)
        var sections: [SportScoreSection] = []
        var current: SportScoreSection?
        for shelf in shelves {
            if current?.sportKey != shelf.sportKey {
                if let current { sections.append(current) }
                current = SportScoreSection(
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
}
