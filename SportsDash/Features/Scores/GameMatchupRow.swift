import SwiftUI

// MARK: - Team color accents (inspired by sports score UIs — not Apple Sports assets)

/// Stable, brand-free accent colors derived from team identity for gradients.
/// Avoids hard-coding league palettes or copying third-party app art.
enum TeamTheme {
    static func accent(for team: TeamInfo) -> Color {
        let key = (team.id.isEmpty ? team.name : team.id).lowercased()
        var hash: UInt64 = 5381
        for b in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(b)
        }
        // Prefer deep, saturated hues that read on dark sports UI
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.62, brightness: 0.42)
    }

    static func pairGradient(away: TeamInfo, home: TeamInfo) -> LinearGradient {
        LinearGradient(
            colors: [
                accent(for: away).opacity(0.95),
                SportsColors.voidBlack.opacity(0.92),
                accent(for: home).opacity(0.85),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func heroGradient(away: TeamInfo, home: TeamInfo) -> LinearGradient {
        LinearGradient(
            colors: [
                accent(for: away),
                Color.black.opacity(0.55),
                accent(for: home).opacity(0.75),
                Color.black.opacity(0.95),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Team logo / monogram

struct TeamMarkView: View {
    let team: TeamInfo
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let raw = team.logoURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        Text(String(team.abbreviation.prefix(3)))
            .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
            .foregroundStyle(SportsColors.text)
            .frame(width: size, height: size)
            .background(TeamTheme.accent(for: team).opacity(0.55), in: Circle())
    }
}

// MARK: - Dashboard matchup row (list style — no card border)

/// Vertical scoreboard row inspired by modern sports apps: marks + big scores + center status.
struct GameMatchupRow: View {
    let game: Game
    var isFavorite: Bool = false
    var onFavorite: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if game.usesMatchupLayout {
                side(team: game.away, score: game.away.displayScore, align: .leading)
                centerStatus
                side(team: game.home, score: game.home.displayScore, align: .trailing)
            } else {
                eventLayout
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func side(team: TeamInfo, score: String, align: HorizontalAlignment) -> some View {
        HStack(spacing: 10) {
            if align == .leading {
                favoriteStar(leading: true)
                TeamMarkView(team: team, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SportsColors.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                scoreText(score, dimmed: losing(team))
            } else {
                scoreText(score, dimmed: losing(team))
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(team.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SportsColors.text)
                        .lineLimit(1)
                }
                TeamMarkView(team: team, size: 40)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var centerStatus: some View {
        VStack(spacing: 4) {
            if game.isLive {
                SportsLiveBadge()
            }
            Text(game.statusLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(game.isLive ? SportsColors.live : SportsColors.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minWidth: 72, maxWidth: 88)
        }
    }

    private var eventLayout: some View {
        HStack(spacing: 12) {
            favoriteStar(leading: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.eventName ?? game.league.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SportsColors.text)
                    .lineLimit(2)
                Text(game.statusLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(game.isLive ? SportsColors.live : SportsColors.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.muted)
        }
    }

    @ViewBuilder
    private func favoriteStar(leading: Bool) -> some View {
        if let onFavorite {
            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isFavorite ? SportsColors.gold : SportsColors.muted.opacity(0.7))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    private func scoreText(_ score: String, dimmed: Bool) -> some View {
        Text(score)
            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(dimmed ? SportsColors.muted : SportsColors.text)
    }

    private func losing(_ team: TeamInfo) -> Bool {
        guard game.isFinal || game.isLive,
              let a = game.away.score,
              let h = game.home.score,
              a != h
        else { return false }
        if team.id == game.away.id { return a < h }
        if team.id == game.home.id { return h < a }
        return false
    }
}

// MARK: - Content card without borders (material only)

extension View {
    /// Soft material surface — no stroke (Apple Sports–like list grouping).
    func sportsSoftSurface(radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(SportsColors.panelElevated.opacity(0.25))
                    }
            }
            .clipShape(shape)
    }
}
