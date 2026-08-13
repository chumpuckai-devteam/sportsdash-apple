import Foundation

/// ESPN public scoreboard client with bounded concurrency for snappy UI.
actor SportsAPI {
    struct ScoreboardFetchResult: Sendable {
        let games: [Game]
        let successfulBoards: Int
        let failedBoards: Int
        let failedLeagues: Set<SportLeague>

        var allBoardsFailed: Bool {
            successfulBoards == 0 && failedBoards > 0
        }

        var hasPartialFailures: Bool {
            successfulBoards > 0 && failedBoards > 0
        }
    }

    private struct LeagueFetchResult: Sendable {
        let games: [Game]
        let successfulBoards: Int
        let failedBoards: Int
        let failedLeague: SportLeague?
    }

    private enum ScoreboardRequestError: Error, Sendable {
        case invalidResponse
        case httpStatus(Int)
        case invalidPayload
    }

    private let session: URLSession
    private let base = "https://site.api.espn.com/apis/site/v2/sports"
    /// Cap parallel ESPN league requests so first paint isn't starved.
    private let maxConcurrent = 5
    /// Days ahead on America/New_York calendar for scheduled boards.
    /// Default ESPN board often becomes finals/live-only after evening slate
    /// (classic “MLB selected but Upcoming empty” hole).
    private let upcomingDayHorizon = 7

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 14
            config.timeoutIntervalForResource = 28
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
    /// 2. One **date-range** board (today…+horizon, US/Eastern) merged in — fills Upcoming
    ///    when the default slate is already all finals (MLB evening / late night).
    /// onPartial is now async @MainActor @Sendable so callers on MainActor can do
    /// non-suspending work (guard, update, await notifications) before fetch continues.
    /// Awaited end-to-end prevents partial-final race.
    func fetchScoreboards(
        leagues: [SportLeague],
        onPartial: (@MainActor @Sendable ([Game]) async -> Void)? = nil
    ) async -> ScoreboardFetchResult {
        var byId: [String: Game] = [:]
        var successfulBoards = 0
        var failedBoards = 0
        var failedLeagues = Set<SportLeague>()
        let list = leagues

        // Pass 1 — default boards only (fast).
        let current = await fetchLeagues(list, urlsForLeague: { league in
            self.defaultScoreboardURL(for: league).map { [$0] } ?? []
        }, into: &byId, onPartial: onPartial)
        successfulBoards += current.successfulBoards
        failedBoards += current.failedBoards
        failedLeagues.formUnion(current.failedLeagues)

        // Pass 2 — range supplement (scheduled days).
        let upcoming = await fetchLeagues(list, urlsForLeague: { league in
            self.upcomingRangeScoreboardURLs(for: league)
        }, into: &byId, onPartial: onPartial)
        successfulBoards += upcoming.successfulBoards
        failedBoards += upcoming.failedBoards
        failedLeagues.formUnion(upcoming.failedLeagues)

        return ScoreboardFetchResult(
            games: Array(byId.values).sorted(by: Self.sortGames),
            successfulBoards: successfulBoards,
            failedBoards: failedBoards,
            failedLeagues: failedLeagues
        )
    }

    private func fetchLeagues(
        _ leagues: [SportLeague],
        urlsForLeague: (SportLeague) -> [URL],
        into byId: inout [String: Game],
        onPartial: (@MainActor @Sendable ([Game]) async -> Void)?
    ) async -> (successfulBoards: Int, failedBoards: Int, failedLeagues: Set<SportLeague>) {
        var successfulBoards = 0
        var failedBoards = 0
        var failedLeagues = Set<SportLeague>()
        var index = 0
        while index < leagues.count {
            let end = min(index + maxConcurrent, leagues.count)
            let slice = Array(leagues[index..<end])
            let batches: [LeagueFetchResult] = await withTaskGroup(
                of: LeagueFetchResult.self,
                returning: [LeagueFetchResult].self
            ) { group in
                for league in slice {
                    let urls = urlsForLeague(league)
                    group.addTask {
                        await self.fetchAndMerge(urls: urls, league: league)
                    }
                }
                var out: [LeagueFetchResult] = []
                for await batch in group {
                    out.append(batch)
                }
                return out
            }
            for batch in batches {
                successfulBoards += batch.successfulBoards
                failedBoards += batch.failedBoards
                if let league = batch.failedLeague {
                    failedLeagues.insert(league)
                }

                for game in batch.games {
                    if let existing = byId[game.id] {
                        byId[game.id] = Self.prefer(existing, game)
                    } else {
                        byId[game.id] = game
                    }
                }
            }
            // Always publish merged snapshot so Upcoming can fill after pass-1 finals-only boards.
            let snapshot = Array(byId.values).sorted(by: Self.sortGames)
            await onPartial?(snapshot)
            index = end
        }
        return (successfulBoards, failedBoards, failedLeagues)
    }

    private func fetchAndMerge(urls: [URL], league: SportLeague) async -> LeagueFetchResult {
        guard !urls.isEmpty else {
            return LeagueFetchResult(
                games: [],
                successfulBoards: 0,
                failedBoards: 0,
                failedLeague: nil
            )
        }
        var local: [String: Game] = [:]
        var successfulBoards = 0
        var failedBoards = 0
        await withTaskGroup(of: Result<[Game], ScoreboardRequestError>.self) { group in
            for url in urls {
                group.addTask {
                    do {
                        return .success(try await self.fetchScoreboardURL(url, league: league))
                    } catch let error as ScoreboardRequestError {
                        return .failure(error)
                    } catch {
                        return .failure(.invalidResponse)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let batch):
                    successfulBoards += 1
                    for game in batch {
                        if let existing = local[game.id] {
                            local[game.id] = Self.prefer(existing, game)
                        } else {
                            local[game.id] = game
                        }
                    }
                case .failure:
                    failedBoards += 1
                }
            }
        }
        return LeagueFetchResult(
            games: Array(local.values),
            successfulBoards: successfulBoards,
            failedBoards: failedBoards,
            failedLeague: failedBoards > 0 ? league : nil
        )
    }

    nonisolated private static func sortGames(_ a: Game, _ b: Game) -> Bool {
        if a.isLive != b.isLive { return a.isLive && !b.isLive }
        if a.isUpcoming != b.isUpcoming { return a.isUpcoming && !b.isUpcoming }
        return a.startTime < b.startTime
    }

    func fetchScoreboard(league: SportLeague) async throws -> [Game] {
        var urls: [URL] = []
        if let d = defaultScoreboardURL(for: league) { urls.append(d) }
        urls.append(contentsOf: upcomingRangeScoreboardURLs(for: league))
        let result = await fetchAndMerge(urls: urls, league: league)
        guard result.successfulBoards > 0 else {
            throw ScoreboardRequestError.invalidResponse
        }
        return result.games
    }

    private func defaultScoreboardURL(for league: SportLeague) -> URL? {
        URL(string: "\(base)/\(league.sportPath)/\(league.leaguePath)/scoreboard")
    }

    /// Single range request: `?dates=yyyyMMdd-yyyyMMdd&limit=200` on US/Eastern calendar.
    /// More reliable than N single-day calls for Upcoming coverage.
    private func upcomingRangeScoreboardURLs(for league: SportLeague) -> [URL] {
        guard let root = defaultScoreboardURL(for: league)?.absoluteString else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"

        // Start from *today* Eastern (includes late games still "pre" if any);
        // span horizon days forward.
        guard let endDay = calendar.date(byAdding: .day, value: upcomingDayHorizon, to: now) else {
            return []
        }
        let startStamp = formatter.string(from: now)
        let endStamp = formatter.string(from: endDay)
        // Also request tomorrow-only as a cheap second path if range is thin on some sports.
        var urls: [URL] = []
        if let range = URL(string: "\(root)?dates=\(startStamp)-\(endStamp)&limit=200") {
            urls.append(range)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            let t = formatter.string(from: tomorrow)
            if let u = URL(string: "\(root)?dates=\(t)&limit=100") {
                urls.append(u)
            }
        }
        return urls
    }

    private func fetchScoreboardURL(_ url: URL, league: SportLeague) async throws -> [Game] {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw ScoreboardRequestError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw ScoreboardRequestError.httpStatus(http.statusCode) }
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
            throw ScoreboardRequestError.invalidPayload
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
            let state = ((type["state"] as? String) ?? "pre").lowercased()
            let name = ((type["name"] as? String) ?? "").uppercased()
            let completed = type["completed"] as? Bool ?? false
            let shortDetail = type["shortDetail"] as? String
            let detail = type["detail"] as? String

            let status: GameStatus
            if name.contains("POSTPONED") || name.contains("CANCELED") || name.contains("CANCELLED") {
                status = .postponed
            } else if state == "in"
                        || name.contains("IN_PROGRESS")
                        || name.contains("HALFTIME")
                        || name.contains("STATUS_HALFTIME") {
                status = .live
            } else if state == "pre"
                        || name.contains("SCHEDULED")
                        || name.contains("STATUS_SCHEDULED")
                        || name.contains("DELAYED") {
                status = .upcoming
            } else if completed || name.contains("FINAL") || state == "post" {
                status = .final_
            } else {
                status = .unknown
            }

            let dateStr = (comp["date"] as? String) ?? (event["date"] as? String) ?? ""
            let start = Self.parseESPNDate(dateStr) ?? Date.distantPast

            let competitors = comp["competitors"] as? [[String: Any]] ?? []
            var home = TeamInfo(id: "", name: "Home", abbreviation: "HOME")
            var away = TeamInfo(id: "", name: "Away", abbreviation: "AWAY")
            for c in competitors {
                let team = c["team"] as? [String: Any] ?? [:]
                let rawTid: String = {
                    let a = Self.espnJsonId(team["id"])
                    if !a.isEmpty { return a }
                    return Self.espnJsonId(team["uid"])
                }()
                let stableId: String = {
                    let s = Self.stableTeamId(league: league, rawId: rawTid)
                    return s.isEmpty ? UUID().uuidString : s
                }()
                let info = TeamInfo(
                    id: stableId,
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

            if home.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || away.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || home.isPlaceholder || away.isPlaceholder { continue }
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


    /// Full roster for favorite-team picker (Android parity).
    func fetchTeams(league: SportLeague) async -> [TeamInfo] {
        guard let url = URL(string: "\(base)/\(league.sportPath)/\(league.leaguePath)/teams?limit=400") else {
            return []
        }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            return Self.parseTeams(data, league: league)
        } catch {
            return []
        }
    }

    nonisolated private static func parseTeams(_ data: Data, league: SportLeague) -> [TeamInfo] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sports = root["sports"] as? [[String: Any]] else { return [] }
        var out: [TeamInfo] = []
        var seen = Set<String>()
        for sport in sports {
            guard let leagues = sport["leagues"] as? [[String: Any]] else { continue }
            for _leagueObj in leagues {
                guard let teams = _leagueObj["teams"] as? [[String: Any]] else { continue }
                for wrap in teams {
                    let team = (wrap["team"] as? [String: Any]) ?? wrap
                    let raw = {
                        let a = espnJsonId(team["id"])
                        if !a.isEmpty { return a }
                        let b = espnJsonId(team["uid"])
                        if !b.isEmpty { return b }
                        return ""
                    }()
                    // Never fall back to abbreviation — TB collides Bucs/Rays across sports.
                    guard !raw.isEmpty else { continue }
                    let id = stableTeamId(league: league, rawId: raw)
                    guard !id.isEmpty, seen.insert(id).inserted else { continue }
                    var logo: String?
                    if let logos = team["logos"] as? [[String: Any]],
                       let href = logos.first?["href"] as? String, !href.isEmpty {
                        logo = href
                    } else if let l = team["logo"] as? String, !l.isEmpty {
                        logo = l
                    }
                    let name = (team["displayName"] as? String)
                        ?? (team["name"] as? String)
                        ?? (team["shortDisplayName"] as? String)
                        ?? id
                    let abbr = (team["abbreviation"] as? String)
                        ?? String(name.prefix(3)).uppercased()
                    let short = (team["shortDisplayName"] as? String) ?? (team["name"] as? String)
                    out.append(TeamInfo(
                        id: id,
                        name: name,
                        abbreviation: abbr,
                        score: nil,
                        logoURL: logo,
                        colorHex: team["color"] as? String,
                        alternateColorHex: team["alternateColor"] as? String,
                        shortName: short
                    ))
                }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    /// ESPN team ids are only unique **within** a sport/league (NFL 27 = Bucs, MLB 27 = Rockies).
    nonisolated static func stableTeamId(league: SportLeague, rawId: String) -> String {
        let raw = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        if raw.contains(":") { return raw }
        return "\(league.rawValue):\(raw)"
    }

    nonisolated static func espnJsonId(_ value: Any?) -> String {
        switch value {
        case let s as String:
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case let i as Int:
            return String(i)
        case let i as Int64:
            return String(i)
        case let n as NSNumber:
            return n.stringValue
        default:
            return ""
        }
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
