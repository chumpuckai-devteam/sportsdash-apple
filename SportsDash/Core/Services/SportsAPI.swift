import Foundation

/// ESPN public scoreboard client with bounded concurrency for snappy UI.
actor SportsAPI {
    private let session: URLSession
    private let base = "https://site.api.espn.com/apis/site/v2/sports"
    /// Cap parallel ESPN league requests so first paint isn't starved.
    private let maxConcurrent = 5
    /// Extra calendar days (America/New_York) beyond ESPN's default board.
    /// Default boards often drop to finals-only after the slate ends; dated
    /// fetches restore scheduled games (e.g. MLB tonight / tomorrow).
    private let upcomingDayHorizon = 3

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
    ///
    /// Strategy:
    /// 1. Default ESPN board per league (fast first paint — live + current slate).
    /// 2. Dated boards for today…+horizon (US/Eastern) merged in — fills Upcoming
    ///    when the default slate is already all finals (classic MLB evening hole).
    func fetchScoreboards(
        leagues: [SportLeague],
        onPartial: (@Sendable ([Game]) -> Void)? = nil
    ) async -> [Game] {
        var byId: [String: Game] = [:]
        let list = leagues

        // Pass 1 — default boards only.
        await fetchLeagues(list, urlsForLeague: { league in
            self.defaultScoreboardURL(for: league).map { [$0] } ?? []
        }, into: &byId, onPartial: onPartial)

        // Pass 2 — dated supplements (skip URLs already fetched as default).
        await fetchLeagues(list, urlsForLeague: { league in
            self.datedScoreboardURLs(for: league)
        }, into: &byId, onPartial: onPartial)

        return Array(byId.values).sorted(by: Self.sortGames)
    }

    private func fetchLeagues(
        _ leagues: [SportLeague],
        urlsForLeague: (SportLeague) -> [URL],
        into byId: inout [String: Game],
        onPartial: (@Sendable ([Game]) -> Void)?
    ) async {
        var index = 0
        while index < leagues.count {
            let end = min(index + maxConcurrent, leagues.count)
            let slice = Array(leagues[index..<end])
            let batches: [[Game]] = await withTaskGroup(of: [Game].self, returning: [[Game]].self) { group in
                for league in slice {
                    let urls = urlsForLeague(league)
                    group.addTask {
                        await self.fetchAndMerge(urls: urls, league: league)
                    }
                }
                var out: [[Game]] = []
                for await batch in group {
                    out.append(batch)
                }
                return out
            }
            for batch in batches {
                for game in batch {
                    if let existing = byId[game.id] {
                        byId[game.id] = Self.prefer(existing, game)
                    } else {
                        byId[game.id] = game
                    }
                }
            }
            let snapshot = Array(byId.values).sorted(by: Self.sortGames)
            onPartial?(snapshot)
            index = end
        }
    }

    private func fetchAndMerge(urls: [URL], league: SportLeague) async -> [Game] {
        guard !urls.isEmpty else { return [] }
        var local: [String: Game] = [:]
        await withTaskGroup(of: [Game].self) { group in
            for url in urls {
                group.addTask {
                    (try? await self.fetchScoreboardURL(url, league: league)) ?? []
                }
            }
            for await batch in group {
                for game in batch {
                    if let existing = local[game.id] {
                        local[game.id] = Self.prefer(existing, game)
                    } else {
                        local[game.id] = game
                    }
                }
            }
        }
        return Array(local.values)
    }

    nonisolated private static func sortGames(_ a: Game, _ b: Game) -> Bool {
        if a.isLive != b.isLive { return a.isLive && !b.isLive }
        return a.startTime < b.startTime
    }

    func fetchScoreboard(league: SportLeague) async throws -> [Game] {
        var urls: [URL] = []
        if let d = defaultScoreboardURL(for: league) { urls.append(d) }
        urls.append(contentsOf: datedScoreboardURLs(for: league))
        return await fetchAndMerge(urls: urls, league: league)
    }

    private func defaultScoreboardURL(for league: SportLeague) -> URL? {
        URL(string: "\(base)/\(league.sportPath)/\(league.leaguePath)/scoreboard")
    }

    /// Per-day boards for today…+horizon on the US/Eastern game calendar.
    private func datedScoreboardURLs(for league: SportLeague) -> [URL] {
        guard let root = defaultScoreboardURL(for: league)?.absoluteString else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"

        var urls: [URL] = []
        for offset in 0...upcomingDayHorizon {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let stamp = formatter.string(from: day)
            if let u = URL(string: "\(root)?dates=\(stamp)") {
                urls.append(u)
            }
        }
        return urls
    }

    private func fetchScoreboardURL(_ url: URL, league: SportLeague) async throws -> [Game] {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return []
        }
        return try parseScoreboard(data: data, league: league)
    }

    /// When the same event appears on default + dated boards, keep the fresher status.
    nonisolated private static func prefer(_ a: Game, _ b: Game) -> Game {
        statusRank(a.status) <= statusRank(b.status) ? a : b
    }

    nonisolated private static func statusRank(_ s: GameStatus) -> Int {
        switch s {
        case .live: return 0
        case .upcoming: return 1
        case .postponed: return 2
        case .final_: return 3
        case .unknown: return 4
        }
    }

    private func parseScoreboard(data: Data, league: SportLeague) throws -> [Game] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            return []
        }

        var games: [Game] = []
        games.reserveCapacity(events.count)

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
            if name.contains("POSTPONED") || name.contains("CANCELED") || name.contains("CANCELLED") {
                status = .postponed
            } else if completed || name == "STATUS_FINAL" {
                status = .final_
            } else if state == "in" || name.contains("IN_PROGRESS") {
                status = .live
            } else if state == "pre" {
                status = .upcoming
            } else {
                status = .unknown
            }

            // ESPN often emits `2026-10-05T04:00Z` (no seconds). Strict ISO8601
            // formatters miss that and used to fall back to Date() → every card
            // showed the same "now" clock time.
            let dateStr = (comp["date"] as? String) ?? (event["date"] as? String) ?? ""
            let start = Self.parseESPNDate(dateStr) ?? Date.distantPast

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
                    logoURL: team["logo"] as? String,
                    colorHex: team["color"] as? String,
                    alternateColorHex: team["alternateColor"] as? String,
                    shortName: (team["shortDisplayName"] as? String)
                        ?? (team["name"] as? String)
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

    /// ESPN scoreboard dates vary: with/without seconds, with/without fractional seconds, `Z` or offset.
    nonisolated static func parseESPNDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        // `2026-10-05T04:00Z` / `2026-10-05T04:00:00Z` / offsets without colon variants
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        let patterns = [
            "yyyy-MM-dd'T'HH:mmX",
            "yyyy-MM-dd'T'HH:mm:ssX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSX",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mmZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
        ]
        for p in patterns {
            df.dateFormat = p
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}
