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

/// Structured movie-flag inputs (P0 = XMLTV categories; channel/title are fallbacks).
struct MovieFlagSignals: Sendable, Hashable {
    var cleanTitle: String
    var year: Int?
    /// XMLTV `<category>` contains movie/film/cinema (highest-confidence P0 flag).
    var categorySaysMovie: Bool
    /// XMLTV category is sports/news/series/etc. without a movie token.
    var categorySaysNonMovie: Bool
    var channelSaysMovie: Bool
    var channelSaysSportsOrNews: Bool
    var titleHasYear: Bool
    var titlePrefixedMovie: Bool
    var softEntertainmentChannel: Bool
    var multiWordTitle: Bool

    /// Final gate for ratings lookup / Guide movie filter.
    var isMovieCandidate: Bool {
        guard cleanTitle.count >= 2 else { return false }
        if channelSaysSportsOrNews { return false }
        // P0 hard yes — category wins even on soft entertainment channels.
        if categorySaysMovie { return true }
        // Explicit non-movie category blocks weak heuristics (series/news/sport).
        if categorySaysNonMovie { return false }
        if channelSaysMovie { return true }
        if titlePrefixedMovie { return true }
        if titleHasYear || year != nil { return true }
        if softEntertainmentChannel && cleanTitle.count >= 4 { return true }
        // Last-resort IPTV heuristic: only when no category metadata at all.
        if multiWordTitle { return true }
        return false
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
        "entertainment", "premium", "hollywood", "vod",
    ]
    private static let skipTitles = [
        "no information", "no info", "no program", "to be announced", "tba", "tbd",
        "program data", "unknown", "n/a", "off air", "off-air", "sign off", "test card",
        "paid programming", "infomercial",
    ]

    /// Build structured signals (tests + debugging) then gate with `isMovieCandidate`.
    static func signals(
        title: String,
        categories: [String] = [],
        channelGroup: String? = nil,
        channelName: String? = nil
    ) -> MovieFlagSignals {
        let (cleanTitle, year) = MovieTitleParser.parse(title)
        let t = cleanTitle.lowercased()
        let group = (channelGroup ?? "").lowercased()
        let ch = (channelName ?? "").lowercased()
        let bag = group + " " + ch

        let skip = skipTitles.contains(where: { t == $0 || t.hasPrefix($0) })
        let categoryMovie = XmltvCategory.saysMovie(categories)
        let categoryNonMovie = !categoryMovie && XmltvCategory.saysNonMovie(categories)
        let sportsOrNews =
            sportsHints.contains(where: { bag.contains($0) })
            || newsHints.contains(where: { bag.contains($0) })
            || sportsHints.contains(where: { t.contains($0) })
        let channelMovie = movieChannelHints.contains(where: { group.contains($0) || ch.contains($0) })
        let soft = softGroups.contains(where: { group.contains($0) || ch.contains($0) })
        let words = cleanTitle.split(separator: " ")
        // Only use multi-word heuristic when categories are absent (real IPTV often omits them).
        let multiWord = categories.isEmpty && words.count >= 2 && cleanTitle.count >= 8 && !skip
        let titleYear =
            year != nil
            || title.range(of: #"\(\d{4}\)"#, options: .regularExpression) != nil
        let prefixed =
            t.hasPrefix("movie:") || t.hasPrefix("film:")
            || title.lowercased().hasPrefix("movie:") || title.lowercased().hasPrefix("film:")

        return MovieFlagSignals(
            cleanTitle: skip ? "" : cleanTitle,
            year: year,
            categorySaysMovie: categoryMovie,
            categorySaysNonMovie: categoryNonMovie || skip,
            channelSaysMovie: channelMovie,
            channelSaysSportsOrNews: sportsOrNews,
            titleHasYear: titleYear,
            titlePrefixedMovie: prefixed,
            softEntertainmentChannel: soft,
            multiWordTitle: multiWord
        )
    }

    /// Whether this EPG program should be treated as a movie candidate for ratings lookup.
    static func isMovieCandidate(
        title: String,
        categories: [String] = [],
        channelGroup: String? = nil,
        channelName: String? = nil
    ) -> Bool {
        signals(
            title: title,
            categories: categories,
            channelGroup: channelGroup,
            channelName: channelName
        ).isMovieCandidate
    }
}
