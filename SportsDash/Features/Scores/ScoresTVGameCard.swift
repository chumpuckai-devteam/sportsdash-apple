import SwiftUI

#if os(tvOS)

/// Netflix-style focusable game card for Apple TV Scores browse.
struct ScoresTVGameCard: View {
    let game: Game
    var isFavoriteMatch: Bool = false
    var onSelect: () -> Void

    /// Wide enough for logos + fixed center WATCH band + scores.
    private let cardWidth: CGFloat = 400
    private let cardHeight: CGFloat = 228
    /// Dedicated center column — never squeeze WATCH into a vertical stack of letters.
    private let centerBand: CGFloat = 128

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

    private var showScores: Bool { game.isLive || game.isFinal }

    private func cardChrome(focused: Bool) -> some View {
        VStack(spacing: 12) {
            // Top: teams + center status/WATCH (fixed widths so WATCH never collapses)
            HStack(alignment: .top, spacing: 10) {
                teamColumn(game.away)
                    .frame(maxWidth: .infinity)

                centerStatusBand
                    .frame(width: centerBand)

                teamColumn(game.home)
                    .frame(maxWidth: .infinity)
            }

            // Scores row — full breathing room under logos (not jammed in center)
            if showScores {
                HStack {
                    Text(game.away.displayScore)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(SportsColors.text)
                        .frame(maxWidth: .infinity)
                    Text("–")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SportsColors.muted)
                    Text(game.home.displayScore)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(SportsColors.text)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)
            }

            Text(game.matchupLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
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
                    .padding(12)
            }
        }
        .scaleEffect(focused ? 1.05 : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        .shadow(color: focused ? SportsColors.gold.opacity(0.35) : .clear, radius: 18, y: 8)
    }

    /// Status + WATCH with guaranteed horizontal room.
    private var centerStatusBand: some View {
        VStack(spacing: 10) {
            Text(game.statusLine)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(game.isLive ? SportsColors.live : SportsColors.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)

            Text("WATCH")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(SportsColors.voidBlack)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(SportsColors.gold, in: Capsule(style: .continuous))
                .fixedSize(horizontal: true, vertical: true)
        }
        .frame(width: centerBand)
    }

    private func teamColumn(_ team: TeamInfo) -> some View {
        VStack(spacing: 8) {
            teamLogo(team)
            Text(team.rowLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(SportsColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func teamLogo(_ team: TeamInfo) -> some View {
        let size: CGFloat = 56
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
                LazyHStack(spacing: 24) {
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
                .padding(.vertical, 14)
            }
            .focusSection()
        }
    }
}

#endif
