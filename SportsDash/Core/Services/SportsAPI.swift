import Foundation

/// ESPN public scoreboard client (same endpoints as the Flutter prototype).
actor SportsAPI {
    private let session: URLSession
    private let base = "https://site.api.espn.com/apis/site/v2/sports"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchScoreboards(leagues: [SportLeague]) async throws -> [Game] {
        var all: [Game] = []
        try await withThrowingTaskGroup(of: [Game].self) { group in
            for league in leagues {
                group.addTask {
                    try await self.fetchScoreboard(league: league)
                }
            }
            for try await batch in group {
                all.append(contentsOf: batch)
            }
        }
        return all.sorted { a, b in
            if a.isLive != b.isLive { return a.isLive && !b.isLive }
            return a.startTime < b.startTime
        }
    }

    func fetchScoreboard(league: SportLeague) async throws -> [Game] {
        let urlString = "\(base)/\(league.sportPath)/\(league.leaguePath)/scoreboard"
        guard let url = URL(string: urlString) else { return [] }
        var request = URLRequest(url: url)
        request.setValue("SportsDash/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // Empty board for off-season leagues is fine
            return []
        }
        return try parseScoreboard(data: data, league: league)
    }

    private func parseScoreboard(data: Data, league: SportLeague) throws -> [Game] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            return []
        }

        var games: [Game] = []
        for event in events {
            guard let id = event["id"] as? String else { continue }
            let competitions = event["competitions"] as? [[String: Any]] ?? []
            guard let comp = competitions.first else { continue }

            let statusObj = (comp["status"] as? [String: Any])
                ?? (event["status"] as? [String: Any])
                ?? [:]
            let type = statusObj["type"] as? [String: Any] ?? [:]
            let state = (type["state"] as? String) ?? "pre"
            let name = (type["name"] as? String) ?? ""
            let completed = type["completed"] as? Bool ?? false
            let shortDetail = type["shortDetail"] as? String
            let detail = type["detail"] as? String

            let status: GameStatus
            if completed || name == "STATUS_FINAL" {
                status = .final_
            } else if state == "in" || name.contains("IN_PROGRESS") {
                status = .live
            } else if state == "pre" {
                status = .upcoming
            } else {
                status = .unknown
            }

            let dateStr = (comp["date"] as? String) ?? (event["date"] as? String)
            let start = ISO8601DateFormatter().date(from: dateStr ?? "") ?? Date()

            let competitors = comp["competitors"] as? [[String: Any]] ?? []
            var home = TeamInfo(id: "", name: "Home", abbreviation: "HOME")
            var away = TeamInfo(id: "", name: "Away", abbreviation: "AWAY")
            for c in competitors {
                let team = c["team"] as? [String: Any] ?? [:]
                let info = TeamInfo(
                    id: (team["id"] as? String) ?? UUID().uuidString,
                    name: (team["displayName"] as? String) ?? (team["name"] as? String) ?? "Team",
                    abbreviation: (team["abbreviation"] as? String) ?? "TBD",
                    score: Int(c["score"] as? String ?? "") ?? (c["score"] as? Int),
                    logoURL: team["logo"] as? String
                )
                if (c["homeAway"] as? String) == "home" {
                    home = info
                } else {
                    away = info
                }
            }

            let broadcasts: [String] = {
                guard let list = comp["broadcasts"] as? [[String: Any]] else { return [] }
                var names: [String] = []
                for b in list {
                    if let n = b["names"] as? [String] {
                        names.append(contentsOf: n)
                    }
                }
                return names
            }()

            let venue = (comp["venue"] as? [String: Any])?["fullName"] as? String
            let eventName = event["name"] as? String ?? event["shortName"] as? String
            let period = (statusObj["period"] as? Int).map(String.init)
            let clock = statusObj["displayClock"] as? String

            let isH2H = league.sportPath != "golf" && league.sportPath != "racing"

            games.append(
                Game(
                    id: "\(league.rawValue)-\(id)",
                    league: league,
                    home: home,
                    away: away,
                    status: status,
                    startTime: start,
                    statusDetail: shortDetail ?? detail,
                    period: period,
                    clock: clock,
                    broadcasts: broadcasts,
                    venue: venue,
                    eventName: eventName,
                    isHeadToHead: isH2H
                )
            )
        }
        return games
    }
}
