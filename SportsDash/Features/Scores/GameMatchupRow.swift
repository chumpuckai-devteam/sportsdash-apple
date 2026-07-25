import SwiftUI

// MARK: - Team colors (ESPN hex when present; stable fallback)

enum TeamTheme {
    static func accent(for team: TeamInfo) -> Color {
        if let hex = team.colorHex, let c = Color(sportsHex: hex) {
            return c
        }
        // Fallback: stable deep hue from id
        let key = (team.id.isEmpty ? team.name : team.id).lowercased()
        var hash: UInt64 = 5381
        for b in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(b)
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.70, brightness: 0.38)
    }
}

extension Color {
    /// Parse ESPN-style hex (`BA0021` or `#BA0021`).
    init?(sportsHex: String) {
        var s = sportsHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
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
                        image.resizable().scaledToFit()
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

// MARK: - Dashboard matchup row
// Layout cue (Apple Sports–inspired):  logo+name | score | status | score | logo+name
// No full names jammed beside the logo (that caused "Lo" truncation).

struct GameMatchupRow: View {
    let game: Game
    var isFavorite: Bool = false
    var onFavorite: (() -> Void)?

    var body: some View {
        Group {
            if game.usesMatchupLayout {
                matchup
            } else {
                eventLayout
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(minHeight: 88)
        .contentShape(Rectangle())
    }

    private var matchup: some View {
        HStack(spacing: 0) {
            // Away
            HStack(spacing: 8) {
                favoriteStar
                teamBlock(team: game.away, alignment: .center)
                scoreText(game.away.displayScore, dimmed: losing(game.away))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center status
            centerStatus
                .frame(width: 86)

            // Home
            HStack(spacing: 8) {
                scoreText(game.home.displayScore, dimmed: losing(game.home))
                teamBlock(team: game.home, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func teamBlock(team: TeamInfo, alignment: HorizontalAlignment) -> some View {
        VStack(spacing: 6) {
            TeamMarkView(team: team, size: 44)
            Text(team.rowLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: 72)
        }
        .frame(width: 72)
    }

    private var centerStatus: some View {
        VStack(spacing: 5) {
            if game.isLive {
                Text("LIVE")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(SportsColors.live)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(SportsColors.live.opacity(0.16), in: Capsule())
            }
            Text(game.statusLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(game.isLive ? SportsColors.live : SportsColors.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private var eventLayout: some View {
        HStack(spacing: 12) {
            favoriteStar
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
    private var favoriteStar: some View {
        if let onFavorite {
            #if os(tvOS)
            // Indicator only — nested Button inside row Button traps focus on Apple TV.
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.body.weight(.semibold))
                .foregroundStyle(isFavorite ? SportsColors.gold : SportsColors.muted.opacity(0.65))
                .frame(width: 26, height: 44)
                .accessibilityHidden(true)
            #else
            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isFavorite ? SportsColors.gold : SportsColors.muted.opacity(0.65))
                    .frame(width: 26, height: 44)
            }
            .buttonStyle(.plain)
            #endif
        } else {
            Color.clear.frame(width: 4, height: 44)
        }
    }

    private func scoreText(_ score: String, dimmed: Bool) -> some View {
        Text(score)
            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(dimmed ? SportsColors.muted : SportsColors.text)
            .frame(minWidth: 36, alignment: .center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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

// MARK: - Focusable score row (tvOS-safe — no white .card plume)

/// Wraps `GameMatchupRow` with custom gold focus; avoids system .card scale that clips at edges.
/// Canonical S-TV.1: `@Environment(\.isFocused)` chrome + `sportsTVFocusClean()` — no hybrid lift.
struct GameScoreFocusRow: View {
    let game: Game
    var isFavorite: Bool = false
    var onSelect: () -> Void
    var onFavorite: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            #if os(tvOS)
            SportsTVFocused { focused in
                scoreLabel(focused: focused)
            }
            #else
            scoreLabel(focused: false)
            #endif
        }
        #if os(tvOS)
        .sportsTVFocusClean()
        #else
        .buttonStyle(.plain)
        #endif
        .compositingGroup()
        .accessibilityHint("Opens game details and streams")
    }

    @ViewBuilder
    private func scoreLabel(focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: SportsTVMetrics.focusCorner, style: .continuous)
        #if os(tvOS)
        let favAction: (() -> Void)? = nil
        #else
        let favAction = onFavorite
        #endif
        GameMatchupRow(
            game: game,
            isFavorite: isFavorite,
            onFavorite: favAction
        )
        #if os(tvOS)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(minHeight: SportsTVMetrics.scoreRowMinHeight)
        #endif
        .background {
            shape.fill(focused ? SportsColors.panelElevated : SportsColors.panel.opacity(0.92))
        }
        .overlay {
            shape.stroke(
                focused ? SportsColors.gold : SportsColors.border.opacity(0.35),
                lineWidth: focused ? 3 : 1
            )
        }
        .clipShape(shape)
        .shadow(color: focused ? SportsColors.gold.opacity(0.30) : .clear, radius: 14, y: 0)
        #if os(tvOS)
        .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        #endif
    }
}

// MARK: - Soft surface (channel-picker style card)

extension View {
    /// Soft material surface — no stroke (grouped list / stream picker style).
    func sportsSoftSurface(radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(SportsColors.panelElevated.opacity(0.28))
                    }
            }
            .clipShape(shape)
    }
}
