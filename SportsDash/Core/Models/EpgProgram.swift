import Foundation

struct EpgProgram: Identifiable, Hashable, Sendable, Codable {
    var id: String { "\(channelKey)-\(start.timeIntervalSince1970)" }
    var channelKey: String
    var title: String
    var start: Date
    var end: Date
    var description: String?
    /// XMLTV `<category>` values when present (used for movie detection).
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

    var isNow: Bool {
        let now = Date()
        return start <= now && now < end
    }

    var timeRangeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    var looksLikeMovie: Bool {
        MovieDetection.isMovieCandidate(title: title, categories: categories)
    }
}
