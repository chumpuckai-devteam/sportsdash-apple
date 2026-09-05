import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Font registration (no runtime fetch)

enum JumbotronFonts {
    static func register() {
        let files = [
            "BebasNeue-Regular",
            "Orbitron-Black",
            "SpaceMono-Regular",
            "SpaceMono-Bold",
        ]
        for name in files {
            let url =
                Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Bebas Neue display. Fallback: condensed system.
    static func display(_ size: CGFloat) -> Font {
        .custom("Bebas Neue", size: size, relativeTo: .title)
    }

    /// Orbitron Black 900 digits. Fallback: rounded monospacedDigit.
    static func digits(_ size: CGFloat) -> Font {
        .custom("Orbitron Black", size: size, relativeTo: .title)
    }

    /// Space Mono body. Fallback: .monospaced.
    static func body(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Space Mono Bold" : "Space Mono", size: size, relativeTo: .caption)
    }
}

extension View {
    func jumbotronDisplayTracking(_ size: CGFloat) -> some View {
        self.tracking(size * 0.04)
    }

    func jumbotronLedGlow() -> some View {
        #if os(tvOS)
        self.shadow(color: SportsColors.ledGlow, radius: SportsTVMetrics.ledGlowRadius)
        #else
        self.shadow(color: SportsColors.ledGlow, radius: 6)
        #endif
    }

    func jumbotronLiveGlow() -> some View {
        #if os(tvOS)
        self.shadow(color: SportsColors.liveGlow, radius: SportsTVMetrics.liveGlowRadius)
        #else
        self.shadow(color: SportsColors.liveGlow, radius: 5)
        #endif
    }

    /// 3pt gold ring + LED glow + 1.045 scale. Cards/rows never gold-fill on focus.
    @ViewBuilder
    func jumbotronTVFocusRing(focused: Bool, fillOnFocus: Bool = false) -> some View {
        #if os(tvOS)
        self
            .overlay {
                Rectangle()
                    .stroke(focused ? SportsColors.gold : SportsColors.border, lineWidth: SportsTVMetrics.hairline)
            }
            .compositingGroup()
            .shadow(color: focused ? SportsColors.ledGlow : .clear, radius: focused ? SportsTVMetrics.focusGlowRadius : 0)
            .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
            .animation(SportsTVFocusMotion.animation, value: focused)
        #else
        self
        #endif
    }

    /// Radius-0 riveted panel. Glass stays off content.
    func jumbotronPanel(
        border: Color = SportsColors.border,
        emphasized: Bool = false
    ) -> some View {
        self
            .background(SportsColors.panelGradient)
            .overlay {
                #if os(tvOS)
                Rectangle().stroke(border, lineWidth: SportsTVMetrics.hairline)
                #else
                Rectangle().stroke(border, lineWidth: 2)
                #endif
            }
            .overlay {
                Rectangle()
                    .stroke(SportsColors.voidBlack, lineWidth: 1)
                    .padding(2)
            }
            .clipShape(Rectangle())
    }

    func jumbotronAXCap() -> some View {
        self.dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

// MARK: - Grid ground

struct JumbotronGridDot: View {
    var body: some View {
        #if canImport(UIKit)
        Image(uiImage: Self.tile)
            .resizable(resizingMode: .tile)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #else
        SportsColors.voidBlack
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #endif
    }

    #if canImport(UIKit)
    /// Phone: 6pt cell / 1pt dot. tvOS: 12pt cell / 2pt dot (006 §1). Separate tiles so phone stays pixel-identical.
    private static let tile: UIImage = {
        #if os(tvOS)
        let step: CGFloat = SportsTVMetrics.gridStep
        let dot: CGFloat = SportsTVMetrics.gridDotSize
        #else
        let step: CGFloat = 6
        let dot: CGFloat = 1
        #endif
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: step, height: step), format: format)
        return renderer.image { ctx in
            UIColor(SportsColors.gridDot).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: dot, height: dot))
        }
    }()
    #endif
}

// MARK: - Type primitives

