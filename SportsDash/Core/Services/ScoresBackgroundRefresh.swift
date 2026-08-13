import Foundation

#if os(iOS)
import BackgroundTasks
#endif

/// iOS-only background refresh singleton for scores (to drive notifications when app is suspended).
/// No dependency on AppModel, SwiftUI, or UI state. Uses StorageService + direct fetch + process.
#if os(iOS)
final class ScoresBackgroundRefresh {
    static let shared = ScoresBackgroundRefresh()

    private init() {}

    private let identifier = "com.samirpatel.sportsdash.scores-refresh"

    /// Register handler with BGTaskScheduler. Must be called early (from AppDelegate didFinishLaunching).
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(task: task)
        }
    }

    private func handle(task: BGAppRefreshTask) {
        let finishedLock = NSLock()
        var finished = false

        func complete(_ ok: Bool) {
            finishedLock.lock()
            defer { finishedLock.unlock() }
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: ok)
        }

        let work = Task { @MainActor in
            do {
                let prefs = StorageService.shared.playerPrefs()
                let favoriteTeamIds = StorageService.shared.favoriteTeamIds()
                if !prefs.notificationsEnabled {
                    complete(true)
                    self.scheduleIfNeeded(notificationsEnabled: prefs.notificationsEnabled, notifyGoals: prefs.notifyGoals, notifyStarts: prefs.notifyGameStarts)
                    return
                }
                if favoriteTeamIds.isEmpty {
                    complete(true)
                    self.scheduleIfNeeded(notificationsEnabled: prefs.notificationsEnabled, notifyGoals: prefs.notifyGoals, notifyStarts: prefs.notifyGameStarts)
                    return
                }
                let api = SportsAPI()
                let leagues = StorageService.shared.selectedLeagues()
                let result = await api.fetchScoreboards(leagues: leagues)

                if Task.isCancelled {
                    complete(false)
                    self.scheduleIfNeeded(notificationsEnabled: prefs.notificationsEnabled, notifyGoals: prefs.notifyGoals, notifyStarts: prefs.notifyGameStarts)
                    return
                }

                if result.allBoardsFailed {
                    // Do not call process with empty games: that would pruneStaleStartRequests(keeping:[]) and delete scheduled start-soon notifications.
                    complete(false)
                    self.scheduleIfNeeded(notificationsEnabled: prefs.notificationsEnabled, notifyGoals: prefs.notifyGoals, notifyStarts: prefs.notifyGameStarts)
                    return
                }
                if result.games.isEmpty {
                    // Games empty for any reason (even with favorites) — skip process entirely to avoid empty payload clearing starts.
                    // (merge baseline keeps prior keys; on partial boards we only process present games when not empty)
                    complete(true)
                    self.scheduleIfNeeded(notificationsEnabled: prefs.notificationsEnabled, notifyGoals: prefs.notifyGoals, notifyStarts: prefs.notifyGameStarts)
                    return
                }

                await GameNotificationService.shared.process(
                    games: result.games,
                    favoriteTeamIds: favoriteTeamIds,
                    notifyStarts: false,
                    notifyGoals: prefs.notifyGoals,
                    masterEnabled: prefs.notificationsEnabled,
                    touchStartSchedules: false
                )

                if Task.isCancelled {
                    complete(false)
                    self.scheduleIfNeeded(notificationsEnabled: prefs.notificationsEnabled, notifyGoals: prefs.notifyGoals, notifyStarts: prefs.notifyGameStarts)
                    return
                }

                complete(true)
                // rearm next BG
                self.scheduleIfNeeded(notificationsEnabled: prefs.notificationsEnabled, notifyGoals: prefs.notifyGoals, notifyStarts: prefs.notifyGameStarts)
            } catch {
                complete(false)
                // rearm on failure too
                let prefs = StorageService.shared.playerPrefs()
                self.scheduleIfNeeded(notificationsEnabled: prefs.notificationsEnabled, notifyGoals: prefs.notifyGoals, notifyStarts: prefs.notifyGameStarts)
            }
        }

        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in
                let prefs = StorageService.shared.playerPrefs()
                complete(false)
                self.scheduleIfNeeded(notificationsEnabled: prefs.notificationsEnabled, notifyGoals: prefs.notifyGoals, notifyStarts: prefs.notifyGameStarts)
            }
        }
    }

    /// Cancel + submit if master on and (goals or starts) requested. earliest 15min.
    func scheduleIfNeeded(prefs: PlayerPrefs) {
        scheduleIfNeeded(
            notificationsEnabled: prefs.notificationsEnabled,
            notifyGoals: prefs.notifyGoals,
            notifyStarts: prefs.notifyGameStarts
        )
    }

    func scheduleIfNeeded(notificationsEnabled: Bool, notifyGoals: Bool, notifyStarts: Bool) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)

        guard notificationsEnabled && (notifyGoals || notifyStarts) else { return }

        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Fail soft — background fetch not guaranteed; foreground + scene active will cover.
        }
    }
}
#endif
