import SwiftUI

struct ScoresView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedGame: Game?

    var body: some View {
        NavigationStack {
            scoresRoot
                .background(SportsColors.voidBlack)
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
                                ProgressView().tint(SportsColors.gold)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(appModel.isLoadingScores)
                    }
                }
                .sheet(item: $selectedGame) { game in
                    GameDetailSheet(game: game)
                        .environmentObject(appModel)
                        // Large first so streams are visible without scrolling the header away
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)
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
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .padding(.horizontal)
                    }

                    if showFaves {
                        shelfSection(
                            title: "Faves",
                            emoji: "★",
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
                                sportHeader(section.sportTitle, emoji: section.sportEmoji)
                            }
                            shelfSection(
                                title: section.title,
                                emoji: section.emoji,
                                games: section.games,
                                goldTitle: false
                            )
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            #if os(iOS)
            // Must be on the ScrollView itself — not NavigationStack/ZStack — for pull-to-refresh
            .refreshable {
                await appModel.refreshScores()
            }
            #endif
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DashboardFilter.allCases) { f in
                    let selected = appModel.dashboardFilter == f
                    let liveCount = appModel.games.filter(\.isLive).count
                    Button {
                        appModel.dashboardFilter = f
                    } label: {
                        HStack(spacing: 6) {
                            Text(f.label)
                                .font(.caption.weight(.black))
                            if f == .live, liveCount > 0 {
                                Text("\(liveCount)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(SportsColors.live.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundStyle(selected ? SportsColors.voidBlack : SportsColors.muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selected ? SportsColors.gold : SportsColors.panelElevated)
                        .overlay(
                            Capsule().stroke(
                                selected ? SportsColors.gold : SportsColors.border,
                                lineWidth: 1
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(SportsColors.voidBlack)
        .overlay(alignment: .bottom) {
            Divider().background(SportsColors.border)
        }
    }

    /// Sport section label (e.g. BASEBALL, SOCCER) — no emoji.
    private func sportHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .tracking(1.6)
                .foregroundStyle(SportsColors.gold)
            Rectangle().fill(SportsColors.border).frame(height: 1)
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    /// League sub-row (e.g. MLB, World Cup, Premier League) — no emoji.
    private func shelfSection(
        title: String,
        games: [Game],
        goldTitle: Bool
    ) -> some View {
        let live = games.filter(\.isLive).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(goldTitle ? SportsColors.gold : SportsColors.text)
                Spacer()
                Text("\(games.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SportsColors.muted)
                if live > 0 {
                    Text("\(live) LIVE")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(SportsColors.live)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SportsColors.live.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
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
        case .favorites: return "Star teams on a matchup card to build your Faves row."
        default: return "Pull to refresh or try another filter."
        }
    }
}

struct LeagueShelf: Identifiable {
    var id: String { key }
    /// League key (e.g. mlb, worldcup).
    var key: String
    /// League display name (sub-row).
    var title: String
    /// Sport path for grouping (soccer, baseball, …).
    var sportKey: String
    /// Sport section title (Soccer, Baseball, …).
    var sportTitle: String
    /// First league under a sport gets the section header.
    var showSportHeader: Bool
    var games: [Game]
}

enum ScoreboardGrouping {
    /// Preferred league order within sports (sport sections follow first league appearance).
    static let leagueOrder: [SportLeague] = SportLeague.allCases

    /// Sport sections with league sub-rows: Soccer → World Cup, UCL, EPL, …
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