struct JumbotronScreenTitle: View {
    let first: String
    let gold: String
    var size: CGFloat = 40

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(first)
                .foregroundStyle(SportsColors.text)
            Text(gold)
                .foregroundStyle(SportsColors.gold)
        }
        .font(JumbotronFonts.display(size))
        .jumbotronDisplayTracking(size)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct JumbotronLED: View {
    let text: String
    var size: CGFloat = 26
    var color: Color = SportsColors.gold
    var glow: Bool = true
    var dimmed: Bool = false

    var body: some View {
        Text(text)
            .font(JumbotronFonts.digits(size))
            .monospacedDigit()
            .foregroundStyle(color.opacity(dimmed ? 0.5 : 1))
            .shadow(
                color: glow && !dimmed ? glowColor : .clear,
                radius: glow ? ledRadius : 0
            )
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            #if os(tvOS)
            .drawingGroup(opaque: false)
            #endif
    }

    private var glowColor: Color {
        color == SportsColors.live ? SportsColors.liveGlow : SportsColors.ledGlow
    }

    private var ledRadius: CGFloat {
        #if os(tvOS)
        color == SportsColors.live ? SportsTVMetrics.liveGlowRadius : SportsTVMetrics.ledGlowRadius
        #else
        6
        #endif
    }
}

struct JumbotronWatchButton: View {
    var filled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: filled ? 11 : 9, weight: .bold))
                Text("WATCH")
                    .font(JumbotronFonts.display(filled ? 18 : 15))
                    .jumbotronDisplayTracking(filled ? 18 : 15)
            }
            .foregroundStyle(filled ? SportsColors.voidBlack : SportsColors.gold)
            .padding(.horizontal, filled ? 14 : 8)
            .frame(height: filled ? 36 : 30)
            .background(filled ? SportsColors.gold : Color.clear)
            .overlay {
                if !filled {
                    Rectangle().stroke(SportsColors.gold, lineWidth: 2)
                }
            }
            .shadow(color: filled ? SportsColors.ledGlow : .clear, radius: filled ? 8 : 0)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Watch")
    }
}

