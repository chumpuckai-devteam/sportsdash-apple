import SwiftUI

struct GameCardView: View {
    let game: Game
    var isFavorite: Bool = false
    var onTap: () -> Void
    var onFavorite: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if game.isLive {
                        SportsLiveBadge()
                    }
                    Text(game.statusLine)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(game.isLive ? SportsColors.live : SportsColors.textSecondary)
                    Spacer(minLength: 4)
                    if game.usesMatchupLayout, let onFavorite {
                        Button(action: onFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(isFavorite ? SportsColors.gold : SportsColors.muted)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
                    }
                }

                if game.usesMatchupLayout {
                    teamRow(game.away)
                    teamRow(game.home)
                } else {
                    Text(game.eventName ?? game.league.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SportsColors.text)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(game.broadcasts.prefix(2).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(SportsColors.muted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    SportsWatchBadge()
                }
            }
            .padding(SportsMetrics.cardPadding)
            .frame(width: 288, height: 164, alignment: .topLeading)
            .sportsContentCard(emphasized: game.isLive)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens game details and streams")
    }

    private func teamRow(_ team: TeamInfo) -> some View {
        HStack {
            Text(team.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SportsColors.text)
                .lineLimit(1)
            Spacer()
            if game.isLive || game.isFinal {
                Text(team.displayScore)
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(SportsColors.text)
            }
        }
    }
}
