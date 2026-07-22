import SwiftUI

/// Compact critic / audience chips (RT-style, generic labels — no RT trademark required).
struct MovieRatingBadge: View {
    let rating: MovieRating
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            if let critic = rating.criticLabel {
                scoreChip(
                    systemName: "percent",
                    label: compact ? critic : "Critic \(critic)",
                    tint: Color(red: 0.95, green: 0.35, blue: 0.35)
                )
            }
            if let audience = rating.audienceLabel {
                scoreChip(
                    systemName: "person.2.fill",
                    label: compact ? audience : "Audience \(audience)",
                    tint: SportsColors.gold
                )
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
                .font(.system(size: compact ? 10 : 11, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: compact ? 11 : 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 4 : 5)
        .background(Color.white.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.7), lineWidth: 1)
        }
    }
}

/// Reads from `MovieRatingsStore` and kicks a request. Always reserves vertical space
/// so List cells lay out and updates paint when the store publishes.
struct MovieRatingLoader: View {
    let title: String
    var categories: [String] = []
    var channelGroup: String? = nil
    var channelName: String? = nil
    var compact: Bool = false
    /// When true, skip MovieDetection and always fetch (movie folders).
    var forceMovie: Bool = false

    @ObservedObject private var store = MovieRatingsStore.shared

    private var cacheKey: String {
        let (clean, year) = MovieTitleParser.parse(title)
        return MovieTitleParser.cacheKey(title: clean, year: year)
    }

    private var isCandidate: Bool {
        forceMovie || MovieDetection.isMovieCandidate(
            title: title,
            categories: categories,
            channelGroup: channelGroup,
            channelName: channelName
        )
    }

    var body: some View {
        Group {
            if !isCandidate {
                EmptyView()
            } else if let rating = store.rating(forCacheKey: cacheKey) {
                MovieRatingBadge(rating: rating, compact: compact)
            } else if store.isLoading(cacheKey) || !store.hasAttempted(cacheKey) {
                // Visible placeholder so the row has height and user sees activity
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(SportsColors.gold)
                    if !compact {
                        Text("Ratings…")
                            .font(.caption2)
                            .foregroundStyle(SportsColors.muted)
                    }
                }
                .frame(height: compact ? 20 : 22)
            } else {
                // Attempted, no score — keep tiny spacer so layout stable
                Color.clear.frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            store.request(
                title: title,
                categories: categories,
                channelGroup: channelGroup,
                channelName: channelName,
                forceMovie: forceMovie
            )
        }
        .onChange(of: title) { _, _ in
            store.request(
                title: title,
                categories: categories,
                channelGroup: channelGroup,
                channelName: channelName,
                forceMovie: forceMovie
            )
        }
    }
}