struct JumbotronToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(SportsColors.voidBlack)
                    .overlay {
                        #if os(tvOS)
                        Rectangle().stroke(isOn ? SportsColors.gold : SportsColors.border, lineWidth: SportsTVMetrics.hairline)
                        #else
                        Rectangle().stroke(isOn ? SportsColors.gold : SportsColors.border, lineWidth: 2)
                        #endif
                    }
                    .shadow(color: isOn ? SportsColors.ledGlow.opacity(0.55) : .clear, radius: 6)
                Rectangle()
                    .fill(isOn ? SportsColors.gold : SportsColors.border)
                    #if os(tvOS)
                    .frame(width: 30, height: 26)
                    #else
                    .frame(width: 22, height: 18)
                    #endif
                    .padding(2)
                    .shadow(color: isOn ? SportsColors.gold.opacity(0.8) : .clear, radius: 4)
            }
            #if os(tvOS)
            .frame(width: SportsTVMetrics.toggleWidth, height: SportsTVMetrics.toggleHeight)
            #else
            .frame(width: 52, height: 26)
            #endif
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .frame(width: SportsTVMetrics.toggleWidth, height: SportsTVMetrics.minFocusSize)
        #else
        .frame(width: 52, height: 44)
        #endif
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct JumbotronRivet: View {
    var body: some View {
        Circle()
            .fill(SportsColors.border)
            #if os(tvOS)
            .frame(width: SportsTVMetrics.rivet, height: SportsTVMetrics.rivet)
            #else
            .frame(width: 6, height: 6)
            #endif
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 4, height: 2)
                    .offset(y: 1)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Tab bar (opaque panelGradient, lamps, no glass)

struct JumbotronTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            tab(.scores, title: "SCORES")
            tab(.guide, title: "GUIDE")
            tab(.settings, title: "SETTINGS")
        }
        .padding(.top, 8)
        .padding(.bottom, SportsMetrics.tabBarSafePad)
        .frame(height: SportsMetrics.tabBarHeight)
        .frame(maxWidth: .infinity)
        .background(SportsColors.panelGradient)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SportsColors.border)
                .frame(height: 2)
        }
        .jumbotronAXCap()
    }

    private func tab(_ value: AppTab, title: String) -> some View {
        let on = selection == value
        return Button {
            selection = value
        } label: {
            VStack(spacing: 4) {
                Rectangle()
                    .fill(on ? SportsColors.gold : SportsColors.border)
                    .frame(width: 28, height: 4)
                    .shadow(color: on ? SportsColors.ledGlow : .clear, radius: 4)
                Text(title)
                    .font(JumbotronFonts.display(20))
                    .jumbotronDisplayTracking(20)
                    .foregroundStyle(on ? SportsColors.gold : SportsColors.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

#if os(tvOS)
/// Left rail for Apple TV. Back (`onExitCommand`) and long-press return focus here.
struct JumbotronTVSidebar: View {
    @Binding var selection: AppTab
    var sidebarItem: FocusState<AppTab?>.Binding
    var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(.scores, "SCORES")
            row(.guide, "GUIDE")
            row(.settings, "SETTINGS")
            Spacer(minLength: 0)
        }
        .padding(.top, 48)
        .padding(.bottom, 28)
        .padding(.horizontal, expanded ? 18 : 12)
        .frame(width: expanded ? 280 : 72)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SportsColors.panelGradient)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SportsColors.border)
                .frame(width: SportsTVMetrics.hairline)
        }
        .focusSection()
        .accessibilityAddTraits(.isTabBar)
    }

    private func row(_ value: AppTab, _ title: String) -> some View {
        let on = selection == value
        return Button {
            selection = value
        } label: {
            SportsTVFocused { focused in
                HStack(spacing: expanded ? 16 : 0) {
                    Rectangle()
                        .fill((on || focused) ? SportsColors.gold : SportsColors.border)
                        .frame(width: 6, height: 28)
                        .shadow(
                            color: (expanded && (on || focused)) ? SportsColors.ledGlow : .clear,
                            radius: 6
                        )
                    if expanded {
                        Text(title)
                            .font(JumbotronFonts.display(28))
                            .jumbotronDisplayTracking(28)
                            .foregroundStyle((on || focused) ? SportsColors.gold : SportsColors.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, expanded ? 16 : 8)
                .frame(maxWidth: .infinity, minHeight: SportsTVMetrics.minFocusSize, alignment: .leading)
                .background {
                    if focused {
                        SportsColors.gold.opacity(0.14)
                    } else {
                        Color.clear
                    }
                }
                .overlay {
                    Rectangle().stroke(
                        focused ? SportsColors.gold : Color.clear,
                        lineWidth: SportsTVMetrics.hairline
                    )
                }
                .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
            }
        }
        .buttonStyle(.plain)
        .sportsTVFocusClean()
        .focused(sidebarItem, equals: value)
        .accessibilityLabel(value.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}
#endif

// MARK: - Switchboard

struct JumbotronSwitchboard: View {
    @Binding var filter: DashboardFilter
    var favoriteTeams: [TeamInfo]
    var onFavorites: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DashboardFilter.allCases) { f in
                let on = filter == f
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { filter = f }
                } label: {
                    Text(f.label.uppercased())
                        .font(JumbotronFonts.display(18))
                        .jumbotronDisplayTracking(18)
                        .foregroundStyle(on ? SportsColors.voidBlack : SportsColors.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if on {
                                SportsColors.gold
                            } else {
                                SportsColors.panelGradient
                            }
                        }
                        .overlay { Rectangle().stroke(on ? SportsColors.gold : SportsColors.border, lineWidth: 2) }
                        .shadow(color: on ? SportsColors.ledGlow.opacity(0.55) : .clear, radius: 7)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(f.label)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }

            Button(action: onFavorites) {
                HStack(spacing: 4) {
                    if favoriteTeams.isEmpty {
                        Text("★ PICK")
                            .font(JumbotronFonts.display(12))
                            .foregroundStyle(SportsColors.gold)
                    } else {
                        let shown = Array(favoriteTeams.prefix(3))
                        ForEach(Array(shown.enumerated()), id: \.element.id) { idx, team in
                            Text(String(team.abbreviation.prefix(3)))
                                .font(JumbotronFonts.display(8))
                                .foregroundStyle(SportsColors.text)
                                .frame(width: 16, height: 16)
                                .background(TeamTheme.accent(for: team))
                                .overlay {
                                    if idx == 0 {
                                        Rectangle().stroke(SportsColors.gold, lineWidth: 1)
                                    }
                                }
                        }
                        if favoriteTeams.count > 3 {
                            Text("+\(favoriteTeams.count - 3)")
                                .font(JumbotronFonts.display(12))
                                .foregroundStyle(SportsColors.gold)
                        }
                    }
                }
                .frame(width: 66, height: 38)
                .jumbotronPanel(border: SportsColors.gold.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 66, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(favoriteTeams.isEmpty ? "Pick favorite teams" : "Favorite teams")
        }
    }
}

// MARK: - Empty / error / skeleton

struct JumbotronMessagePanel: View {
    var tick: Color = SportsColors.gold
    var title: String
    var subtitle: String
    var cta: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rectangle().fill(tick).frame(width: 4, height: 16)
                Text(title)
                    .font(JumbotronFonts.display(22))
                    .jumbotronDisplayTracking(22)
                    .foregroundStyle(SportsColors.text)
            }
            Text(subtitle)
                .font(JumbotronFonts.body(11))
                .foregroundStyle(SportsColors.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Text(cta)
                    .font(JumbotronFonts.display(16))
                    .foregroundStyle(SportsColors.gold)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .overlay { Rectangle().stroke(SportsColors.gold, lineWidth: 2) }
            }
            .buttonStyle(.plain)
            #if os(tvOS)
            .sportsTVFocusClean()
            #endif
            .frame(minHeight: 44)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jumbotronPanel(border: tick == SportsColors.danger ? SportsColors.danger.opacity(0.55) : SportsColors.border)
    }
}

