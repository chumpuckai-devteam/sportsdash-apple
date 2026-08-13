import Foundation

#if canImport(UserNotifications)
import UserNotifications
#endif

/// Local notifications for favorite-team game starts and score increases (“goals”).
///
/// - **iOS only** — `UNMutableNotificationContent` title/body/sound are unavailable on tvOS.
/// - No remote push server — compares iOS foreground score polls and schedules calendar start alerts.
/// - Android's separate helper only observes existing app-driven refreshes; it does not share
///   this service's start-soon scheduler or iOS 45-second polling owner.
/// - Master off by default (`PlayerPrefs.notificationsEnabled`).
///
/// See `docs/game-notifications.md`.
@MainActor
final class GameNotificationService {
    static let shared = GameNotificationService()

    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        #if os(iOS)
        return await IOSImpl.shared.requestAuthorizationIfNeeded()
        #else
        return false
        #endif
    }

    /// Call after each scores refresh (partial or final).
    /// touchStartSchedules=false (for BG refresh) leaves all start-soon schedules and just-started
    /// emission untouched (avoids deleting ATL start-soon etc when using partial boards or notifyStarts:false).
    /// When true (default): if notifyStarts then schedule+emitJust, else clearPendingStarts.
    func process(
        games: [Game],
        favoriteTeamIds: Set<String>,
        notifyStarts: Bool,
        notifyGoals: Bool,
        masterEnabled: Bool,
        touchStartSchedules: Bool = true
    ) async {
        #if os(iOS)
        await IOSImpl.shared.process(
            games: games,
            favoriteTeamIds: favoriteTeamIds,
            notifyStarts: notifyStarts,
            notifyGoals: notifyGoals,
            masterEnabled: masterEnabled,
            touchStartSchedules: touchStartSchedules
        )
        #else
        _ = (games, favoriteTeamIds, notifyStarts, notifyGoals, masterEnabled, touchStartSchedules)
        #endif
    }

    // Exposed pure helpers for unit tests (via @testable)
    #if DEBUG
    static func test_scoreDidIncrease(currentHome: Int?, currentAway: Int?, prevHome: Int?, prevAway: Int?) -> Bool {
        #if os(iOS)
        return IOSImpl.scoreDidIncrease(currentHome: currentHome, currentAway: currentAway, prevHome: prevHome, prevAway: prevAway)
        #else
        return false
        #endif
    }
    static func test_snapshotFrom(_ g: Game) -> GameNotificationService.TestSnapshot? {
        #if os(iOS)
        let s = IOSImpl.snapshotFrom(g)
        return GameNotificationService.TestSnapshot(home: s.home, away: s.away, status: s.status, updatedAt: s.updatedAt)
        #else
        return nil
        #endif
    }

    static func test_goalId(gameId: String, home: Int?, away: Int?) -> String {
        let h = home ?? 0
        let a = away ?? 0
        return "goal-\(gameId)-\(h)-\(a)"
    }

    static func test_mergeSnapshots(existing: [String: TestSnapshot], observed: [String: TestSnapshot]) -> [String: TestSnapshot] {
        #if os(iOS)
        let ex: [String: IOSImpl.Snapshot] = existing.mapValues { ts in
            IOSImpl.Snapshot(home: ts.home, away: ts.away, status: ts.status, updatedAt: ts.updatedAt)
        }
        let ob: [String: IOSImpl.Snapshot] = observed.mapValues { ts in
            IOSImpl.Snapshot(home: ts.home, away: ts.away, status: ts.status, updatedAt: ts.updatedAt)
        }
        let merged = IOSImpl.mergeSnapshots(existing: ex, observed: ob)
        return merged.mapValues { s in
            GameNotificationService.TestSnapshot(home: s.home, away: s.away, status: s.status, updatedAt: s.updatedAt)
        }
        #else
        var result = existing
        for (k, v) in observed {
            result[k] = v
        }
        return result
        #endif
    }

    static func test_pruneByAge(_ snaps: [String: TestSnapshot]) -> [String: TestSnapshot] {
        #if os(iOS)
        let real: [String: IOSImpl.Snapshot] = snaps.mapValues { ts in
            IOSImpl.Snapshot(home: ts.home, away: ts.away, status: ts.status, updatedAt: ts.updatedAt)
        }
        let pruned = IOSImpl.pruneByAge(real)
        return pruned.mapValues { s in
            GameNotificationService.TestSnapshot(home: s.home, away: s.away, status: s.status, updatedAt: s.updatedAt)
        }
        #else
        let now = Date()
        let c48 = now.addingTimeInterval(-48 * 3600)
        let c6 = now.addingTimeInterval(-6 * 3600)
        var out: [String: TestSnapshot] = [:]
        for (k, s) in snaps {
            if s.updatedAt < c48 { continue }
            if s.status == .final_ && s.updatedAt < c6 { continue }
            out[k] = s
        }
        return out
        #endif
    }

    static func test_startScheduleAction(touchStartSchedules: Bool, notifyStarts: Bool) -> String {
        #if os(iOS)
        return IOSImpl.startScheduleAction(touchStartSchedules: touchStartSchedules, notifyStarts: notifyStarts)
        #else
        return "none"
        #endif
    }
    #endif
}

