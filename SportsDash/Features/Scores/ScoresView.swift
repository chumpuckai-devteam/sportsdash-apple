import SwiftUI

struct ScoresView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedGame: Game?

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
                                // Icon only — Label truncates badly in the TV toolbar ("R…sh")
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
                ContentUnavailableView(
                    "Scores unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: Text(err)
                )
                .frame(maxWidth: .infinity, minHeight: 400)
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
        let shelves: [LeagueShelf] = appModel.dashboardFilter == .favorites
            ? []
            : ScoreboardGrouping.leagueShelves(from: appModel.filteredGames)

        return VStack(spacing: 0) {
            filterBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if let updated = appModel.lastUpdated {
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SportsColors.muted)
                            .padding(.horizontal, 16)
                    }

                    if showFaves {
                        leagueBlock(
                            title: "My teams",
                            systemImage: "star.fill",
                            goldTitle: true,
                            games: appModel.favoriteGames
                        )
                    }

                    if shelves.isEmpty && !showFaves {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: "sportscourt",
                            description: Text(emptySubtitle)
                        )
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        ForEach(shelves) { section in
                            if section.showSportHeader {
                                Text(section.sportTitle)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(SportsColors.text)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 4)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            leagueBlock(
                                title: section.title,
                                systemImage: nil,
                                goldTitle: false,
                                games: section.games
                            )
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.bottom, 28)
            }
            .sportsRefreshable { await appModel.refreshScores() }
        }
    }

    private var filterBar: some View {
        #if os(tvOS)
        // No horizontal ScrollView — plain chips inside ScrollView often can't take focus on tvOS.
        HStack(spacing: 16) {
            ForEach(DashboardFilter.allCases) { f in
                let liveCount = appModel.games.filter(\.isLive).count
                SportsFilterChip(
                    title: f.label,
                    count: f == .live ? liveCount : nil,
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
                    SportsFilterChip(
                        title: f.label,
                        count: f == .live ? liveCount : nil,
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
                        .foregroundStyle(SportsColors.gold)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(goldTitle ? SportsColors.gold : SportsColors.textSecondary)
                Spacer()
                if live > 0 {
                    Text("\(live) Live")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SportsColors.live)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

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
            // Inset + max width so focus scale doesn't clip at screen edges
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 48)
            #else
            .sportsSoftSurface(radius: 22)
            .padding(.horizontal, 12)
            #endif
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
        case .favorites: return "Star a team on a matchup to build My teams."
        default: return "Pull to refresh or try another filter."
        }
    }
}

struct LeagueShelf: Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var sportKey: String
    var sportTitle: String
    var showSportHeader: Bool
    var games: [Game]
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
}
