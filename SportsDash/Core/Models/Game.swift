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
    /// ESPN primary hex without `#` (e.g. `BA0021`), when available.
    var colorHex: String?
    /// ESPN alternate hex, when available.
    var alternateColorHex: String?
    /// Short label for score rows (e.g. "Angels", "Giants").
    var shortName: String?

    var displayScore: String {
        if let score { return "\(score)" }
        return "—"
    }

    /// Compact name under logo — prefers shortName, else last word of full name, else abbrev.
    var rowLabel: String {
        if let shortName, !shortName.isEmpty { return shortName }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts.last!)
        }
        return abbreviation
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
    /// Scheduled / not started. Also treats future kickoff as upcoming if ESPN
    /// left status ambiguous (unknown) but start is still ahead.
    var isUpcoming: Bool {
        if status == .upcoming { return true }
        if status == .live || status == .final_ || status == .postponed { return false }
        // unknown + future start → show under Upcoming rather than disappearing
        return startTime > Date().addingTimeInterval(-15 * 60)
    }

    var usesMatchupLayout: Bool {
        isHeadToHead && league.sportPath != "golf" && league.sportPath != "racing"
    }

    var matchupLabel: String {
        if usesMatchupLayout {
            return "\(away.abbreviation) @ \(home.abbreviation)"
        }
        return eventName ?? league.label
    }

    /// ESPN-style short status (clock / period / FINAL / start time).
    var statusLine: String {
        if isFinal { return "FINAL" }
        if isUpcoming {
            return Self.formatStartTime(startTime, statusDetail: statusDetail)
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

    private static func formatStartTime(_ start: Date, statusDetail: String?) -> String {
        if start > Date.distantPast.addingTimeInterval(60) {
            let cal = Calendar.current
            let f = DateFormatter()
            f.locale = .current
            if cal.isDateInToday(start) {
                f.dateFormat = "h:mm a"
            } else if cal.isDateInTomorrow(start) {
                f.dateFormat = "'Tomorrow' h:mm a"
            } else if cal.component(.year, from: start) == cal.component(.year, from: Date()) {
                f.dateFormat = "EEE M/d h:mm a"
            } else {
                f.dateFormat = "MMM d, yyyy h:mm a"
            }
            return f.string(from: start)
        }
        if let detail = statusDetail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty,
           detail.uppercased() != "TBD" {
            return detail
        }
        return "TBD"
    }
}
