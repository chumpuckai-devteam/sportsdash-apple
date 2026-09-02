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
    /// True when either side is starred (row chrome / accessibility).
    var isFavorite: Bool = false
    var isAwayFavorite: Bool = false
    var isHomeFavorite: Bool = false
    /// Per-team toggles (Android long-press home/away parity). Nil = indicator-only.
    var onToggleAwayFavorite: (() -> Void)?
    var onToggleHomeFavorite: (() -> Void)?

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
            // Away — star outside top-LEFT of logo
            HStack(spacing: 6) {
                teamBlock(
                    team: game.away,
                    isTeamFavorite: isAwayFavorite,
                    onToggleFavorite: onToggleAwayFavorite,
                    starCorner: .topLeading
                )
                scoreText(game.away.displayScore, dimmed: losing(game.away))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center status
            centerStatus
                .frame(width: 86)

            // Home — star outside top-RIGHT of logo
            HStack(spacing: 6) {
                scoreText(game.home.displayScore, dimmed: losing(game.home))
                teamBlock(
                    team: game.home,
                    isTeamFavorite: isHomeFavorite,
                    onToggleFavorite: onToggleHomeFavorite,
                    starCorner: .topTrailing
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func teamBlock(
        team: TeamInfo,
        isTeamFavorite: Bool,
        onToggleFavorite: (() -> Void)?,
        starCorner: Alignment
    ) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: starCorner) {
                TeamMarkView(team: team, size: 44)
                    // Keep logo clear of the corner badge
                    .padding(.top, 6)
                    .padding(.leading, starCorner == .topLeading ? 8 : 0)
                    .padding(.trailing, starCorner == .topTrailing ? 8 : 0)
                teamStarBadge(isTeamFavorite: isTeamFavorite, onToggle: onToggleFavorite)
                    .offset(
                        x: starCorner == .topLeading ? -2 : 2,
                        y: -2
                    )
            }
            Text(team.rowLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: 78)
        }
        .frame(width: 78)
    }

    @ViewBuilder
    private func teamStarBadge(isTeamFavorite: Bool, onToggle: (() -> Void)?) -> some View {
        let icon = Image(systemName: isTeamFavorite ? "star.fill" : "star")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isTeamFavorite ? SportsColors.gold : SportsColors.muted.opacity(0.55))
            .padding(3)
            .background(
                Circle()
                    .fill(SportsColors.voidBlack.opacity(isTeamFavorite ? 0.85 : 0.55))
            )
        #if os(tvOS)
        // Indicator only — nested Button inside row Button traps focus on Apple TV.
        if isTeamFavorite || onToggle != nil {
            icon.accessibilityHidden(true)
        }
        #else
        if let onToggle {
            Button(action: onToggle) {
                icon
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isTeamFavorite ? "Unstar team" : "Star team")
        } else if isTeamFavorite {
            icon.accessibilityHidden(true)
        }
        #endif
    }

    private var centerStatus: some View {
        VStack(spacing: 5) {
            // Gold WATCH affordance (stream path) — not green LIVE badge
            Text("WATCH")
                .font(.caption2.weight(.black))
                .foregroundStyle(SportsColors.voidBlack)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(SportsColors.gold, in: Capsule())
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
            eventFavoriteIndicator
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
    private var eventFavoriteIndicator: some View {
        if isFavorite || onToggleHomeFavorite != nil || onToggleAwayFavorite != nil {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.body.weight(.semibold))
                .foregroundStyle(isFavorite ? SportsColors.gold : SportsColors.muted.opacity(0.65))
                .frame(width: 26, height: 44)
                .accessibilityHidden(true)
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
    var isAwayFavorite: Bool = false
    var isHomeFavorite: Bool = false
    var hasMatch: Bool = false
    var onSelect: () -> Void
    var onToggleAwayFavorite: (() -> Void)?
    var onToggleHomeFavorite: (() -> Void)?

    var body: some View {
        #if os(iOS)
        JumbotronScoreRow(
            game: game,
            isAwayFavorite: isAwayFavorite,
            isHomeFavorite: isHomeFavorite,
            hasMatch: hasMatch,
            onSelect: onSelect,
            onWatch: onSelect
        )
        .contextMenu {
            if game.usesMatchupLayout {
                if !game.away.id.isEmpty, let onToggleAwayFavorite {
                    Button {
                        onToggleAwayFavorite()
                    } label: {
                        Label(
                            isAwayFavorite ? "Unstar \(game.away.rowLabel)" : "★ Star \(game.away.rowLabel)",
                            systemImage: isAwayFavorite ? "star.slash" : "star.fill"
                        )
                    }
                }
                if !game.home.id.isEmpty, let onToggleHomeFavorite {
                    Button {
                        onToggleHomeFavorite()
                    } label: {
                        Label(
                            isHomeFavorite ? "Unstar \(game.home.rowLabel)" : "★ Star \(game.home.rowLabel)",
                            systemImage: isHomeFavorite ? "star.slash" : "star.fill"
                        )
                    }
                }
            } else {
                if !game.away.id.isEmpty, let onToggleAwayFavorite {
                    Button(action: onToggleAwayFavorite) {
                        Label(
                            isAwayFavorite ? "Unstar \(game.away.rowLabel)" : "★ Star \(game.away.rowLabel)",
                            systemImage: isAwayFavorite ? "star.slash" : "star.fill"
                        )
                    }
                }
                if !game.home.id.isEmpty, let onToggleHomeFavorite {
                    Button(action: onToggleHomeFavorite) {
                        Label(
                            isHomeFavorite ? "Unstar \(game.home.rowLabel)" : "★ Star \(game.home.rowLabel)",
                            systemImage: isHomeFavorite ? "star.slash" : "star.fill"
                        )
                    }
                }
            }
        }
        #else
        Button(action: onSelect) {
            SportsTVFocused { focused in
                scoreLabel(focused: focused)
            }
        }
        .sportsTVFocusClean()
        .compositingGroup()
        .accessibilityLabel(scoreRowAccessibilityLabel)
        .accessibilityHint("Opens game details and streams.")
        #endif
    }

    private var scoreRowAccessibilityLabel: String {
        if game.usesMatchupLayout {
            return "\(game.away.rowLabel) \(game.away.displayScore), \(game.home.rowLabel) \(game.home.displayScore), \(game.statusLine). Watch"
        }
        return "\(game.eventName ?? game.league.label), \(game.statusLine). Watch"
    }

    @ViewBuilder
    private func scoreLabel(focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: SportsTVMetrics.focusCorner, style: .continuous)
        #if os(tvOS)
        let awayAction: (() -> Void)? = nil
        let homeAction: (() -> Void)? = nil
        #else
        let awayAction = onToggleAwayFavorite
        let homeAction = onToggleHomeFavorite
        #endif
        GameMatchupRow(
            game: game,
            isFavorite: isFavorite,
            isAwayFavorite: isAwayFavorite,
            isHomeFavorite: isHomeFavorite,
            onToggleAwayFavorite: awayAction,
            onToggleHomeFavorite: homeAction
        )
        #if os(tvOS)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(minHeight: SportsTVMetrics.scoreRowMinHeight)
        #endif
        #if os(iOS)
        // No gray card behind games — sit directly on void screen background.
        .background(Color.clear)
        #else
        .background {
            let base = focused ? SportsColors.panelElevated : SportsColors.panel.opacity(0.92)
            let favFill = SportsColors.gold.opacity(focused ? 0.22 : 0.12)
            shape.fill(isFavorite ? favFill : base)
        }
        .overlay {
            if focused {
                shape.stroke(SportsColors.gold, lineWidth: 3)
            }
        }
        .clipShape(shape)
        #endif
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