struct JumbotronSkeletonPanel: View {
    var height: CGFloat = 58

    var body: some View {
        Rectangle()
            .fill(SportsColors.panelGradient)
            .frame(height: height)
            .overlay { Rectangle().stroke(SportsColors.border, lineWidth: 2) }
            .overlay { JumbotronShimmer() }
    }
}

private struct JumbotronShimmer: View {
    @State private var x: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    SportsColors.border.opacity(0.0),
                    SportsColors.border.opacity(0.55),
                    SportsColors.border.opacity(0.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.45)
            .offset(x: x * geo.size.width)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    x = 1.2
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Score row / hero helpers

extension Game {
    var jumbotronStatusLED: String {
        if isFinal { return "FINAL" }
        if isUpcoming { return statusLine.uppercased() }
        if league.sportPath == "soccer" {
            if let clock, !clock.isEmpty {
                return clock.contains("'") ? clock : "\(clock)'"
            }
        }
        if let clock, !clock.isEmpty { return clock.uppercased() }
        if let period, !period.isEmpty { return jumbotronPeriodLabel }
        return statusLine.uppercased()
    }

    var jumbotronStatusCaption: String {
        if isFinal || isUpcoming { return "" }
        let detail = statusDetail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !detail.isEmpty,
           detail.uppercased() != jumbotronStatusLED,
           detail.lowercased() != "in progress",
           detail.lowercased() != "live" {
            return detail.uppercased()
        }
        if let period, !period.isEmpty, jumbotronStatusLED != jumbotronPeriodLabel {
            return jumbotronPeriodLabel
        }
        return ""
    }

    var jumbotronPeriodLabel: String {
        guard let period, !period.isEmpty else { return "" }
        switch league.sportPath {
        case "football", "basketball":
            return period.hasPrefix("Q") ? period.uppercased() : "Q\(period)"
        case "hockey":
            return period.hasPrefix("P") ? period.uppercased() : "P\(period)"
        case "baseball":
            return period
        default:
            return period.uppercased()
        }
    }

    var jumbotronHeroClock: String {
        if isUpcoming { return statusLine.uppercased() }
        if isFinal { return "FINAL" }
        if let clock, !clock.isEmpty {
            return league.sportPath == "soccer" && !clock.contains("'") ? "\(clock)'" : clock
        }
        return jumbotronPeriodLabel.isEmpty ? "LIVE" : jumbotronPeriodLabel
    }

    func jumbotronLosing(_ team: TeamInfo) -> Bool {
        guard isFinal || isLive,
              let a = away.score,
              let h = home.score,
              a != h
        else { return false }
        if team.id == away.id { return a < h }
        if team.id == home.id { return h < a }
        return false
    }

