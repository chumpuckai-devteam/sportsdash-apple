import SwiftUI

// MARK: - SportsDash design tokens
// HIG: https://developer.apple.com/design/human-interface-guidelines
// Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/liquid-glass
// Materials: https://developer.apple.com/design/human-interface-guidelines/materials
//
// Rule: Liquid Glass is for the *navigation / control* layer that floats above content.
// Content cards use standard materials / opaque panels so hierarchy stays clear.

enum SportsColors {
    /// Screen ground — Jumbotron SPEC §1 `#070910`.
    static let voidBlack = Color(sportsHex: "070910") ?? Color(red: 0.027, green: 0.035, blue: 0.063)
    static let panel = Color(sportsHex: "0F131A") ?? Color(red: 0.059, green: 0.075, blue: 0.102)
    static let panelElevated = Color(sportsHex: "171C24") ?? Color(red: 0.090, green: 0.110, blue: 0.141)
    static let border = Color(sportsHex: "2A3340") ?? Color(red: 0.165, green: 0.200, blue: 0.251)
    static let gold = Color(sportsHex: "FFB800") ?? Color(red: 1.0, green: 0.722, blue: 0.0)
    static let goldDim = Color(sportsHex: "B8860B") ?? Color(red: 0.722, green: 0.525, blue: 0.043)
    static let live = Color(sportsHex: "00E5A0") ?? Color(red: 0.0, green: 0.898, blue: 0.627)
    static let danger = Color(sportsHex: "FF3B5C") ?? Color(red: 1.0, green: 0.231, blue: 0.361)
    static let muted = Color(sportsHex: "8B96A8") ?? Color(red: 0.545, green: 0.588, blue: 0.659)
    static let text = Color(sportsHex: "F2F4F7") ?? Color(red: 0.949, green: 0.957, blue: 0.969)
    static let textSecondary = Color(sportsHex: "B8C0CE") ?? Color(red: 0.722, green: 0.753, blue: 0.808)

    /// 1pt dots on a 6pt grid (screen ground).
    static let gridDot = Color(sportsHex: "141B28") ?? Color(red: 0.078, green: 0.106, blue: 0.157)
    /// Gold @ 0.80 — apply with `.shadow(color:ledGlow, radius: 6)`.
    static let ledGlow = gold.opacity(0.80)
    /// Live @ 0.75 — apply with `.shadow(color:liveGlow, radius: 5)`.
    static let liveGlow = live.opacity(0.75)

    static var panelGradient: LinearGradient {
        LinearGradient(
            colors: [panelElevated, panel],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Soft scrim for sheets / floating chrome over video.
    static let scrim = Color.black.opacity(0.45)
}

enum SportsMetrics {
    static let cardRadius: CGFloat = 16
    static let chipRadius: CGFloat = 20
    static let controlHeight: CGFloat = 44
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 20
    static let gridGutter: CGFloat = 12
    /// Jumbotron content panels / buttons / tab lamp — SPEC §3.
    static let jumbotronRadius: CGFloat = 0
    static let screenInset: CGFloat = 12
    static let scoreRowHeight: CGFloat = 58
    static let guideRowHeight: CGFloat = 62
    static let settingsRowHeight: CGFloat = 50
    static let tabBarHeight: CGFloat = 80
    static let tabBarSafePad: CGFloat = 14
    static let teamEdgeWidth: CGFloat = 5
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

/// tvOS focus geometry (HIG ~66pt preferred control size; scale needs margin).
/// https://developer.apple.com/design/human-interface-guidelines/focus-and-selection
enum SportsTVMetrics {
    static let minFocusSize: CGFloat = 66
    static let channelRowHeight: CGFloat = 88
    static let scoreRowMinHeight: CGFloat = 120
    static let focusScale: CGFloat = 1.045
    static let chipFocusScale: CGFloat = 1.06
    static let scoreCardMaxWidth: CGFloat = 960
    static let scoreHorizontalInset: CGFloat = 56
    /// Jumbotron TV surfaces are square (006 §1). Player circular buttons use `circleControl`.
    static let focusCorner: CGFloat = 0
    static let channelCorner: CGFloat = 0
    static let rowVerticalGutter: CGFloat = 10
    static let hairline: CGFloat = 3
    static let edgeBar: CGFloat = 6
    static let stripe: CGFloat = 6
    static let rivet: CGFloat = 8
    static let gridStep: CGFloat = 12
    static let gridDotSize: CGFloat = 2
    static let cardWidth: CGFloat = 420
    static let cardHeight: CGFloat = 236
    static let heroCardWidth: CGFloat = 560
    static let chipHeight: CGFloat = 56
    static let chipMinWidth: CGFloat = 160
    static let screenInset: CGFloat = 48
    static let titleSafe: CGFloat = 60
    static let circleControl: CGFloat = 18
    static let toggleWidth: CGFloat = 72
    static let toggleHeight: CGFloat = 36
    static let settingsRowHeight: CGFloat = 66
    static let ledGlowRadius: CGFloat = 10
    static let focusGlowRadius: CGFloat = 14
    static let liveGlowRadius: CGFloat = 8
}

// MARK: - Glass / material helpers
//
// Liquid Glass symbols (`glassEffect`, `ButtonStyle.glass`) ship with the **iOS 26 SDK**
// (Xcode 26+ / Swift 6.2+). `#available(iOS 26.0, *)` is runtime-only — the type checker
// still needs the symbols in the active SDK. Gate glass branches at **compile time**
// so Xcode 16.4 / iOS 18.5 SDK builds keep the material fallback path.
// Docs: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)

extension View {
    /// Material + hairline control chrome when Liquid Glass SDK/OS is unavailable.
    @ViewBuilder
    fileprivate func sportsGlassMaterialFallback(in shape: some Shape) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(SportsColors.border.opacity(0.55), lineWidth: 0.5))
    }

    /// Navigation-layer glass: Liquid Glass on iOS 26+ (capable SDK), material fallback earlier.
    /// Use on floating controls, filter chips, toolbars — not full content backgrounds.
    @ViewBuilder
    func sportsGlass(
        in shape: some Shape = RoundedRectangle(cornerRadius: SportsMetrics.cardRadius, style: .continuous)
    ) -> some View {
        // Liquid Glass control layer is iOS-first; tvOS uses standard materials.
        #if os(iOS)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.sportsGlassMaterialFallback(in: shape)
        }
        #else
        // Pre–iOS 26 SDK (e.g. Xcode 16.4): symbols absent — material only.
        self.sportsGlassMaterialFallback(in: shape)
        #endif
        #else
        self.sportsGlassMaterialFallback(in: shape)
        #endif
    }

