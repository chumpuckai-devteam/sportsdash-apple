import SwiftUI

// MARK: - SportsDash design tokens
// HIG: https://developer.apple.com/design/human-interface-guidelines
// Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/liquid-glass
// Materials: https://developer.apple.com/design/human-interface-guidelines/materials
//
// Rule: Liquid Glass is for the *navigation / control* layer that floats above content.
// Content cards use standard materials / opaque panels so hierarchy stays clear.

enum SportsColors {
    static let voidBlack = Color(red: 0.027, green: 0.035, blue: 0.047)
    static let panel = Color(red: 0.059, green: 0.075, blue: 0.094)
    static let panelElevated = Color(red: 0.090, green: 0.110, blue: 0.141)
    static let border = Color(red: 0.165, green: 0.200, blue: 0.251)
    static let gold = Color(red: 1.0, green: 0.722, blue: 0.0)
    static let goldDim = Color(red: 0.722, green: 0.525, blue: 0.043)
    static let live = Color(red: 0.0, green: 0.898, blue: 0.627)
    static let danger = Color(red: 1.0, green: 0.231, blue: 0.361)
    static let muted = Color(red: 0.545, green: 0.588, blue: 0.659)
    static let text = Color(red: 0.949, green: 0.957, blue: 0.969)
    static let textSecondary = Color(red: 0.722, green: 0.753, blue: 0.808)

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
}

// MARK: - Glass / material helpers

extension View {
    /// Navigation-layer glass: Liquid Glass on iOS 26+, material fallback earlier.
    /// Use on floating controls, filter chips, toolbars — not full content backgrounds.
    @ViewBuilder
    func sportsGlass(
        in shape: some Shape = RoundedRectangle(cornerRadius: SportsMetrics.cardRadius, style: .continuous)
    ) -> some View {
        #if os(iOS) || os(tvOS)
        if #available(iOS 26.0, tvOS 26.0, *) {
            // Liquid Glass control layer — https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
            self.glassEffect(in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(SportsColors.border.opacity(0.55), lineWidth: 0.5))
        }
        #else
        self
            .background(.ultraThinMaterial, in: shape)
        #endif
    }

    /// Content-layer card — **standard materials**, not Liquid Glass.
    /// HIG: Liquid Glass is for floating chrome (tabs/toolbars); content uses materials
    /// for separation without a heavy “boarder” look.
    /// https://developer.apple.com/design/human-interface-guidelines/materials
    func sportsContentCard(
        radius: CGFloat = SportsMetrics.cardRadius,
        emphasized: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        // Slight brand lift so dark sports UI stays on-theme
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    SportsColors.panelElevated.opacity(emphasized ? 0.35 : 0.22),
                                    SportsColors.panel.opacity(emphasized ? 0.28 : 0.18),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
            }
            .overlay {
                shape.stroke(
                    emphasized
                        ? SportsColors.live.opacity(0.28)
                        : Color.white.opacity(0.08),
                    lineWidth: emphasized ? 1 : 0.5
                )
            }
            .shadow(
                color: Color.black.opacity(0.28),
                radius: emphasized ? 14 : 10,
                y: 6
            )
    }

    /// Screen root background (void) — never glass-fill the whole canvas.
    func sportsScreenBackground() -> some View {
        self.background(SportsColors.voidBlack.ignoresSafeArea())
    }

    /// Toolbar / menu control styling with glass when available.
    @ViewBuilder
    func sportsToolbarControl() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - Reusable chrome

/// Capsule filter / status chip (Scores All·Live·…, etc.).
struct SportsFilterChip: View {
    let title: String
    var count: Int? = nil
    var countTint: Color = SportsColors.live
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(selected ? SportsColors.voidBlack.opacity(0.75) : countTint)
                }
            }
            .foregroundStyle(selected ? SportsColors.voidBlack : SportsColors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if selected {
                    Capsule(style: .continuous).fill(SportsColors.gold.gradient)
                } else {
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .sportsGlass(in: Capsule(style: .continuous))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small LIVE pill.
struct SportsLiveBadge: View {
    var body: some View {
        Text("LIVE")
            .font(.caption2.weight(.black))
            .foregroundStyle(SportsColors.live)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(SportsColors.live.opacity(0.16), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(SportsColors.live.opacity(0.35), lineWidth: 0.5))
            .accessibilityLabel("Live")
    }
}

/// Gold CTA chip (WATCH).
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

/// Section header used on Scores / lists.
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

/// Toolbar category `Menu` with modern chrome.
struct SportsCategoryMenu: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Menu {
            Picker("Category", selection: $selection) {
                ForEach(options, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.body.weight(.semibold))
                Text(title.isEmpty ? "Category" : title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(SportsColors.gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .sportsGlass(in: Capsule(style: .continuous))
        }
        #if os(iOS)
        .menuOrder(.fixed)
        #endif
    }
}
