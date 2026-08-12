import SwiftUI

#if os(tvOS)

/// Netflix-style focusable game card for Apple TV Scores browse.
struct ScoresTVGameCard: View {
    let game: Game
    var isFavoriteMatch: Bool = false
    var onSelect: () -> Void

    private let cardWidth: CGFloat = 340
    private let cardHeight: CGFloat = 200

    var body: some View {
        Button(action: onSelect) {
            SportsTVFocused { focused in
                cardChrome(focused: focused)
            }
        }
        .sportsTVFocusClean()
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens game details and streams")
    }

    private var accessibilityText: String {
        "\(game.away.rowLabel) \(game.away.displayScore) at \(game.home.rowLabel) \(game.home.displayScore). \(game.statusLine)"
    }

    private func cardChrome(focused: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                teamBlock(game.away, score: game.isLive || game.isFinal ? game.away.displayScore : nil)
                Spacer(minLength: 4)
                VStack(spacing: 6) {
                    Text(game.statusLine)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(game.isLive ? SportsColors.live : SportsColors.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("WATCH")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(SportsColors.voidBlack)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SportsColors.gold, in: Capsule())
                }
                Spacer(minLength: 4)
                teamBlock(game.home, score: game.isLive || game.isFinal ? game.home.displayScore : nil)
            }

            Text(game.matchupLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.muted)
                .lineLimit(1)
        }
        .padding(16)
        .frame(width: cardWidth, height: cardHeight)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(focused ? SportsColors.panelElevated : SportsColors.panel)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    focused ? SportsColors.gold : (isFavoriteMatch ? SportsColors.gold.opacity(0.45) : SportsColors.border.opacity(0.35)),
                    lineWidth: focused ? 3 : (isFavoriteMatch ? 1.5 : 1)
                )
        }
        .overlay(alignment: .topTrailing) {
            if isFavoriteMatch {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SportsColors.gold)
                    .padding(10)
            }
        }
        .scaleEffect(focused ? 1.06 : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        .shadow(color: focused ? SportsColors.gold.opacity(0.35) : .clear, radius: 18, y: 8)
    }

    private func teamBlock(_ team: TeamInfo, score: String?) -> some View {
        VStack(spacing: 6) {
            teamLogo(team)
            Text(team.rowLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(SportsColors.text)
                .lineLimit(1)
                .frame(maxWidth: 110)
            if let score {
                Text(score)
                    .font(.title.weight(.heavy))
                    .foregroundStyle(SportsColors.text)
                    .monospacedDigit()
            }
        }
        .frame(minWidth: 100)
    }

    @ViewBuilder
    private func teamLogo(_ team: TeamInfo) -> some View {
        let size: CGFloat = 52
        if let urlStr = team.logoURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                default:
                    logoFallback(team, size: size)
                }
            }
            .frame(width: size, height: size)
        } else {
            logoFallback(team, size: size)
        }
    }

    private func logoFallback(_ team: TeamInfo, size: CGFloat) -> some View {
        Text(team.abbreviation.prefix(3).uppercased())
            .font(.caption.weight(.black))
            .foregroundStyle(SportsColors.gold)
            .frame(width: size, height: size)
            .background(SportsColors.voidBlack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Horizontal Netflix-style rail of game cards.
struct ScoresTVRail: View {
    let title: String
    var emoji: String? = nil
    let games: [Game]
    var favoriteTeamIds: Set<String> = []
    var onSelect: (Game) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let emoji, !emoji.isEmpty {
                    Text(emoji).font(.title3)
                }
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(SportsColors.text)
                if games.contains(where: \.isLive) {
                    Text("LIVE")
                        .font(.caption.weight(.black))
                        .foregroundStyle(SportsColors.live)
                }
                Text("\(games.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SportsColors.muted)
            }
            .padding(.horizontal, 48)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                    ForEach(games) { game in
                        ScoresTVGameCard(
                            game: game,
                            isFavoriteMatch: favoriteTeamIds.contains(game.home.id)
                                || favoriteTeamIds.contains(game.away.id),
                            onSelect: { onSelect(game) }
                        )
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 12)
            }
            .focusSection()
        }
    }
}

#endif
