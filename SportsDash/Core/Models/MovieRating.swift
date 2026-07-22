import Foundation

/// Aggregated movie quality scores for now-playing IPTV titles (RT-style).
struct MovieRating: Identifiable, Hashable, Sendable, Codable {
    var id: String { cacheKey }
    /// Normalized cache key (title|year).
    var cacheKey: String
    var title: String
    var year: Int?
    /// Critic score 0–100 when known (e.g. Rotten Tomatoes Tomatometer via OMDb).
    var criticScore: Int?
    /// Audience score 0–100 when known (IMDb/TMDB mapped to 0–100).
    var audienceScore: Int?
    /// Provider label for UI footnote (e.g. "OMDb", "TMDB").
    var source: String
    var fetchedAt: Date
    /// Remote poster path/URL if available (optional future UI).
    var posterURL: String?

    var hasAnyScore: Bool {
        criticScore != nil || audienceScore != nil
    }

    var criticLabel: String? {
        guard let criticScore else { return nil }
        return "\(criticScore)%"
    }

    var audienceLabel: String? {
        guard let audienceScore else { return nil }
        return "\(audienceScore)%"
    }
}

enum MovieTitleParser {
    /// Strip common EPG noise and pull trailing `(YYYY)`.
    static func parse(_ raw: String) -> (title: String, year: Int?) {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop leading "Movie:" / "FILM -" prefixes common on IPTV EPG.
        let prefixes = ["movie:", "film:", "cinema:", "mov:"]
        let lower = t.lowercased()
        for p in prefixes where lower.hasPrefix(p) {
            t = String(t.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        var year: Int?
        if let re = try? NSRegularExpression(pattern: #"\((\d{4})\)\s*$"#),
           let match = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let r = Range(match.range(at: 1), in: t) {
            year = Int(t[r])
            if let full = Range(match.range(at: 0), in: t) {
                t = String(t[..<full.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Collapse internal whitespace.
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return (t, year)
    }

    static func cacheKey(title: String, year: Int?) -> String {
        let (clean, y) = parse(title)
        let resolved = year ?? y
        let base = clean.lowercased()
        if let resolved { return "\(base)|\(resolved)" }
        return base
    }
}

enum MovieDetection {
    /// Whether this EPG program should be treated as a movie candidate for ratings lookup.
    static func isMovieCandidate(
        title: String,
        categories: [String] = [],
        channelGroup: String? = nil,
        channelName: String? = nil
    ) -> Bool {
        let catBlob = categories.joined(separator: " ").lowercased()
        if catBlob.contains("movie") || catBlob.contains("film") || catBlob.contains("cinema") {
            return true
        }
        if catBlob.contains("sport") || catBlob.contains("news") || catBlob.contains("weather") {
            return false
        }

        let group = (channelGroup ?? "").lowercased()
        let ch = (channelName ?? "").lowercased()
        let sportsHints = ["sport", "espn", "nfl", "nba", "mlb", "nhl", "soccer", "football", "tennis", "golf", "ufc", "racing"]
        if sportsHints.contains(where: { group.contains($0) || ch.contains($0) }) {
            return false
        }
        let movieChannelHints = ["hbo", "showtime", "starz", "cinemax", "movie", "film", "cinema", "mgm", "tcm"]
        if movieChannelHints.contains(where: { group.contains($0) || ch.contains($0) }) {
            return true
        }

        let t = title.lowercased()
        if t.hasPrefix("movie:") || t.hasPrefix("film:") { return true }
        // Title with year often indicates a film listing.
        if title.range(of: #"\(\d{4}\)"#, options: .regularExpression) != nil {
            // Avoid sports scores that sometimes include years rarely — still ok.
            if sportsHints.contains(where: { t.contains($0) }) { return false }
            return true
        }
        return false
    }
}
