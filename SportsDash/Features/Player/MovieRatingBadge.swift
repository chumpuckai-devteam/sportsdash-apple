import SwiftUI

/// Compact critic / audience chips (RT-style, generic labels — no RT trademark required).
struct MovieRatingBadge: View {
    let rating: MovieRating
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            if let critic = rating.criticLabel {
                scoreChip(systemName: "percent", label: compact ? critic : "Critic \(critic)", tint: SportsColors.danger)
            }
            if let audience = rating.audienceLabel {
                scoreChip(systemName: "person.2.fill", label: compact ? audience : "Audience \(audience)", tint: SportsColors.gold)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let c = rating.criticLabel { parts.append("Critic \(c)") }
        if let a = rating.audienceLabel { parts.append("Audience \(a)") }
        return parts.joined(separator: ", ")
    }

    private func scoreChip(systemName: String, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: compact ? 10 : 11, weight: .bold))
                .foregroundStyle(SportsColors.text)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(SportsColors.panelElevated.opacity(0.95), in: Capsule())
        .overlay {
            Capsule().stroke(SportsColors.border.opacity(0.8), lineWidth: 1)
        }
    }
}

/// Loads a rating for a title without blocking the parent layout.
struct MovieRatingLoader: View {
    let title: String
    var categories: [String] = []
    var channelGroup: String? = nil
    var channelName: String? = nil
    var compact: Bool = false

    @State private var rating: MovieRating?
    @State private var attempted = false

    var body: some View {
        Group {
            if let rating {
                MovieRatingBadge(rating: rating, compact: compact)
            }
        }
        .task(id: title) {
            await load()
        }
    }

    private func load() async {
        let hint = MovieDetection.isMovieCandidate(
            title: title,
            categories: categories,
            channelGroup: channelGroup,
            channelName: channelName
        )
        guard hint else {
            rating = nil
            return
        }
        let result = await MovieRatingsService.shared.rating(
            forTitle: title,
            year: nil,
            isMovieHint: hint
        )
        await MainActor.run {
            rating = result
            attempted = true
        }
    }
}
