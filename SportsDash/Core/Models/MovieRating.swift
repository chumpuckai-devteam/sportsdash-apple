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
    private static let noiseTokens: Set<String> = [
        "hd", "fhd", "uhd", "4k", "8k", "hdr", "hdr10", "dv", "sdr",
        "live", "premiere", "new", "eng", "en", "multi", "dual",
        "h264", "h265", "hevc", "aac", "ac3", "dts",
    ]

    /// Strip common EPG noise and pull trailing `(YYYY)`.
    static func parse(_ raw: String) -> (title: String, year: Int?) {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["movie:", "film:", "cinema:", "mov:", "movies -", "movie -"]
        let lower = t.lowercased()
        for p in prefixes where lower.hasPrefix(p) {
            t = String(t.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        if let sep = t.range(of: #"^(?i)(movie|film|cinema)\s*[\|·:\-]\s*"#, options: .regularExpression) {
            t = String(t[sep.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
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
        if year == nil, let re = try? NSRegularExpression(pattern: #"\s(19|20)\d{2}\s*$"#),
           let match = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let r = Range(match.range, in: t) {
            let digits = t[r].filter(\.isNumber)
            if let y = Int(digits), (1950 ... 2035).contains(y) {
                year = y
                t = String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        t = t.replacingOccurrences(of: #"\[(.*?)\]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(
            of: #"\((?:hd|fhd|uhd|4k|hdr|live|multi)[^)]*\)"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        var parts = t.split(separator: " ").map(String.init)
        while let last = parts.last?.lowercased(),
              noiseTokens.contains(last) || last.hasPrefix("1080") || last.hasPrefix("720") {
            parts.removeLast()
        }
        t = parts.joined(separator: " ")
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    private static let sportsHints = [
        "sport", "espn", "nfl", "nba", "mlb", "nhl", "soccer", "football", "tennis",
        "golf", "ufc", "racing", "f1", "nascar", "wwe", "boxing", "olympics",
        "premier league", "la liga", "serie a", "bundesliga", "cricket", "rugby",
    ]
    private static let newsHints = ["news", "weather", "cnn", "msnbc", "fox news", "cnbc", "bloomberg"]
    private static let movieChannelHints = [
        "hbo", "showtime", "starz", "cinemax", "movie", "movies", "film", "films",
        "cinema", "mgm", "tcm", "epix", "amc", "fxm", "indie",
        "hollywood", "paramount", "stars", "sky cinema", "cineplex",
        "hallmark", "lifetime movies", "sony movies", "freeform",
        "24/7 movie", "hollywood 24", "hollywoodbox", "vod",
    ]
    private static let softGroups = [
        "entertainment", "premium", "hollywood", "vod", "hollywood", "hollywood box", "hollywood network",
    ]
    private static let skipTitles = [
        "no information", "no info", "no program", "to be announced", "tba", "tbd",
        "program data", "unknown", "n/a", "off air", "off-air", "sign off", "test card",
        "paid programming", "infomercial",
    ]

    /// Whether this EPG program should be treated as a movie candidate for ratings lookup.
    static func isMovieCandidate(
        title: String,
        categories: [String] = [],
        channelGroup: String? = nil,
        channelName: String? = nil
    ) -> Bool {
        let (cleanTitle, year) = MovieTitleParser.parse(title)
        guard cleanTitle.count >= 2 else { return false }
        let t = cleanTitle.lowercased()
        if skipTitles.contains(where: { t == $0 || t.hasPrefix($0) }) { return false }

        let catBlob = categories.joined(separator: " ").lowercased()
        let group = (channelGroup ?? "").lowercased()
        let ch = (channelName ?? "").lowercased()
        let bag = catBlob + " " + group + " " + ch

        if sportsHints.contains(where: { bag.contains($0) }) { return false }
        if newsHints.contains(where: { bag.contains($0) }) { return false }
        if catBlob.contains("sport") || catBlob.contains("news") || catBlob.contains("weather") {
            return false
        }
        if sportsHints.contains(where: { t.contains($0) }) { return false }

        if catBlob.contains("movie") || catBlob.contains("film") || catBlob.contains("cinema") {
            return true
        }
        if movieChannelHints.contains(where: { group.contains($0) || ch.contains($0) }) {
            return true
        }
        if t.hasPrefix("movie:") || t.hasPrefix("film:") { return true }
        if year != nil { return true }
        if title.range(of: #"\(\d{4}\)"#, options: .regularExpression) != nil { return true }

        if softGroups.contains(where: { group.contains($0) || ch.contains($0) }) {
            return cleanTitle.count >= 4
        }

        // Multi-word titles on non-sports channels (common IPTV film listings without year).
        let words = cleanTitle.split(separator: " ")
        if words.count >= 2 && cleanTitle.count >= 8 {
            return true
        }

        return false
    }
}
