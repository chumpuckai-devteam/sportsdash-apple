import SwiftUI

/// Player overlay: sport-grouped live cards, last-played sort, manual scroll.
struct LiveScoresStrip: View {
    let games: [Game]
    var currentGameId: String?
    var favoriteTeamIds: Set<String> = []
    var lastPlayedGameIds: [String] = []
    var onGameTap: (Game) -> Void

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

    private var groups: [(sport: String, title: String, emoji: String, games: [Game])] {
        var order: [String] = []
        var map: [String: [Game]] = [:]
        var titles: [String: String] = [:]
        var emojis: [String: String] = [:]
        for g in liveOrdered {
            let key = g.league.sportPath
            if map[key] == nil {
                order.append(key)
                titles[key] = g.league.sportSectionTitle
                emojis[key] = g.league.emoji
                map[key] = []
            }
            map[key]?.append(g)
        }
        return order.map { (sport: $0, title: titles[$0]!, emoji: emojis[$0]!, games: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 6) {
            if let current = games.first(where: { $0.id == currentGameId }) {
                hero(current)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 10) {
                    if groups.isEmpty {
                        Text("No other live games")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .padding(.horizontal)
                    }
                    ForEach(groups, id: \.sport) { group in
                        sportHeader(group.emoji, group.title, count: group.games.count)
                        ForEach(group.games) { g in
                            card(g)
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

    private func hero(_ game: Game) -> some View {
        VStack(spacing: 2) {
            Text("\(game.league.emoji)  \(game.league.sportSectionTitle.uppercased())  ·  \(game.league.label)")
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

    private func sportHeader(_ emoji: String, _ title: String, count: Int) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.title3)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(SportsColors.gold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(SportsColors.muted)
        }
        .frame(width: 68, height: 104)
        .background(SportsColors.voidBlack.opacity(0.75))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SportsColors.gold.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private func isFav(_ g: Game) -> Bool {
        favoriteTeamIds.contains(g.home.id) || favoriteTeamIds.contains(g.away.id)
    }

    private func lastPlayedRank(_ id: String) -> Int {
        lastPlayedGameIds.firstIndex(of: id) ?? 9999
    }
}
