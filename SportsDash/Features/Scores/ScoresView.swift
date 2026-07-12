import SwiftUI

struct ScoresView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                SportsColors.voidBlack.ignoresSafeArea()
                Group {
                    if appModel.isLoadingScores && appModel.games.isEmpty {
                        ProgressView()
                            .tint(SportsColors.gold)
                    } else if let err = appModel.scoresError, appModel.games.isEmpty {
                        ContentUnavailableView(
                            "Scores unavailable",
                            systemImage: "wifi.exclamationmark",
                            description: Text(err)
                        )
                    } else {
                        scoresList
                    }
                }
            }
            .navigationTitle("Scores")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await appModel.refreshScores() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appModel.isLoadingScores)
                }
            }
            #if os(iOS)
            .refreshable {
                await appModel.refreshScores()
            }
            #endif
        }
    }

    private var scoresList: some View {
        let sections = ScoreboardGrouping.leagueShelves(from: appModel.games)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                if let updated = appModel.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                        .padding(.horizontal)
                }

                ForEach(sections) { section in
                    if section.showSportHeader {
                        sportHeader(section.sportTitle, emoji: section.sportEmoji)
                    }
                    leagueShelf(section)
                }
            }
            .padding(.vertical)
        }
    }

    private func sportHeader(_ title: String, emoji: String) -> some View {
        HStack(spacing: 8) {
            Text(emoji)
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .tracking(1.4)
                .foregroundStyle(SportsColors.gold)
            Rectangle()
                .fill(SportsColors.border)
                .frame(height: 1)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func leagueShelf(_ section: LeagueShelf) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(section.emoji)  \(section.title)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SportsColors.text)
                Spacer()
                Text("\(section.games.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SportsColors.muted)
                if section.liveCount > 0 {
                    Text("\(section.liveCount) LIVE")
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
                    ForEach(section.games) { game in
                        GameCardView(game: game)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct LeagueShelf: Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var emoji: String
    var sportKey: String
    var sportTitle: String
    var sportEmoji: String
    var showSportHeader: Bool
    var games: [Game]
    var liveCount: Int { games.filter(\.isLive).count }
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
                    emoji: league.emoji,
                    sportKey: sport,
                    sportTitle: league.sportSectionTitle,
                    sportEmoji: league.emoji,
                    showSportHeader: showHeader,
                    games: list
                )
            )
        }
        return shelves
    }
}