    /// Opaque elevated content panel — never Liquid Glass.
    /// Use for game cards / channel tiles so hierarchy stays clear over void or video.
    func sportsContentCard(
        radius: CGFloat = SportsMetrics.cardRadius,
        emphasized: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                // Solid brand panels (PRD content layer) — not material/glass wash.
                shape.fill(
                    LinearGradient(
                        colors: [
                            emphasized ? SportsColors.panelElevated : SportsColors.panelElevated.opacity(0.98),
                            SportsColors.panel,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.stroke(
                    emphasized
                        ? SportsColors.live.opacity(0.35)
                        : SportsColors.border.opacity(0.55),
                    lineWidth: emphasized ? 1 : 0.5
                )
            }
            .shadow(
                color: Color.black.opacity(emphasized ? 0.40 : 0.32),
                radius: emphasized ? 14 : 10,
                y: 6
            )
    }

    func sportsScreenBackground() -> some View {
        self.background {
            ZStack {
                SportsColors.voidBlack
                JumbotronGridDot()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    /// Toolbar / menu control styling with glass when available.
    @ViewBuilder
    func sportsToolbarControl() -> some View {
        #if os(iOS)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self
        }
        #else
        self
        #endif
        #else
        self
        #endif
    }

    /// tvOS S-TV.1: kill system white lift/hover. Pair with `SportsTVFocused` label chrome.
    /// Never mix with `.buttonStyle(.card)`.
    /// https://developer.apple.com/documentation/swiftui/view/focuseffectdisabled(_:)
    @ViewBuilder
    func sportsTVFocusClean() -> some View {
        #if os(tvOS)
        self
            .buttonStyle(.plain)
            .focusEffectDisabled(true)
        #else
        self
        #endif
    }
}

// MARK: - tvOS custom focus (canonical — S-TV.1)
// One system: Button focusable+activatable; system hover disabled; gold from isFocused.
// Focus ≠ selection (HIG).

struct SportsTVFocused<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    @ViewBuilder var content: (_ focused: Bool) -> Content

    var body: some View {
        content(isFocused)
    }
}

#if os(tvOS)
enum SportsTVFocusMotion {
    static let animation: Animation = .easeOut(duration: 0.14)
}

/// Circular toolbar / chrome control — gold fill when focused, no system white lift.
struct SportsTVIconButton: View {
    let systemName: String
    var accessibilityLabelText: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SportsTVFocused { focused in
                Image(systemName: systemName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                    .frame(width: SportsTVMetrics.minFocusSize, height: SportsTVMetrics.minFocusSize)
                    .background {
                        Circle().fill(focused ? SportsColors.gold : SportsColors.panelElevated)
                    }
                    .overlay {
                        Circle().stroke(
                            focused ? SportsColors.goldDim : SportsColors.border.opacity(0.4),
                            lineWidth: focused ? 2 : 1
                        )
                    }
                    .scaleEffect(focused ? SportsTVMetrics.chipFocusScale : 1.0)
                    .animation(SportsTVFocusMotion.animation, value: focused)
            }
        }
        .sportsTVFocusClean()
        .accessibilityLabel(accessibilityLabelText)
    }
}

/// Opaque list row chrome for TV sheets/pickers (selection ≠ focus).
struct SportsTVListRowLabel<Content: View>: View {
    var selected: Bool = false
    @ViewBuilder var content: (_ focused: Bool) -> Content

    var body: some View {
        SportsTVFocused { focused in
            content(focused)
                .frame(maxWidth: .infinity, minHeight: SportsTVMetrics.minFocusSize, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(focused ? SportsColors.gold : (selected ? SportsColors.panelElevated : SportsColors.panel))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            focused
                                ? SportsColors.goldDim
                                : (selected ? SportsColors.gold.opacity(0.45) : SportsColors.border.opacity(0.35)),
                            lineWidth: focused || selected ? 2 : 1
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
                .animation(SportsTVFocusMotion.animation, value: focused)
        }
    }
}
#endif

#if os(tvOS)
/// tvOS `prefersDefaultFocus` requires a focus namespace (`in:`).
private struct SportsDefaultFocusModifier: ViewModifier {
    let enabled: Bool
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, let namespace {
            content.prefersDefaultFocus(true, in: namespace)
        } else {
            content
        }
    }
}
#endif

// MARK: - Reusable chrome

struct SportsFilterChip: View {
    let title: String
    var count: Int? = nil
    var countTint: Color = SportsColors.live
    let selected: Bool
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            #if os(tvOS)
            SportsTVFocused { focused in
                chipLabel(focused: focused)
            }
            #else
            chipLabel(focused: false)
            #endif
        }
        #if os(tvOS)
        .sportsTVFocusClean()
        .modifier(SportsDefaultFocusModifier(enabled: prefersDefault, namespace: focusNamespace))
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var prefersDefault: Bool = false
    var focusNamespace: Namespace.ID? = nil

    @ViewBuilder
    private func chipLabel(focused: Bool) -> some View {
        #if os(iOS)
        HStack(spacing: 6) {
            Text(title)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selected ? SportsColors.voidBlack.opacity(0.75) : countTint)
            }
        }
        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
        .foregroundStyle(selected ? SportsColors.voidBlack : SportsColors.text)
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 5 : 8)
        .background {
            Capsule(style: .continuous)
                .fill(selected ? SportsColors.gold : SportsColors.panel)
        }
        #else
        jumbotronTVChip(focused: focused)
        #endif
    }

    #if os(tvOS)
    @ViewBuilder
    private func jumbotronTVChip(focused: Bool) -> some View {
        let goldFill = selected || focused
        HStack(spacing: 14) {
            Text(title.uppercased())
                .font(JumbotronFonts.display(26))
                .jumbotronDisplayTracking(26)
                .foregroundStyle(goldFill ? SportsColors.voidBlack : SportsColors.muted)
            if let count, count > 0 {
                JumbotronLED(
                    text: "\(count)",
                    size: 16,
                    color: goldFill ? SportsColors.voidBlack : SportsColors.muted,
                    glow: false
                )
            }
        }
        .padding(.horizontal, 26)
        .frame(minWidth: SportsTVMetrics.chipMinWidth, minHeight: SportsTVMetrics.chipHeight)
        .background {
            if goldFill {
                SportsColors.gold
            } else {
                SportsColors.panelGradient
            }
        }
        .overlay {
            Rectangle().stroke(
                goldFill ? SportsColors.gold : SportsColors.border,
                lineWidth: SportsTVMetrics.hairline
            )
        }
        .shadow(color: goldFill ? SportsColors.ledGlow.opacity(0.55) : .clear, radius: 11)
        .scaleEffect(focused ? SportsTVMetrics.chipFocusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
    }
    #endif
}

struct SportsLiveBadge: View {
    var body: some View {
        Text("LIVE")
            .font(.caption2.weight(.black))
            .foregroundStyle(SportsColors.live)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(SportsColors.live.opacity(0.16), in: Capsule(style: .continuous))

            .accessibilityLabel("Live")
    }
}

struct SportsWatchBadge: View {
    var title: String = "WATCH"

    var body: some View {
        Text(title)
            .font(.caption.weight(.black))
            .foregroundStyle(SportsColors.voidBlack)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(SportsColors.gold.gradient, in: Capsule(style: .continuous))
    }
}

struct SportsSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var accent: Color = SportsColors.text

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(accent)
            Spacer(minLength: 8)
            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SportsColors.live)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityAddTraits(.isHeader)
    }
}
