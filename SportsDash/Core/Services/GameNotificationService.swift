import Foundation
import UserNotifications

/// Local **UserNotifications** for favorite-team game starts and score increases (“goals”).
///
/// - No remote push server — compares scoreboard polls and schedules calendar start alerts.
/// - Master off by default (`PlayerPrefs.notificationsEnabled`); not a Sprint 1 release gate.
/// - Non-favorites never notify. Cooldown + stable identifiers limit spam.
///
/// See `docs/game-notifications.md`.
@MainActor
final class GameNotificationService {
    static let shared = GameNotificationService()

    private let center = UNUserNotificationCenter.current()

    /// Last known score/status by game id (full board snapshot, not favorites-only).
    private var lastScores: [String: Snapshot] = [:]
    /// Last goal/score-change fire time per game (rate limit).
    private var lastGoalFire: [String: Date] = [:]
    /// Delivered immediate “game started” ids this session (dedupe rapid polls).
    private var deliveredStartNow: Set<String> = []
    /// Delivered goal notification ids this session (dedupe same score line).
    private var deliveredGoals: Set<String> = []

    /// Minimum gap between score-change alerts for the same game.
    private let goalCooldown: TimeInterval = 45
    /// How far before tip-off to fire the scheduled “starting soon” alert.
    private let startLead: TimeInterval = 5 * 60

    private struct Snapshot {
        var home: Int?
        var away: Int?
        var status: GameStatus
    }

    private init() {}

    // MARK: - Auth

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

    // MARK: - Entry

    /// Call after each scores refresh (partial or final).
    func process(
        games: [Game],
        favoriteTeamIds: Set<String>,
        notifyStarts: Bool,
        notifyGoals: Bool,
        masterEnabled: Bool
    ) async {
        guard masterEnabled else {
            lastScores = snapshotMap(games)
            await clearManagedPending()
            return
        }
        guard !favoriteTeamIds.isEmpty else {
            lastScores = snapshotMap(games)
            await clearManagedPending()
            return
        }

        let favGames = games.filter { isFavorite($0, favoriteTeamIds: favoriteTeamIds) }

        if notifyGoals {
            await emitGoals(favGames: favGames)
        }
        if notifyStarts {
            await scheduleStarts(favGames: favGames.filter(\.isUpcoming))
            await emitJustStarted(favGames: favGames)
        } else {
            await clearPendingStarts()
        }

        lastScores = snapshotMap(games)
        pruneDeliveryMemory()
    }

    // MARK: - Favorites

    private func isFavorite(_ game: Game, favoriteTeamIds: Set<String>) -> Bool {
        favoriteTeamIds.contains(game.home.id) || favoriteTeamIds.contains(game.away.id)
    }

    // MARK: - Goals / score increases

    private func emitGoals(favGames: [Game]) async {
        let now = Date()
        for g in favGames where g.isLive {
            guard let prev = lastScores[g.id] else { continue }

            let h = g.home.score ?? 0
            let a = g.away.score ?? 0
            let ph = prev.home ?? 0
            let pa = prev.away ?? 0

            // Only score *increases* (goals / points). Corrections downward are ignored.
            let homeUp = h > ph
            let awayUp = a > pa
            guard homeUp || awayUp else { continue }

            if let last = lastGoalFire[g.id], now.timeIntervalSince(last) < goalCooldown {
                continue
            }

            let id = "goal-\(g.id)-\(h)-\(a)"
            if deliveredGoals.contains(id) { continue }

            lastGoalFire[g.id] = now
            deliveredGoals.insert(id)

            let scorer: String
            if homeUp && !awayUp {
                scorer = g.home.rowLabel
            } else if awayUp && !homeUp {
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

    // MARK: - Starts

    private func emitJustStarted(favGames: [Game]) async {
        for g in favGames where g.isLive {
            guard let prev = lastScores[g.id] else { continue }
            guard prev.status == .upcoming || prev.status == .unknown else { continue }

            let id = "start-now-\(g.id)"
            if deliveredStartNow.contains(id) { continue }
            deliveredStartNow.insert(id)

            // Drop the scheduled “starting soon” once live.
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

    // MARK: - Post + cleanup

    private func post(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = id.hasPrefix("goal-") ? "game-goal" : "game-start"
        // Immediate delivery (app must be backgrounded / not foreground-suppressed by system).
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await center.add(req)
    }

    private func clearManagedPending() async {
        await clearPendingStarts()
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
            ($0.id, Snapshot(home: $0.home.score, away: $0.away.score, status: $0.status))
        })
    }

    private func pruneDeliveryMemory() {
        // Bound memory if the user leaves the app running across many games.
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