    var jumbotronDigit: (away: String, home: String) {
        if isUpcoming { return ("–", "–") }
        return (away.displayScore == "—" ? "–" : away.displayScore,
                home.displayScore == "—" ? "–" : home.displayScore)
    }
}

extension SportLeague {
    var jumbotronTick: Color {
        switch self {
        case .epl: return Color(sportsHex: "3D195B") ?? SportsColors.gold
        case .mlb: return Color(sportsHex: "D50032") ?? SportsColors.danger
        case .nfl: return Color(sportsHex: "013369") ?? SportsColors.gold
        case .nba: return Color(sportsHex: "C8102E") ?? SportsColors.danger
        case .nhl: return Color(sportsHex: "111111") ?? SportsColors.border
        case .mls: return Color(sportsHex: "C39E6D") ?? SportsColors.gold
        case .ucl: return Color(sportsHex: "0A1C3F") ?? SportsColors.gold
        case .laliga: return Color(sportsHex: "EE8707") ?? SportsColors.gold
        default:
            return TeamTheme.accent(for: TeamInfo(id: rawValue, name: label, abbreviation: rawValue))
        }
    }
}

enum JumbotronBrand {
    static func stripe(for group: String?) -> Color {
        let g = (group ?? "").lowercased()
        if g.contains("movie") || g.contains("film") || g.contains("cinema") || g.contains("hbo") {
            return Color(sportsHex: "6E2B8D") ?? SportsColors.border
        }
        if g.contains("news") || g.contains("cnn") || g.contains("fox news") {
            return Color(sportsHex: "1D4E89") ?? SportsColors.border
        }
        if g.contains("sport") || g.contains("espn") || g.contains("nfl") || g.contains("nba")
            || g.contains("mlb") || g.contains("soccer") || g.contains("football")
            || g.contains("bein") || g.contains("sky") || g.contains("fs1") || g.contains("golf") {
            return Color(sportsHex: "E31837") ?? SportsColors.danger
        }
        return SportsColors.border
    }
}

// MARK: - Score row (phone)

struct JumbotronScoreRow: View {
    let game: Game
    var isAwayFavorite: Bool = false
    var isHomeFavorite: Bool = false
    var hasMatch: Bool = false
    var onSelect: () -> Void
    var onWatch: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                Text(game.away.abbreviation)
                    .font(JumbotronFonts.display(22))
                    .jumbotronDisplayTracking(22)
                    .foregroundStyle(SportsColors.text)
                    .frame(width: 60, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        if isAwayFavorite {
                            Text("★")
                                .font(JumbotronFonts.display(12))
                                .foregroundStyle(SportsColors.gold)
                                .offset(x: 4)
                        }
                    }
                JumbotronLED(
                    text: game.jumbotronDigit.away,
                    size: 26,
                    color: game.isUpcoming ? SportsColors.muted : SportsColors.gold,
                    glow: !game.isUpcoming,
                    dimmed: game.jumbotronLosing(game.away)
                )
                .frame(width: 44)