// Test support types (DEBUG)
#if DEBUG
extension GameNotificationService {
    struct TestSnapshot {
        var home: Int?
        var away: Int?
        var status: GameStatus
        var updatedAt: Date = Date()
    }
}
#endif

#if os(iOS)

@MainActor
final class IOSImpl {
    static let shared = IOSImpl()

    private let center = UNUserNotificationCenter.current()
    private var lastScores: [String: Snapshot] = [:]
    private var lastGoalFire: [String: Date] = [:]
    private var deliveredStartNow: Set<String> = []
    private var deliveredGoals: Set<String> = []
    private let goalCooldown: TimeInterval = 45
    private let startLead: TimeInterval = 5 * 60

    struct Snapshot {
        var home: Int?
        var away: Int?
        var status: GameStatus
        var updatedAt: Date = Date()
    }

    // Persisted form for UserDefaults (cold-start catch-up for score increases / just-started)
    struct PersistedSnapshot: Codable {
        var home: Int?
        var away: Int?
        var statusRaw: String
        var updatedAt: Date
    }

    private let lastScoresDiskKey = "last_game_scores_snapshots_v1"

    #if DEBUG
    internal static var testUserDefaults: UserDefaults?
    internal func testLoadPersistedLastScores() -> [String: Snapshot] {
        loadPersistedLastScores()
    }
    internal func testPersistLastScores(_ snaps: [String: Snapshot]) {
        persistLastScores(snaps)
    }
    #endif

    private var effectiveUserDefaults: UserDefaults {
        #if DEBUG
        return IOSImpl.testUserDefaults ?? UserDefaults.standard
        #else
        return UserDefaults.standard
        #endif
    }

    private init() {}

    // MARK: - Pure testable helpers (for unit tests + logic reuse)
    static func scoreDidIncrease(currentHome: Int?, currentAway: Int?, prevHome: Int?, prevAway: Int?) -> Bool {
        let h = currentHome ?? 0
        let a = currentAway ?? 0
        let ph = prevHome ?? 0
        let pa = prevAway ?? 0
        return h > ph || a > pa
    }

    static func snapshotFrom(_ g: Game) -> Snapshot {
        Snapshot(home: g.home.score, away: g.away.score, status: g.status, updatedAt: Date())
    }

    // Pure merge: start from existing (keeps keys not in observed), overwrite/add from observed. Never drops prior keys.
    static func mergeSnapshots(existing: [String: Snapshot], observed: [String: Snapshot]) -> [String: Snapshot] {
        var result = existing
        for (id, snap) in observed {
            result[id] = snap
        }
        return result
    }

