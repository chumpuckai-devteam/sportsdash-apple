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
                .navigationBarTitleDisplayMode(.large)
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await appModel.refreshScores() }
                        } label: {
                            if appModel.isLoadingScores {
                                ProgressView().controlSize(.small).tint(SportsColors.gold)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(appModel.isLoadingScores)
                        .sportsToolbarControl()
                    }
                }
                .sheet(item: $selectedGame) { game in
                    GameDetailSheet(game: game)
                        .environmentObject(appModel)
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(.ultraThinMaterial)
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
            #if os(iOS)
            .refreshable { await appModel.refreshScores() }
            #endif
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
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let updated = appModel.lastUpdated {
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SportsColors.muted)
                            .padding(.horizontal)
                    }

                    if showFaves {
                        shelfSection(
                            title: "Faves",
                            games: appModel.favoriteGames,
                            goldTitle: true
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
                                sportHeader(section.sportTitle)
                            }
                            shelfSection(
                                title: section.title,
                                games: section.games,
                                goldTitle: false
                            )
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            #if os(iOS)
            // Must be on the ScrollView itself — not NavigationStack/ZStack — for pull-to-refresh
            .refreshable {
                await appModel.refreshScores()
            }
            #endif
        }
    }

    /// Apple-style filter chips with glass unselected state.
    private var filterBar: some View {
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
        .background {
            Rectangle()
                .fill(.clear)
                .background(.bar)
                .opacity(0.001) // let system nav material show through when scrolling
        }
    }

    private func sportHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(SportsColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func shelfSection(
        title: String,
        games: [Game],
        goldTitle: Bool
    ) -> some View {
        let live = games.filter(\.isLive).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SportsMetrics.gridGutter) {
                    ForEach(games) { game in
                        GameCardView(
                            game: game,
                            isFavorite: appModel.isFavorite(game),
                            onTap: { selectedGame = game },
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
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            #if os(iOS)
            .scrollTargetBehavior(.viewAligned)
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
        case .favorites: return "Star teams on a matchup card to build your Faves row."
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