                VStack(spacing: 1) {
                    JumbotronLED(
                        text: game.jumbotronStatusLED,
                        size: 12,
                        color: game.isLive ? SportsColors.live : SportsColors.muted,
                        glow: game.isLive
                    )
                    if !game.jumbotronStatusCaption.isEmpty {
                        Text(game.jumbotronStatusCaption)
                            .font(JumbotronFonts.body(9))
                            .foregroundStyle(SportsColors.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)

                JumbotronLED(
                    text: game.jumbotronDigit.home,
                    size: 26,
                    color: game.isUpcoming ? SportsColors.muted : SportsColors.gold,
                    glow: !game.isUpcoming,
                    dimmed: game.jumbotronLosing(game.home)
                )
                .frame(width: 44, alignment: .trailing)
                Text(game.home.abbreviation)
                    .font(JumbotronFonts.display(22))
                    .jumbotronDisplayTracking(22)
                    .foregroundStyle(SportsColors.text)
                    .frame(width: 60, alignment: .trailing)
                    .overlay(alignment: .leading) {
                        if isHomeFavorite {
                            Text("★")
                                .font(JumbotronFonts.display(12))
                                .foregroundStyle(SportsColors.gold)
                                .offset(x: -4)
                        }
                    }

                if hasMatch {
                    JumbotronWatchButton(filled: false, action: onWatch)
                        .padding(.leading, 8)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, hasMatch ? 8 : 12)
            .frame(height: SportsMetrics.scoreRowHeight)
            .frame(minHeight: 44)
            .background(SportsColors.panelGradient)
            .overlay { Rectangle().stroke(SportsColors.border, lineWidth: 2) }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(TeamTheme.accent(for: game.away))
                    .frame(width: SportsMetrics.teamEdgeWidth)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(TeamTheme.accent(for: game.home))
                    .frame(width: SportsMetrics.teamEdgeWidth)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens game details and streams")
    }

    private var accessibilityText: String {
        let watch = hasMatch ? ", Watch" : ""
        return "\(game.away.rowLabel), \(game.jumbotronDigit.away), \(game.jumbotronStatusLED), \(game.home.rowLabel), \(game.jumbotronDigit.home)\(watch)"
    }
}

struct JumbotronHeroBoard: View {
    let game: Game
    var isAwayFavorite: Bool = false
    var isHomeFavorite: Bool = false
    var matchCount: Int = 0
    var onSelect: () -> Void
    var onWatch: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                HStack {
                    Text("★ MY GAME · \(game.league.label.uppercased())")
                        .font(JumbotronFonts.display(16))
                        .foregroundStyle(SportsColors.gold)
                    Spacer()
                    if game.isLive {
                        JumbotronLED(
                            text: "● LIVE" + (game.jumbotronPeriodLabel.isEmpty ? "" : " · \(game.jumbotronPeriodLabel)"),
                            size: 11,
                            color: SportsColors.live,
                            glow: true
                        )
                    } else if game.isFinal {
                        JumbotronLED(text: "FINAL", size: 11, color: SportsColors.muted, glow: false)
                    } else {
                        JumbotronLED(text: game.statusLine.uppercased(), size: 11, color: SportsColors.muted, glow: false)
                    }
                }
                .padding(.horizontal, 6)

                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.away.rowLabel.uppercased())
                            .font(JumbotronFonts.display(32))
                            .jumbotronDisplayTracking(32)
                            .foregroundStyle(SportsColors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(recordLine(game.away, starred: isAwayFavorite))
                            .font(JumbotronFonts.body(10))
                            .foregroundStyle(SportsColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 2) {
                        Text(game.isUpcoming ? "START" : "CLOCK")
                            .font(JumbotronFonts.display(13))
                            .foregroundStyle(SportsColors.muted)
                        JumbotronLED(
                            text: game.jumbotronHeroClock,
                            size: 22,
                            color: game.isLive ? SportsColors.live : (game.isUpcoming ? SportsColors.muted : SportsColors.gold),
                            glow: game.isLive
                        )
                    }
                    .frame(width: 84)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(game.home.rowLabel.uppercased())
                            .font(JumbotronFonts.display(32))
                            .jumbotronDisplayTracking(32)
                            .foregroundStyle(SportsColors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(recordLine(game.home, starred: isHomeFavorite))
                            .font(JumbotronFonts.body(10))
                            .foregroundStyle(SportsColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.top, 8)
                .padding(.horizontal, 6)

                HStack(spacing: 0) {
                    digitBox(game.jumbotronDigit.away, dimmed: game.jumbotronLosing(game.away) || game.isUpcoming)
                        .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 84, height: 1)
                    digitBox(game.jumbotronDigit.home, dimmed: game.jumbotronLosing(game.home) || game.isUpcoming)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 6)
                .padding(.horizontal, 6)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !game.broadcasts.isEmpty {
                            Text(game.broadcasts.prefix(2).joined(separator: " · "))
                                .font(JumbotronFonts.body(10))
                                .foregroundStyle(SportsColors.textSecondary)
                                .lineLimit(1)
                        }
                        if matchCount > 0 {
                            JumbotronLED(
                                text: matchCount == 1 ? "1 STREAM OK" : "\(matchCount) STREAMS OK",
                                size: 10,
                                color: SportsColors.live,
                                glow: true
                            )
                        } else {
                            Text("NO STREAM MATCHED")
                                .font(JumbotronFonts.body(10))
                                .foregroundStyle(SportsColors.muted)
                        }
                    }
                    Spacer()
                    if matchCount > 0 {
                        JumbotronWatchButton(filled: true) {
                            onWatch()
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 6)
            }
            .padding(.top, 10)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .background {
                heroBleed
            }
            .overlay { Rectangle().stroke(SportsColors.live.opacity(0.45), lineWidth: 2) }
            .overlay { Rectangle().stroke(SportsColors.voidBlack, lineWidth: 1).padding(2) }
            .overlay(alignment: .topLeading) { JumbotronRivet().padding(6) }
            .overlay(alignment: .topTrailing) { JumbotronRivet().padding(6) }
            .overlay(alignment: .bottomLeading) { JumbotronRivet().padding(6) }
            .overlay(alignment: .bottomTrailing) { JumbotronRivet().padding(6) }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(
            "My game, \(game.away.rowLabel), \(game.jumbotronDigit.away), \(game.jumbotronStatusLED), \(game.home.rowLabel), \(game.jumbotronDigit.home)\(matchCount > 0 ? ", Watch" : "")"
        )
    }

