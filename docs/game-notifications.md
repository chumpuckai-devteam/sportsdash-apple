# Favorite-team game notifications

SportsDash game alerts are local-only. There is no push server, remote notification pipeline, WorkManager job (Android), or Android alarm in this release. Alerts are best-effort within OS local-notification and background limits.

## Product contract

Scores favorites = teams only. Guide favorites = channels; Guide channel stars do not create game alerts.

All alerts require the Game alerts master switch, OS notification permission, the relevant subtype switch, and a game containing a favorite team ID.

| Alert | iOS | Android |
|---|---|---|
| Game starting soon | Schedules a one-shot local notification about five minutes before a known upcoming start (UNCalendarNotificationTrigger). Can fire when app suspended/killed. | Not supported; no alarm or background scheduler is installed |
| Game just started | Emitted when the foreground score poll observes upcoming/unknown → live (BG does score-ups only, not just-started) | Emitted only when an app-driven score refresh (or in-process ticker) observes upcoming/unknown → live transition |
| Goal / score change | Emitted when poll/BG observes a live score increase; per-game cooldown ~45s. Uses persisted last score snapshot for cold-start catch-up. | Emitted only when refresh/ticker observes live score increase (helper applies ~45s cooldown + persisted snapshot for catch-up on open) |

## Refresh ownership (best-effort)

### iOS
`AppModel.startScoresPolling()` starts a 45-second in-process timer (RunLoop.main + .common modes) while the app is running/foreground. When `scenePhase == .active` a silent `refreshScores` is triggered.

When master + (goals or starts) enabled: registers `BGAppRefreshTask` ("com.samirpatel.sportsdash.scores-refresh") best-effort (15min+ earliest). iOS may throttle or skip.

`lastScores` snapshots are persisted to UserDefaults (pruned >48h) so relaunch/cold-start can detect increases since last successful process. Do not notify on first observation of a game.

Upcoming favorite-team games also create OS-scheduled, one-shot start-soon notifications (calendar), which survive app death.

Score-change (goals) alerts depend on poll or BG task; just-started only from foreground poll. May be delayed/absent when iOS suspends the app.

### Android
`AppViewModel` runs a ViewModel-scoped repeating ~45s coroutine ticker (while process alive and master + goals/starts on) that calls `refreshScores()`. Cancels on toggle off or clear.

`lastScores` snapshots persisted via SharedPreferences for catch-up on cold open / process death.

`AppViewModel.refreshScores()` invokes `GameNotificationHelper` after init, manual refresh, league toggle, etc. No WorkManager / Alarm (none added per constraints). Alerts are observed during app-driven or ticker refreshes.

## Settings

- Game alerts: master opt-in; requests OS permission.
- Game starting soon: enables start-transition alerts + scheduled 5min reminders on iOS only.
- Goals / score changes: enables score-increase alerts. **Score changes require the app to refresh scores (open the app or iOS background refresh best-effort). Start-soon can still fire from iOS schedule.**
- Defaults remain off until the user opts in.
- tvOS uses a no-op `GameNotificationService` surface; notification controls are iOS-only.

## Limits and non-goals

- No remote push, server, guaranteed delivery, WorkManager, or Android alarm.
- No alert parity claim: iOS has scheduled start-soon + 45s poll + BG best-effort + disk snapshot; Android has in-process ticker + app-refresh + snapshot catch-up.
- Cast and multiview remain out of scope.
- ~45s per-game cooldown; increases only.
- Master off by default; starts + goals subtype toggles.

See code: `GameNotificationService.swift`, `GameNotificationHelper.kt`, `AppModel.swift`, `AppViewModel.kt`, `RootTabView.swift`, `SportsDashApp.swift`.
