# Favorite-team game notifications

SportsDash game alerts are local-only. There is no push server, remote notification pipeline, WorkManager job, or Android alarm in this release.

## Product contract

Scores favorites = teams only. Guide favorites = channels; Guide channel stars do not create game alerts.

All alerts require the Game alerts master switch, OS notification permission, the relevant subtype switch, and a game containing a favorite team ID.

| Alert | iOS | Android |
|---|---|---|
| Game starting soon | Schedules a one-shot local notification about five minutes before a known upcoming start | Not supported; no alarm or background scheduler is installed |
| Game just started | Emitted when the foreground score poll observes upcoming/unknown → live | Emitted only when an app-driven score refresh observes upcoming/unknown → live transition (score changes observed on refresh include live game state)
| Goal / score change | Emitted when the foreground score poll observes a live score increase; per-game cooldown ~45s | Emitted only when an app-driven score refresh observes a live score increase (helper applies ~45s cooldown); score state changes observed during live games |

## Refresh ownership

### iOS

`AppModel.startScoresPolling()` starts a 45-second in-process timer while the app is running. Each `refreshScores` result is passed to `GameNotificationService`. Upcoming favorite-team games also create OS-scheduled, one-shot start-soon notifications, which may fire after the app leaves the foreground once they have been scheduled.

This is not live push. Just-started and score-change alerts depend on the app's foreground polling and may be delayed or absent when iOS suspends the app.

### Android

`AppViewModel.refreshScores()` invokes `GameNotificationHelper` after refreshes caused by app initialization, user refresh, or other existing in-app refresh paths. Android does not currently run a recurring foreground poll and does not install WorkManager, an alarm, or push delivery in this slice. Therefore Android alerts are refresh-observed, not scheduled or background-reliable.

## Settings

- Game alerts: master opt-in; requests OS permission.
- Game starting soon: enables start-transition alerts on both phones and scheduled five-minute reminders on iOS only.
- Goals / score changes: enables refresh-observed score-increase alerts.
- Defaults remain off until the user opts in.
- tvOS uses a no-op `GameNotificationService` surface; notification controls are iOS-only.

## Limits and non-goals

- No remote push, server, WorkManager, Android alarm, or guaranteed background score monitoring.
- No alert parity claim: iOS has scheduled start-soon plus a 45-second foreground poll; Android has app-refresh-observed alerts.
- Cast and multiview remain out of scope.
