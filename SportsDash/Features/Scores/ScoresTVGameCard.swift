import SwiftUI

#if os(tvOS)

/// Jumbotron TV score card (006 §3). Radius 0, 6pt edges, LED 44 in boxes, WATCH only when matched.
struct ScoresTVGameCard: View {
    let game: Game
    var isFavoriteMatch: Bool = false
    var isAwayFavorite: Bool = false
    var isHomeFavorite: Bool = false
    var hasMatch: Bool = false
    var isHero: Bool = false
    var onSelect: () -> Void

    private var cardWidth: CGFloat {
        isHero ? SportsTVMetrics.heroCardWidth : SportsTVMetrics.cardWidth
    }

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
        let watch = hasMatch ? ", Watch" : ""
        return "\(game.away.rowLabel), \(game.jumbotronDigit.away), \(game.jumbotronStatusLED), \(game.home.rowLabel), \(game.jumbotronDigit.home)\(watch)"
    }

    private func cardChrome(focused: Bool) -> some View {
        VStack(spacing: 10) {
            topRow
            digitRow
            bottomRow
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(width: cardWidth, height: SportsTVMetrics.cardHeight)
        .background { heroOrPanel }
        .overlay {
            Rectangle().stroke(
                focused ? SportsColors.gold : (isHero ? SportsColors.live.opacity(0.45) : SportsColors.border),
                lineWidth: SportsTVMetrics.hairline
            )
        }
        .overlay(alignment: .leading) {
            if !isHero {
                Rectangle().fill(TeamTheme.accent(for: game.away)).frame(width: SportsTVMetrics.edgeBar)
            }
        }
        .overlay(alignment: .trailing) {
            if !isHero {
                Rectangle().fill(TeamTheme.accent(for: game.home)).frame(width: SportsTVMetrics.edgeBar)
            }
        }
        .overlay(alignment: .topLeading) { if isHero { JumbotronRivet().padding(8) } }
        .overlay(alignment: .topTrailing) { if isHero { JumbotronRivet().padding(8) } }
        .overlay(alignment: .bottomLeading) { if isHero { JumbotronRivet().padding(8) } }
        .overlay(alignment: .bottomTrailing) { if isHero { JumbotronRivet().padding(8) } }
        .shadow(color: focused ? SportsColors.ledGlow : .clear, radius: focused ? SportsTVMetrics.focusGlowRadius : 0)
        .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
    }

    private var heroOrPanel: some View {
        Group {
            if isHero {
                ZStack {
                    SportsColors.panelGradient
                    LinearGradient(
                        stops: [
                            .init(color: TeamTheme.accent(for: game.away).opacity(0.55), location: 0),
                            .init(color: SportsColors.panel.opacity(0.95), location: 0.34),
                            .init(color: SportsColors.panel.opacity(0.95), location: 0.66),
                            .init(color: TeamTheme.accent(for: game.home).opacity(0.60), location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            } else {
                SportsColors.panelGradient
            }
        }
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 0) {
            teamHead(game.away, favorite: isAwayFavorite, trailing: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                JumbotronLED(
                    text: statusLED,
                    size: 18,
                    color: game.isLive ? SportsColors.live : SportsColors.muted,
                    glow: game.isLive
                )
                if isHero {
                    JumbotronLED(
                        text: game.jumbotronHeroClock,
                        size: 28,
                        color: game.isLive ? SportsColors.live : SportsColors.muted,
                        glow: game.isLive
                    )
                } else if !game.jumbotronStatusCaption.isEmpty {
                    Text(game.jumbotronStatusCaption)
                        .font(JumbotronFonts.body(13))
                        .foregroundStyle(SportsColors.muted)
                }
            }
            .frame(width: isHero ? 170 : 150)
            teamHead(game.home, favorite: isHomeFavorite, trailing: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var statusLED: String {
        if isHero {
            if game.isLive {
                let p = game.jumbotronPeriodLabel
                return p.isEmpty ? "● LIVE" : "● LIVE · \(p)"
            }
            if game.isFinal { return "FINAL" }
            return game.statusLine.uppercased()
        }
        return game.jumbotronStatusLED
    }

    private func teamHead(_ team: TeamInfo, favorite: Bool, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 10) {
                if !trailing { logoBox(team) }
                Text((isHero ? team.rowLabel : team.abbreviation).uppercased())
                    .font(JumbotronFonts.display(isHero ? 44 : 34))
                    .jumbotronDisplayTracking(isHero ? 44 : 34)
                    .foregroundStyle(SportsColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if favorite {
                    Text("★").font(JumbotronFonts.display(22)).foregroundStyle(SportsColors.gold)
                }
                if trailing { logoBox(team) }
            }
            Text("\(team.abbreviation)\(favorite ? " ★" : "")")
                .font(JumbotronFonts.body(16))
                .foregroundStyle(SportsColors.textSecondary)
        }
    }

    private func logoBox(_ team: TeamInfo) -> some View {
        Group {
            if let raw = team.logoURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    default: logoFallback(team)
                    }
                }
            } else {
                logoFallback(team)
            }
        }
        .frame(width: 44, height: 44)
        .background(SportsColors.voidBlack)
        .overlay { Rectangle().stroke(SportsColors.border, lineWidth: SportsTVMetrics.hairline) }
    }

    private func logoFallback(_ team: TeamInfo) -> some View {
        Text(team.abbreviation.prefix(3).uppercased())
            .font(JumbotronFonts.display(16))
            .foregroundStyle(SportsColors.gold)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var digitRow: some View {
        HStack(spacing: 0) {
            digitBox(game.jumbotronDigit.away, dimmed: game.jumbotronLosing(game.away) || game.isUpcoming)
            Color.clear.frame(width: isHero ? 170 : 150, height: 1)
            digitBox(game.jumbotronDigit.home, dimmed: game.jumbotronLosing(game.home) || game.isUpcoming)
        }
    }

    private func digitBox(_ text: String, dimmed: Bool) -> some View {
        JumbotronLED(
            text: text,
            size: isHero ? 96 : 44,
            color: game.isUpcoming ? SportsColors.muted : SportsColors.gold,
            glow: !game.isUpcoming,
            dimmed: dimmed && !game.isUpcoming
        )
        .frame(maxWidth: .infinity)
        .frame(height: isHero ? 112 : 66)
        .background(SportsColors.voidBlack)
        .overlay { Rectangle().stroke(SportsColors.border, lineWidth: SportsTVMetrics.hairline) }
    }

    private var bottomRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(JumbotronFonts.body(13))
                    .foregroundStyle(SportsColors.textSecondary)
                    .lineLimit(1)
                if hasMatch {
                    JumbotronLED(
                        text: "STREAM OK",
                        size: 13,
                        color: SportsColors.live,
                        glow: true
                    )
                } else {
                    Text("NO STREAM MATCHED")
                        .font(JumbotronFonts.body(13))
                        .foregroundStyle(SportsColors.muted)
                }
            }
            Spacer()
            if hasMatch {
                Text("WATCH")
                    .font(JumbotronFonts.display(22))
                    .foregroundStyle(SportsColors.voidBlack)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(SportsColors.gold)
                    .shadow(color: SportsColors.ledGlow, radius: 11)
            }
        }
    }

    private var caption: String {
        if !game.broadcasts.isEmpty {
            return game.broadcasts.prefix(2).joined(separator: " · ")
        }
        return "\(game.away.rowLabel.uppercased()) · \(game.home.rowLabel.uppercased())"
    }
}

