# Favorite-team game notifications

**Local only** (no push server). Driven by ESPN scores refresh.

## Types
1. **Game starting soon** (iOS) — scheduled ~5 minutes before tip for upcoming favorite-team games.
2. **Game started** — when a favorite-team game flips to live on poll.
3. **Goal / score change** — when home or away score changes on a live favorite-team game (45s cooldown per game).

## Settings
- **Game alerts** master toggle (requests OS permission when enabled).
- **Game starting soon**
- **Goals / score changes**

## Platforms
| | iOS | Android |
|--|-----|---------|
| API | UserNotifications | NotificationCompat + POST_NOTIFICATIONS (33+) |
| Scope | Favorite team ids only | Same |
| Poll | `AppModel.refreshScores` | `AppViewModel.refreshScores` |

## Limits
- Not a substitute for live push — phone must refresh scores (foreground / periodic app use).
- Cast / multiview intentionally out of scope.
