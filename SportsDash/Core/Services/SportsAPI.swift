import Foundation

/// ESPN public scoreboard client with bounded concurrency for snappy UI.
actor SportsAPI {
    private let session: URLSession
    private let base = "https://site.api.espn.com/apis/site/v2/sports"
    /// Cap parallel ESPN requests so first paint isn't starved.
    private let maxConcurrent = 5

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 20
            config.httpAdditionalHeaders = [
                "User-Agent": "SportsDash/1.0 (iOS)",
                "Accept": "application/json",
            ]
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    /// Fetches scoreboards; optional progressive callback for partial UI updates.
    func fetchScoreboards(
        leagues: [SportLeague],
        onPartial: (@Sendable ([Game]) -> Void)? = nil
    ) async -> [Game] {
        var all: [Game] = []
        var index = 0
        let list = leagues

        while index < list.count {
            let end = min(index + maxConcurrent, list.count)
            let slice = Array(list[index..<end])
            await withTaskGroup(of: [Game].self) { group in
                for league in slice {
                    group.addTask {
                        (try? await self.fetchScoreboard(league: league)) ?? []
                    }
                }
                for await batch in group {
                    all.append(contentsOf: batch)
                }
            }
            // Progressive update after each batch
            let snapshot = all.sorted(by: Self.sortGames)
            onPartial?(snapshot)
            index = end
        }
        return all.sorted(by: Self.sortGames)
    }

    nonisolated private static func sortGames(_ a: Game, _ b: Game) -> Bool {
        if a.isLive != b.isLive { return a.isLive && !b.isLive }
        return a.startTime < b.startTime
    }

    func fetchScoreboard(league: SportLeague) async throws -> [Game] {
        let urlString = "\(base)/\(league.sportPath)/\(league.leaguePath)/scoreboard"
        guard let url = URL(string: urlString) else { return [] }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
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
        games.reserveCapacity(events.count)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()

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

            let dateStr = (comp["date"] as? String) ?? (event["date"] as? String) ?? ""
            let start = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) ?? Date()

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

            var broadcasts: [String] = []
            if let list = comp["broadcasts"] as? [[String: Any]] {
                for b in list {
                    if let n = b["names"] as? [String] { broadcasts.append(contentsOf: n) }
                }
            }

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
