import Foundation

enum GameStatus: String, Codable, Sendable {
    case live, upcoming, final_, postponed, unknown
}

struct TeamInfo: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var abbreviation: String
    var score: Int?
    var logoURL: String?

    var displayScore: String {
        if let score { return "\(score)" }
        return "—"
    }
}

struct Game: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var league: SportLeague
    var home: TeamInfo
    var away: TeamInfo
    var status: GameStatus
    var startTime: Date
    var statusDetail: String?
    var period: String?
    var clock: String?
    var broadcasts: [String]
    var venue: String?
    var eventName: String?
    var isHeadToHead: Bool

    var isLive: Bool { status == .live }
    var isFinal: Bool { status == .final_ }
    var isUpcoming: Bool { status == .upcoming }

    var usesMatchupLayout: Bool {
        isHeadToHead && league.sportPath != "golf" && league.sportPath != "racing"
    }

    var matchupLabel: String {
        if usesMatchupLayout {
            return "\(away.abbreviation) @ \(home.abbreviation)"
        }
        return eventName ?? league.label
    }

    /// ESPN-style short status (clock / period / FINAL).
    var statusLine: String {
        if isFinal { return "FINAL" }
        if isUpcoming {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: startTime)
        }
        if let detail = statusDetail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty,
           detail.lowercased() != "in progress",
           detail.lowercased() != "live" {
            return detail
        }
        if let clock, !clock.isEmpty {
            return league.sportPath == "soccer" && !clock.contains("'") ? "\(clock)'" : clock
        }
        return "LIVE"
    }
}