/// Horizontal Netflix-style rail of Jumbotron TV cards.
struct ScoresTVRail: View {
    let title: String
    var emoji: String? = nil
    var tick: Color = SportsColors.gold
    let games: [Game]
    var favoriteTeamIds: Set<String> = []
    var heroFirst: Bool = false
    var hasMatch: (Game) -> Bool = { _ in false }
    var liveCount: Int = 0
    var filter: DashboardFilter = .live
    var onSelect: (Game) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 12) {
                    Rectangle().fill(tick).frame(width: 6, height: 24)
                    Text(title.uppercased())
                        .font(JumbotronFonts.display(30))
                        .jumbotronDisplayTracking(30)
                        .foregroundStyle(SportsColors.textSecondary)
                }
                Spacer()
                railCount
            }
            .padding(.horizontal, SportsTVMetrics.screenInset)

            if games.isEmpty {
                Text("None scheduled")
                    .font(JumbotronFonts.body(16))
                    .foregroundStyle(SportsColors.muted)
                    .padding(.horizontal, SportsTVMetrics.screenInset)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 24) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { idx, game in
                            ScoresTVGameCard(
                                game: game,
                                isFavoriteMatch: favoriteTeamIds.contains(game.home.id)
                                    || favoriteTeamIds.contains(game.away.id),
                                isAwayFavorite: favoriteTeamIds.contains(game.away.id),
                                isHomeFavorite: favoriteTeamIds.contains(game.home.id),
                                hasMatch: hasMatch(game),
                                isHero: heroFirst && idx == 0,
                                onSelect: { onSelect(game) }
                            )
                        }
                    }
                    .padding(.horizontal, SportsTVMetrics.screenInset)
                    .padding(.vertical, 14)
                }
                .focusSection()
            }
        }
    }

    @ViewBuilder
    private var railCount: some View {
        switch filter {
        case .live:
            if liveCount > 0 || games.contains(where: \.isLive) {
                JumbotronLED(
                    text: "\(liveCount > 0 ? liveCount : games.filter(\.isLive).count) LIVE",
                    size: 16,
                    color: SportsColors.live,
                    glow: true
                )
            }
        case .upcoming:
            JumbotronLED(text: "\(games.count) UPCOMING", size: 16, color: SportsColors.muted, glow: false)
        case .final:
            JumbotronLED(text: "\(games.count) FINAL", size: 16, color: SportsColors.muted, glow: false)
        }
    }
}

#endif
