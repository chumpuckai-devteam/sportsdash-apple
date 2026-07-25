import Foundation

struct EpgProgram: Identifiable, Hashable, Sendable, Codable {
    var id: String { "\(channelKey)-\(start.timeIntervalSince1970)" }
    var channelKey: String
    var title: String
    var start: Date
    var end: Date
    var description: String?
    /// XMLTV `<category>` values when present (P0 movie-flag + Guide chips).
    var categories: [String] = []

    enum CodingKeys: String, CodingKey {
        case channelKey, title, start, end, description, categories
    }

    init(
        channelKey: String,
        title: String,
        start: Date,
        end: Date,
        description: String? = nil,
        categories: [String] = []
    ) {
        self.channelKey = channelKey
        self.title = title
        self.start = start
        self.end = end
        self.description = description
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelKey = try c.decode(String.self, forKey: .channelKey)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
    }

    /// Remap parsed XMLTV channel id → app channel id without dropping metadata.
    func remapped(toChannelKey key: String) -> EpgProgram {
        guard key != channelKey else { return self }
        return EpgProgram(
            channelKey: key,
            title: title,
            start: start,
            end: end,
            description: description,
            categories: categories
        )
    }

    var isNow: Bool {
        let now = Date()
        return start <= now && now < end
    }

    /// First non-empty XMLTV category (display + filters).
    var primaryCategory: String? {
        categories.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Compact label for Guide chips (e.g. "Movie", "Sports").
    var categoryChipLabel: String? {
        XmltvCategory.displayLabel(from: categories)
    }

    var timeRangeLabel: String {
        let f = Self.timeFormatter
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    var looksLikeMovie: Bool {
        MovieDetection.isMovieCandidate(title: title, categories: categories)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - XMLTV category helpers

enum XmltvCategory {
    /// Tokens that strongly identify theatrical/feature film programmes (P0 movie flags).
    static let movieTokens = [
        "movie", "movies", "film", "films", "cinema", "feature", "feature film",
        "película", "pelicula", "cine", "kino", "filme",
    ]

    /// Tokens that strongly identify non-movie programmes.
    static let nonMovieTokens = [
        "sport", "sports", "news", "weather", "series", "tvshow", "tv show",
        "episode", "soap", "telenovela", "talk", "reality", "game show",
        "children", "kids", "cartoon", "anime", "documentary series",
        "music video", "paid programming", "infomercial", "shopping",
    ]

    static func normalizedBlob(_ categories: [String]) -> String {
        categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }

    static func saysMovie(_ categories: [String]) -> Bool {
        let blob = normalizedBlob(categories)
        guard !blob.isEmpty else { return false }
        return movieTokens.contains { blob.contains($0) }
    }

    static func saysNonMovie(_ categories: [String]) -> Bool {
        let blob = normalizedBlob(categories)
        guard !blob.isEmpty else { return false }
        // "Movie / Drama" still counts as movie — check movie first at call sites.
        return nonMovieTokens.contains { blob.contains($0) }
    }

    /// Prefer a movie-ish category when present; else first category, title-cased lightly.
    static func displayLabel(from categories: [String]) -> String? {
        let cleaned = categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        if let movie = cleaned.first(where: { saysMovie([$0]) }) {
            return shortLabel(movie)
        }
        return shortLabel(cleaned[0])
    }

    private static func shortLabel(_ raw: String) -> String {
        // XMLTV often uses "Movie/Drama" or "Sports: Football"
        var s = raw
        if let slash = s.firstIndex(of: "/") {
            s = String(s[..<slash])
        }
        if let colon = s.firstIndex(of: ":") {
            s = String(s[..<colon])
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > 1 else { return raw }
        if s.count > 18 {
            return String(s.prefix(16)).trimmingCharacters(in: .whitespaces) + "…"
        }
        // Keep provider casing when mixed; title-case all-lower feeds.
        if s == s.lowercased() {
            return s.localizedCapitalized
        }
        return s
    }
}
