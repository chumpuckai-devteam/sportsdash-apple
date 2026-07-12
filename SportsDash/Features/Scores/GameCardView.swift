import SwiftUI

struct GameCardView: View {
    let game: Game
    var isFavorite: Bool = false
    var onTap: () -> Void
    var onFavorite: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if game.isLive {
                        Text("LIVE")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(SportsColors.live)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SportsColors.live.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(game.statusLine)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(game.isLive ? SportsColors.live : SportsColors.textSecondary)
                    Spacer()
                    if game.usesMatchupLayout, let onFavorite {
                        Button(action: onFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .foregroundStyle(isFavorite ? SportsColors.gold : SportsColors.muted)
                        }
                        .buttonStyle(.plain)
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

                HStack {
                    Text(game.broadcasts.prefix(2).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(SportsColors.muted)
                        .lineLimit(1)
                    Spacer()
                    Text("WATCH")
                        .font(.caption.weight(.black))
                        .foregroundStyle(SportsColors.voidBlack)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SportsColors.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(12)
            .frame(width: 280, height: 160, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [SportsColors.panelElevated, SportsColors.panel],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        game.isLive ? SportsColors.live.opacity(0.4) : SportsColors.border,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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
