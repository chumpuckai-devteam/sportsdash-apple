# SportsDash Architecture (2026-08)

## Goals

- Native multi-platform product: iOS + tvOS in SwiftUI and Android phone + Android TV in Jetpack Compose, in one monorepo.
- VLC-family hard IPTV playback under LGPL; Apple also uses AVPlayer for clean HLS.
- Phone baseline and explicit 10-foot TV surfaces, with parity claims limited to behavior that actually ships.
- No secrets in source or documentation.

## Repository structure

- `SportsDash/` — shared SwiftUI sources for iOS and tvOS.
- `android/` — Kotlin/Compose application for Android phone and Android TV.
- `docs/` — product contracts, parity, TV, notification, engine, EPG, and dogfood guidance.
- `Project.yml` + `Podfile` — XcodeGen and CocoaPods for MobileVLCKit/TVVLCKit.
- `android/app/build.gradle.kts` — Android app dependencies, including `org.videolan.android:libvlc-all`.

The repository remains named `sportsdash-apple` for now; that name does not imply a separate Android repository.

## Apple modules

| Area | Responsibility |
|---|---|
| App | Lifecycle, `AppModel`, Scores · Guide · Settings navigation, refresh orchestration |
| Core/Models | Games, leagues, IPTV types, player preferences |
| Core/Services | ESPN, IPTV, EPG, matching, storage, ratings, and iOS notification service with tvOS no-op surface |
| Features/Player | `PlaybackController`, AVPlayer/VLCKit surfaces, full-screen player chrome, iPhone/iPad floating player |
| Features/Scores | Phone list and tvOS horizontal rails |
| Features/Guide | Timeline, grid, category presentation, channel favorites |
| Theme | Tokens, `PlatformChrome`, and TV focus helpers |

## Player strategy

Apple:

- Auto routes MPEG-TS/unknown/Xtream live streams to MobileVLCKit or TVVLCKit.
- Clean HLS routes to AVPlayer.
- User override and one cross-engine fallback are Apple-only capabilities.
- Player presentation is a `fullScreenCover` on iOS and tvOS.
- Floating mini-player/pop-out is iOS/iPadOS only and never appears on tvOS or Android TV (removed/gated).

Android:

- `VlcPlayerController` uses libVLC 3.6.x for all supported streams.
- TextureView supports Compose overlays and video rebind on stream switch.
- Floating mini-player / pop-out exists on phone only. TV (both platforms) full-screen only; pop-out removed.

Android's single-engine implementation is an intentional delta, not unfinished VLC work.

## Scores and favorites

- ESPN supplies Live, Upcoming, and Final boards.
- Apple distinguishes a legitimate successful empty slate from aggregate board failure. A total failure preserves the last successful games and exposes `scoresError`; partial failures retain successful games and expose a warning.

- Phase A score pull reliability (Apple+Android): named warnings e.g. "MLB could not refresh. Other scores are current." / "MLB, NBA could not refresh…" (sorted short labels); silent polls (timer/ticker) only surface after 2 consecutive partial failures (or always on non-silent); per-league retry (~500ms) on primary failures with merge/shrink; default board success clears failure flag (range supplement is best-effort).

- Scores favorites = teams only, stored with league-scoped IDs such as `nfl:27` and `mlb:27`.
- Guide favorites = IPTV channels. They are a separate domain and do not create score alerts.
- Phone uses dense one-row filters and a vertical list; TV uses horizontal “My Games” first + per-league rails (Upcoming incl. empty selected leagues w/ None scheduled on both; Live/Final avoid empty). Sport headers ok in grouping but rails league-level (see tv-surfaces.md).

## TV surfaces

- Apple TV: `SportsDashTV`, TVVLCKit, focus helpers, horizontal Scores rails, and full-screen player cover. No TV pop-out.
- Android TV: leanback launcher/banner, `DeviceProfile.isTelevision`, D-pad focus helpers, TV Scores rails, and TV player key handling. Pop-out removed (Kotlin updated).
- Shell navigation remains available on TV. Phone landscape may use the compact replacement strip.

See `docs/tv-surfaces.md` for the exact implementation and dogfood matrix.

## Notification contract

Game alerts are local and opt-in; no remote push exists.

- iOS: one-shot start-soon scheduling plus transitions/score increases observed by the in-process 45-second foreground score poll.
- Android: transitions/score increases observed when existing app-driven score refreshes run. No recurring poll, WorkManager, alarm, or scheduled start-soon reminder is claimed.
- tvOS: no-op notification service; notification UI is iOS-only.

This is an intentional documented capability delta, not notification parity. See `docs/game-notifications.md`.

## Build and workflow

- Apple: `xcodegen generate && pod install`, then open `SportsDash.xcworkspace`.
- Android: open `android/` in Android Studio or run `./gradlew :app:assembleDebug` with JDK 21.
- Install Android APKs over the existing app to preserve private app data; uninstall removes it.
- Apple CI builds iOS and tvOS. Device/simulator dogfood remains required for interaction and focus sign-off.

## Historical decisions

- The early separate Android repository plan was abandoned; Android production code lives in `android/` here.
- KSPlayer and other GPL engine paths were removed. VLC/libVLC is the chosen hard engine family.
- Cast, multiview, remote push, and another player-engine migration are not part of the current parity slice.