    static func pruneByAge(_ snaps: [String: Snapshot]) -> [String: Snapshot] {
        let now = Date()
        let c48 = now.addingTimeInterval(-48 * 3600)
        let c6 = now.addingTimeInterval(-6 * 3600)
        var out: [String: Snapshot] = [:]
        for (k, s) in snaps {
            if s.updatedAt < c48 { continue }
            if s.status == .final_ && s.updatedAt < c6 { continue }
            out[k] = s
        }
        return out
    }

    /// Pure decision helper for start-schedule vs clear logic (extracted for tests).
    /// Returns "schedule" | "clear" | "none"
    /// if !touchStartSchedules -> "none"; else if notifyStarts -> "schedule"; else "clear"
    static func startScheduleAction(touchStartSchedules: Bool, notifyStarts: Bool) -> String {
        if !touchStartSchedules {
            return "none"
        } else if notifyStarts {
            return "schedule"
        } else {
            return "clear"
        }
    }

    // MARK: - Disk persistence for lastScores (UserDefaults dedicated key)
    private func loadPersistedLastScores() -> [String: Snapshot] {
        let ud = effectiveUserDefaults
        guard let data = ud.data(forKey: lastScoresDiskKey) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let persisted = try? decoder.decode([String: PersistedSnapshot].self, from: data) else { return [:] }
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        var result: [String: Snapshot] = [:]
        for (key, p) in persisted where p.updatedAt > cutoff {
            let st = GameStatus(rawValue: p.statusRaw) ?? .unknown
            result[key] = Snapshot(home: p.home, away: p.away, status: st, updatedAt: p.updatedAt)
        }
        return result
    }