    private var heroBleed: some View {
        let away = TeamTheme.accent(for: game.away).opacity(0.55)
        let home = TeamTheme.accent(for: game.home).opacity(0.60)
        return ZStack {
            SportsColors.panelGradient
            LinearGradient(
                stops: [
                    .init(color: away, location: 0),
                    .init(color: SportsColors.panel.opacity(0.95), location: 0.34),
                    .init(color: SportsColors.panel.opacity(0.95), location: 0.66),
                    .init(color: home, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func digitBox(_ text: String, dimmed: Bool) -> some View {
        JumbotronLED(
            text: text,
            size: 58,
            color: game.isUpcoming ? SportsColors.muted : SportsColors.gold,
            glow: !game.isUpcoming,
            dimmed: dimmed && !game.isUpcoming
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(SportsColors.voidBlack)
        .overlay { Rectangle().stroke(SportsColors.border, lineWidth: 1) }
    }

    private func recordLine(_ team: TeamInfo, starred: Bool) -> String {
        let star = starred ? " ★" : ""
        return "\(team.abbreviation)\(star)"
    }
}

struct JumbotronLeagueHeader: View {
    let title: String
    var tick: Color = SportsColors.gold
    var liveCount: Int = 0
    var upcomingCount: Int = 0
    var finalCount: Int = 0
    var filter: DashboardFilter = .live

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Rectangle().fill(tick).frame(width: 4, height: 16)
                Text(title.uppercased())
                    .font(JumbotronFonts.display(20))
                    .jumbotronDisplayTracking(20)
                    .foregroundStyle(SportsColors.textSecondary)
            }
            Spacer()
            switch filter {
            case .live:
                if liveCount > 0 {
                    JumbotronLED(text: "\(liveCount) LIVE", size: 10, color: SportsColors.live, glow: true)
                }
            case .upcoming:
                JumbotronLED(text: "\(upcomingCount) UPCOMING", size: 10, color: SportsColors.muted, glow: false)
            case .final:
                JumbotronLED(text: "\(finalCount) FINAL", size: 10, color: SportsColors.muted, glow: false)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Settings lamp card

enum JumbotronLampKind { case done, pending, blocked }

struct JumbotronLampCard: View {
    var playlist: JumbotronLampKind
    var epg: JumbotronLampKind
    var favorites: JumbotronLampKind
    var setupCount: Int
    var cta: String
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                lampRow("PLAYLIST", playlist)
                lampRow("EPG", epg)
                lampRow("FAVORITES", favorites)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("SETUP")
                        .font(JumbotronFonts.display(22))
                        .foregroundStyle(SportsColors.text)
                    JumbotronLED(text: "\(setupCount)/3", size: 20, color: SportsColors.gold, glow: true)
                }
                Button(action: action) {
                    Text(cta)
                        .font(JumbotronFonts.display(16))
                        .foregroundStyle(SportsColors.voidBlack)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SportsColors.gold)
                        .shadow(color: SportsColors.ledGlow.opacity(0.55), radius: 6)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            LinearGradient(
                stops: [
                    .init(color: Color(sportsHex: "E31837")?.opacity(0.35) ?? SportsColors.danger.opacity(0.35), location: 0),
                    .init(color: SportsColors.panel.opacity(0.95), location: 0.40),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .overlay { Rectangle().stroke(SportsColors.gold.opacity(0.45), lineWidth: 2) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup \(setupCount) of 3")
    }

    private func lampRow(_ title: String, _ kind: JumbotronLampKind) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(lampColor(kind))
                .frame(width: 10, height: 10)
                .shadow(color: lampColor(kind).opacity(0.9), radius: 4)
            Text(title)
                .font(JumbotronFonts.body(11))
                .foregroundStyle(SportsColors.text)
        }
    }

    private func lampColor(_ kind: JumbotronLampKind) -> Color {
        switch kind {
        case .done: return SportsColors.live
        case .pending: return SportsColors.gold
        case .blocked: return SportsColors.danger
        }
    }
}
