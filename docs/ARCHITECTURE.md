# SportsDash Architecture (2026-08)

## Goals
- Native multi-platform: **iOS + tvOS** (SwiftUI) + **Android** (Jetpack Compose) in a **single monorepo**.
- Hard IPTV engine using **VLC family** (LGPL) to avoid GPL App Store risk.
- Strong phone baseline first, then 10-foot TV surfaces.
- Parity between platforms before major net-new features.

## Current Repository Structure
- `SportsDash/` — SwiftUI app (iOS + tvOS)
- `android/` — Kotlin + Compose app (same `applicationId`)
- `docs/` — product decisions, parity matrix, TV surfaces
- `Project.yml` + `Podfile` — xcodegen + CocoaPods (VLCKit / TVVLCKit)
- `android/build.gradle.kts` — libVLC (`org.videolan.android:libvlc-all`)

Both platforms live in `sportsdash-apple` (rename to `sportsdash` planned later).

## Modules (Swift side)
| Area                  | Responsibility |
|-----------------------|----------------|
| App                   | Lifecycle, `AppModel`, tabs (Scores · Guide · Settings) |
| Core/Models           | `Game`, `SportLeague`, IPTV types, `PlayerPrefs` |
| Core/Services         | `SportsAPI`, `IptvService`, `EpgService`, `MatchingService`, `GameNotificationService` (iOS only) |
| Features/Player       | `PlaybackController` (multi-engine), `PlayerView`, chrome |
| Features/Scores       | Phone list + TV Netflix-style rails |
| Features/Guide        | Timeline + Grid, category picker |
| Theme                 | Colors, `PlatformChrome`, TV focus helpers (`SportsTVFocused`) |

## Player Strategy
**Apple (iOS + tvOS)**: `PlaybackController`
- Auto routing: TS / unknown → **VLCKit** (MobileVLCKit / TVVLCKit); clean HLS → **AVPlayer**
- Explicit override in Settings
- Floating mini-player (phone only) + full-screen

**Android**: `VlcPlayerController`
- libVLC only (same family as Apple)
- TextureView for Compose overlays
- Audio focus + volume boost (0–200)

Intentional delta: Android is currently VLC-only. Dual-engine + fallback is Apple-only for now.

## Scores & Favorites
- ESPN-powered scores.
- **Favorite teams only** (no bare channels in Scores).
- **League-scoped IDs** (e.g. `nfl:27` vs `mlb:27`) to prevent cross-sport collisions.
- On TV: Netflix-style horizontal rails ("My Games" first, then per-sport).
- On phone: Dense one-row chrome + vertical list.

## TV Surfaces (10-foot)
- **Apple TV** (`SportsDashTV` scheme): fullScreenCover player, focus rings, horizontal rails.
- **Android TV**: `LEANBACK_LAUNCHER`, `DeviceProfile.isTelevision`, `TvFocus` helpers.
- PlatformChrome gates iOS-only APIs.
- Shell (tabs) stays visible on TV (unlike phone landscape).

See `docs/tv-surfaces.md` for current status and dogfood steps.

## Platform Differences (Intentional)
- Presentation: fullScreenCover on TV vs sheet on phone for some flows.
- Floating player: iOS only.
- Notifications: local favorite-team alerts (iOS only).
- Engine: Apple dual + fallback; Android VLC-only.

## Build & Workflow
- iOS/tvOS: `xcodegen generate && pod install && open SportsDash.xcworkspace`
- Android: Open `android/` folder in Android Studio or `./gradlew :app:assembleDebug`
- Always prefer **install-over** on Android to preserve login (see `docs/android-login-persist.md`).
- TV dogfood: Apple TV simulator (SportsDashTV scheme) + Android TV AVD.

## Documentation
- `docs/dual-platform-parity.md` — baseline matrix
- `docs/tv-surfaces.md` — TV specific
- `docs/game-notifications.md`
- `android/README.md`

## Historical Notes (kept for context)
- Early Flutter prototype existed (different repo).
- Early plan was separate `sportsdash-android` repo. That plan was abandoned in favor of the current monorepo.
- KSPlayer and other GPL engines were evaluated and removed.

## Current Focus Areas (as of 2026-08)
- TV polish (Netflix cards, focus, player sizing)
- Continued parity enforcement
- Local notifications (shipped)
- EPG experience