    private func persistLastScores(_ snaps: [String: Snapshot]) {
        var toSave: [String: PersistedSnapshot] = [:]
        for (key, s) in snaps {
            toSave[key] = PersistedSnapshot(
                home: s.home,
                away: s.away,
                statusRaw: s.status.rawValue,
                updatedAt: s.updatedAt
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(toSave) {
            let ud = effectiveUserDefaults
            ud.set(data, forKey: lastScoresDiskKey)
        }
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    func process(
        games: [Game],
        favoriteTeamIds: Set<String>,
        notifyStarts: Bool,
        notifyGoals: Bool,
        masterEnabled: Bool,
        touchStartSchedules: Bool = true
    ) async {
        guard masterEnabled else {
            // clear baselines + disk to avoid catch-up spam on re-enable
            lastScores = [:]
            effectiveUserDefaults.removeObject(forKey: lastScoresDiskKey)
            if touchStartSchedules {
                await clearPendingStarts()
            }
            persistLastScores(lastScores)
            return
        }
        guard !favoriteTeamIds.isEmpty else {
            if touchStartSchedules {
                await clearPendingStarts()
            }
            // do not wipe all baselines
            return
        }

        // Seed lastScores from disk (or merge missing keys) BEFORE emit so cold-start/after-kill
        // can detect score increases or just-started using prior persisted state.
        if lastScores.isEmpty {
            lastScores = loadPersistedLastScores()
        } else {
            let disk = loadPersistedLastScores()
            for (k, v) in disk where lastScores[k] == nil {
                lastScores[k] = v
            }
        }

        let favGames = games.filter {
            favoriteTeamIds.contains($0.home.id) || favoriteTeamIds.contains($0.away.id)
        }

        if notifyGoals {
            await emitGoals(favGames: favGames)
        }

        let action = Self.startScheduleAction(touchStartSchedules: touchStartSchedules, notifyStarts: notifyStarts)
        if action == "schedule" {
            await scheduleStarts(favGames: favGames.filter(\.isUpcoming))
            await emitJustStarted(favGames: favGames)
        } else if action == "clear" {
            await clearPendingStarts()
        }
        // else "none": BG path (touchStartSchedules=false) — never scheduleStarts, never clearPendingStarts,
        // never emitJustStarted. This prevents BG partial-board calls (which use notifyStarts:false)
        // from deleting pre-scheduled "start-soon" notifications. Goals run independently if notifyGoals.
        // (emitJustStarted would also remove pending "start-*" requests.)

        // Merge (update/insert observed) instead of full replace to never drop keys for games missing from this snapshot
        let observed = snapshotMap(games)
        lastScores = IOSImpl.mergeSnapshots(existing: lastScores, observed: observed)
        lastScores = IOSImpl.pruneByAge(lastScores)
        pruneDeliveryMemory()
        // Persist at least the observed (favored) games; load prunes >48h
        persistLastScores(lastScores)
    }

    private func emitGoals(favGames: [Game]) async {
        let now = Date()
        for g in favGames where g.isLive {
            guard let prev = lastScores[g.id] else { continue }
            let h = g.home.score ?? 0
            let a = g.away.score ?? 0
            let ph = prev.home ?? 0
            let pa = prev.away ?? 0
            guard Self.scoreDidIncrease(currentHome: h, currentAway: a, prevHome: ph, prevAway: pa) else { continue }
            if let last = lastGoalFire[g.id], now.timeIntervalSince(last) < goalCooldown {
                continue
            }
            let id = "goal-\(g.id)-\(h)-\(a)"
            if deliveredGoals.contains(id) { continue }
            lastGoalFire[g.id] = now
            deliveredGoals.insert(id)
            let scorer: String
            if h > ph && !(a > pa) {
                scorer = g.home.rowLabel
            } else if a > pa && !(h > ph) {
                scorer = g.away.rowLabel
            } else {
                scorer = "Score update"
            }
            await post(
                id: id,
                title: "Score · \(g.matchupLabel)",
                body: "\(scorer) · \(g.away.abbreviation) \(a)–\(h) \(g.home.abbreviation)"
            )
        }
    }

    private func emitJustStarted(favGames: [Game]) async {
        for g in favGames where g.isLive {
            guard let prev = lastScores[g.id] else { continue }
            guard prev.status == .upcoming || prev.status == .unknown else { continue }
            let id = "start-now-\(g.id)"
            if deliveredStartNow.contains(id) { continue }
            deliveredStartNow.insert(id)
            center.removePendingNotificationRequests(withIdentifiers: ["start-\(g.id)"])
            await post(
                id: id,
                title: "Game started",
                body: "\(g.matchupLabel) is live · \(g.statusLine)"
            )
        }
    }

    private func scheduleStarts(favGames: [Game]) async {
        let keepIds = Set(favGames.map { "start-\($0.id)" })
        await pruneStaleStartRequests(keeping: keepIds)

        for g in favGames {
            let fire = g.startTime.addingTimeInterval(-startLead)
            guard fire > Date() else { continue }
            let id = "start-\(g.id)"
            center.removePendingNotificationRequests(withIdentifiers: [id])

            let content = UNMutableNotificationContent()
            content.title = "Game starting soon"
            content.body = "\(g.matchupLabel) starts in about 5 minutes"
            content.sound = .default
            content.threadIdentifier = "game-start"
            content.userInfo = ["gameId": g.id, "kind": "start"]

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fire
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(req)
        }
    }

    private func post(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = id.hasPrefix("goal-") ? "game-goal" : "game-start"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await center.add(req)
    }

    private func clearPendingStarts() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix("start-") }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func pruneStaleStartRequests(keeping: Set<String>) async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { id in
            id.hasPrefix("start-") && !keeping.contains(id)
        }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    private func snapshotMap(_ games: [Game]) -> [String: Snapshot] {
        Dictionary(uniqueKeysWithValues: games.map {
            ($0.id, Snapshot(home: $0.home.score, away: $0.away.score, status: $0.status, updatedAt: Date()))
        })
    }

    private func pruneDeliveryMemory() {
        if deliveredGoals.count > 200 {
            deliveredGoals.removeAll(keepingCapacity: true)
        }
        if deliveredStartNow.count > 100 {
            deliveredStartNow.removeAll(keepingCapacity: true)
        }
        if lastGoalFire.count > 100 {
            let cutoff = Date().addingTimeInterval(-3600)
            lastGoalFire = lastGoalFire.filter { $0.value > cutoff }
        }
    }
}

#endif
