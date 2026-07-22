import Foundation
import SwiftUI

/// Shared in-memory ratings for Guide/Player so List cells don't each own fragile tasks.
@MainActor
final class MovieRatingsStore: ObservableObject {
    static let shared = MovieRatingsStore()

    /// cacheKey → rating (nil entry means fetched, no score)
    @Published private(set) var ratings: [String: MovieRating] = [:]
    /// Keys currently in-flight
    @Published private(set) var loading: Set<String> = []
    /// Keys we already attempted (success or miss)
    private var attempted: Set<String> = []

    func rating(forCacheKey key: String) -> MovieRating? {
        ratings[key]
    }

    func isLoading(_ key: String) -> Bool {
        loading.contains(key)
    }

    func hasAttempted(_ key: String) -> Bool {
        attempted.contains(key) || ratings[key] != nil
    }

    /// Request a rating; safe to call repeatedly from many rows.
    func request(
        title: String,
        categories: [String] = [],
        channelGroup: String? = nil,
        channelName: String? = nil,
        forceMovie: Bool = false
    ) {
        let hint = forceMovie || MovieDetection.isMovieCandidate(
            title: title,
            categories: categories,
            channelGroup: channelGroup,
            channelName: channelName
        )
        guard hint else { return }

        let (clean, year) = MovieTitleParser.parse(title)
        guard clean.count >= 2 else { return }
        let key = MovieTitleParser.cacheKey(title: clean, year: year)

        if ratings[key] != nil { return }
        if loading.contains(key) { return }
        if attempted.contains(key) { return }

        loading.insert(key)
        Task {
            let result = await MovieRatingsService.shared.rating(
                forTitle: title,
                year: year,
                isMovieHint: true
            )
            await MainActor.run {
                self.loading.remove(key)
                self.attempted.insert(key)
                if let result {
                    self.ratings[key] = result
                }
            }
        }
    }

    /// Prefetch now-playing titles for a guide category.
    func prefetch(channels: [IptvChannel], epgByChannel: [String: [EpgProgram]], categoryName: String?) {
        for ch in channels.prefix(16) {
            let programs = epgByChannel[ch.id] ?? []
            guard let now = programs.first(where: \.isNow) ?? programs.first else { continue }
            let group = ch.group ?? categoryName
            // Movie category folders: always try now-playing titles.
            let force = (group ?? "").localizedCaseInsensitiveContains("movie")
                || (group ?? "").localizedCaseInsensitiveContains("cinema")
                || (ch.name).localizedCaseInsensitiveContains("cinema")
                || (ch.name).localizedCaseInsensitiveContains("movie")
            request(
                title: now.title,
                categories: now.categories,
                channelGroup: group,
                channelName: ch.name,
                forceMovie: force
            )
        }
    }

    func clearAttempts() {
        attempted.removeAll()
        loading.removeAll()
        // keep successful ratings
    }
}
