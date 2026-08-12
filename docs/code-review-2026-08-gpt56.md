# SportsDash deep code, architecture, TV, and parity review — GPT‑5.6

**Review date:** 2026-08-12  
**Repository:** `/opt/data/workspace/sportsdash-apple`  
**Remote:** `https://github.com/chumpuckai-devteam/sportsdash-apple.git`  
**Branch / reviewed HEAD:** `main` / `e4c8008`  
**Scope:** SwiftUI iOS + tvOS, Compose Android + Android TV, VLC-family playback, Scores, Guide/EPG, favorites, local notifications, build configuration, CI, and current architecture/parity/TV documentation.

> Repository note: the checkout already contained unrelated modified/untracked files before this review. This report adds only this markdown file and does not modify those pre-existing changes.

## Executive summary

- The monorepo is now the correct product shape: shared SwiftUI sources for iOS/tvOS, a real Compose Android app in `android/`, and one explicit parity-first product story. `docs/ARCHITECTURE.md` finally reflects that reality.
- The strongest recent work is user-visible and coherent: league-scoped team favorites, dense one-row phone score chrome, TV-only Netflix rails, full-screen TV playback, automatic EPG fill, and a consistent void/gold visual language are all present in code.
- TV is genuinely active rather than aspirational: Apple TV has a dedicated target, TVVLCKit, focus helpers, full-screen player presentation, rails, and CI; Android has a leanback launcher, TV detection, D-pad helpers, rails, and TV-specific player key handling.
- The primary architectural risk is concentration of responsibility. `AppModel.swift` (845 lines), `AppViewModel.kt` (1,174 lines), `GuideView.swift` (1,480 lines), and `ScoresScreen.kt` (1,420 lines) combine state, persistence coordination, network orchestration, transformation, and UI policy, making parity fixes easy to duplicate and regress.
- Android TV still exposes the phone floating-player path. `SportsDashRoot.kt` always passes `onPopOut`, and `PlayerScreen.kt` always renders the pop-out control; this violates the TV full-screen-only law and can return TV users to a floating bar over the shell.
- Apple player settings over-promise implementation: buffer duration is ignored by `VLCPlayerController`, aspect changes are a no-op in `PlaybackController`, subtitle APIs return no tracks, and “System Picture in Picture” only shows a banner. These should be implemented or removed/disabled until truthful.
- Android playback has a thinner state contract than Apple: `VlcPlayerController` exposes no observable loading/error/buffering flow, `PlayerScreen` keeps an optimistic local `isPlaying`, and initial composition can invoke `play(url)` from both `AndroidView.factory` and `DisposableEffect(url)`.
- Local-notification parity is incomplete despite the shipped framing. iOS polls every 45 seconds and schedules five-minute start reminders; Android refreshes scores only at initialization/manual actions and emits only poll-observed “just started”/score changes, so background start-soon and reliable goal behavior are not equivalent.
- Selected score leagues persist on Apple but not Android. Android initializes `selectedLeagueIds` to defaults on every process start and `toggleLeague` only mutates memory, so a user’s league selection is lost after restart.
- Documentation remains internally contradictory: `docs/tv-surfaces.md` still calls the Apple player a sheet and describes floating pop-out on TV; `android/README.md` says Android TV is “Not ready” and later says it shipped; `docs/dual-platform.md` and `docs/vlc-main-engine.md` still describe Android Scores/EPG/VLC as TBD/later.
- Automated confidence is too low for the amount of cross-platform policy encoded in hand-written code. No Swift/Kotlin test files were found, Apple CI only builds, and there is no Android CI workflow. Core transformations such as favorite migration, score filtering/grouping, EPG mapping, ticker ordering, and preference migration need tests.
- Security/storage language should be tightened. Apple correctly uses Keychain for IPTV passwords, while Android writes credentials in plaintext JSON to DataStore, SharedPreferences, and `filesDir`; the backup preference name includes “secure” even though no encryption is used. Both manifests/configs broadly allow cleartext transport for IPTV compatibility and should document the threat boundary.
- The immediate priority should be truth and invariants, not net-new scope: remove TV pop-out, fix or hide fake player controls/settings, persist Android league choices, make notification behavior/documentation exact, add Android CI and core unit tests, then split the state/UI god objects.

## Strengths

### Product and architecture direction

1. **The monorepo is intentional and accurately represented at the top level.** `docs/ARCHITECTURE.md` lines 3–16 describes native iOS/tvOS and Android in one repository and names `SportsDash/`, `android/`, `docs/`, XcodeGen/CocoaPods, and Gradle. This is the right correction from the earlier separate-repo framing.
2. **Three-tab IA is consistent.** `SportsDash/App/RootTabView.swift` defines only Scores, Guide, and Settings; `android/.../ui/SportsDashRoot.kt` creates the same three destinations. `LaunchTab` in `PlayerPrefs.swift` also migrates legacy `channels` to Guide.
3. **Cold-start work is thoughtful.** Apple `AppModel.bootstrap()` paints channel/EPG disk caches before network work and precomputes category maps (`applyChannels` / `rebuildChannelGroups`). Android `AppViewModel.refreshChannels()` paints `PrefsStore` cache before refresh. Both follow the product’s “snappy second launch” law.
4. **Favorites model is now exact.** Apple `SportsAPI.stableTeamId` and Android sports models produce league-scoped IDs; both view models migrate legacy bare IDs by matching team metadata and drop ambiguous collisions. Team metadata, rather than IDs alone, is persisted for rails.
5. **Scores hierarchy is product-specific rather than a generic feed.** Apple `ScoresView` and Android `ScoresScreen` implement Live/Upcoming/Final, My Games, favorite-first order, sport/league hierarchy, gold WATCH, and team marks. Apple’s upcoming path additionally preserves empty selected league shelves.

### TV surfaces

6. **TV is represented in build/install surfaces.** `Project.yml` defines `SportsDashTV` with tvOS deployment, bundle ID, assets, and shared sources; `Podfile` uses TVVLCKit; Android manifest declares optional touchscreen/leanback support, a TV banner, and `LEANBACK_LAUNCHER`.
7. **Player presentation regression is fixed on Apple.** `PlatformChrome.sportsPlayerCover` unconditionally uses `fullScreenCover`, and both `RootTabView` and `GuideView` use it. The player surface fills/ignores safe areas.
8. **TV browse layouts are real.** `ScoresTVGameCard.swift` provides a wide Apple TV card with a fixed center WATCH/status band; `ScoresScreen.kt` routes television devices to `ScoresTVBrowse` with horizontal rails and focus rings. Phone layouts remain separate.
9. **Focus behavior is centralized enough to establish a house style.** Swift uses `SportsTVFocused`, `sportsTVFocusClean`, `focusSection`, and metrics. Android `TvFocus.kt` documents avoiding duplicate focusable nodes and supplies ring/circle/group modifiers.
10. **Android TV input handling is more than visual focus.** `PlayerScreen.kt` supports media keys, D-pad chrome reveal, center/enter behavior, and a two-step Back policy.

### Player, Guide, and notifications

11. **VLC-family hard-engine law is implemented.** Apple imports MobileVLCKit/TVVLCKit and routes TS/unknown to VLC with HLS to AV; Android pins `libvlc-all:3.6.0`. Android rebinds video views after stream switches and reapplies 140/200 volume and media audio focus.
12. **Full-bleed overlay law is respected.** Both player implementations put video at the bottom of the z-stack and transparent ticker/chrome over it. Ticker pills are opaque, and OFF/FADE/PIN behavior is persisted.
13. **Guide behavior contains important hard-earned safeguards.** Apple debounces category side work, uses provider order, defaults to a populated category, deduplicates clone channels by cleaned name while preferring richer EPG, paints continuous gap blocks, and resets the timeline to the current hour. Android implements bulk + short EPG phases and progressive merges.
14. **Notification opt-in is conservative.** Both default off and filter to favorite teams. iOS properly compiles notification content only under `#if os(iOS)` while preserving a tvOS-safe service surface; Android requests runtime notification permission in Settings.
15. **Apple CI covers both Apple targets.** `.github/workflows/ios.yml` generates the project, installs pods, and builds both iOS and generic tvOS simulator schemes from the workspace.

## Detailed issues

## Architecture & State

### A1 — State containers are oversized orchestration god objects (**P1**)

- `SportsDash/App/AppModel.swift` is 845 lines and owns scores, channels, playlists, account state, favorites, player routing, timers, EPG caching/loading, notification processing, matching, preference writes, and derived presentation sections.
- `android/.../AppViewModel.kt` is 1,174 lines and owns the same concerns plus key handling, ratings orchestration, all player routes, notification dispatch, and UI-specific helpers.
- Consequence: a parity change requires edits in large actor/view-model files and often duplicates transformations. This is visible in separate implementations of favorite migration, favorite-first sorting, guide dedupe, filters, and ticker ranking.
- Recommendation: retain one screen-facing state owner per platform, but delegate to focused coordinators/stores: `ScoresStore`, `GuideStore`, `PlaybackSession`, `PlaylistStore`, and `NotificationCoordinator`. Keep immutable screen state and event methods at the boundary.

### A2 — Large UI files contain models, algorithms, and platform policy (**P1**)

- `GuideView.swift` includes Guide UI, TV picker/focus behavior, dedupe, timeline block generation, UIKit scroll synchronization, and UIKit hosting wrappers in one 1,480-line file.
- `ScoresView.swift` includes the complete dashboard, section-building algorithm, filter model consumers, TV routing, and grouping types.
- `ScoresScreen.kt` includes score screen, pickers/dialogs, phone rows, stream picker, TV browse, TV cards, and logo components in 1,420 lines.
- Recommendation: split by feature-private units while preserving behavior: `GuideTimeline.swift`, `GuideCardList.swift`, `GuideCategoryPresentation.swift`, `GuideScrollSync.swift`; Android `scores/PhoneScores.kt`, `scores/TvScores.kt`, `scores/FavoriteTeamPicker.kt`, `scores/StreamPicker.kt`.

### A3 — Android league selection is not persisted (**P0 parity/data-loss**)

- `AppUiState.selectedLeagueIds` initializes from `SportLeague.DEFAULTS` (`AppViewModel.kt` lines 90–92).
- `toggleLeague` updates only `_state` and calls `refreshScores` (lines 999–1005).
- `PrefsStore.kt` has no league key or league flow/write API.
- Apple persists this setting through `StorageService.selectedLeagues()` / `setSelectedLeagues()` and loads it in `AppModel.init`.
- Impact: Android users lose customized league selections every process restart; Scores behavior silently changes.
- Recommendation: add a DataStore string-set/JSON key with migration/default fallback, collect it before first scores refresh, and test restart persistence.

### A4 — Android starts network refresh before key preferences settle (**P1**)

- `AppViewModel.init` launches many independent collectors and immediately calls `refreshScores()` at line 247.
- Favorite teams, notification toggles, and future persisted leagues may not have emitted when the first score result is processed; notification processing uses whatever `_state` contains at that moment.
- Recommendation: use one bootstrap coroutine that loads a preference snapshot first, publishes initial state once, then starts refresh and long-lived collectors. This also avoids visible default-to-saved flicker.

### A5 — Apple score failures are effectively unobservable (**P1**)

- `AppModel.refreshScores()` clears `scoresError`, calls `SportsAPI.fetchScoreboards`, and always assigns the returned array; it never sets `scoresError`.
- `SportsAPI.fetchAndMerge` converts every request failure to `[]` via `try?`, and non-2xx responses also return `[]`.
- Yet `ScoresView` has a dedicated “Scores unavailable” branch keyed by `scoresError`.
- Impact: total network/API failure looks like a legitimate empty slate rather than an error.
- Recommendation: return a typed aggregate result (games plus per-league failures) or throw when all requested boards fail; preserve partial games with a non-blocking warning when only some leagues fail.

### A6 — Polling/lifecycle policies differ and are implicit (**P1**)

- Apple schedules a 45-second `Timer` in `startScoresPolling()` and a 15-minute playlist timer; Android performs scores refresh at init and user actions only.
- Neither architecture document calls out foreground lifecycle, app background behavior, or refresh ownership precisely.
- Recommendation: define a cross-platform foreground polling policy and lifecycle hooks. On Android use lifecycle-aware collection/coroutines; on Apple invalidate/restart timers on scene changes rather than relying on an app-lifetime model.

## Platform Branching

### B1 — `PlatformChrome` is useful but still shallow/inconsistent (**P2**)

- It centralizes scroll background, navigation title mode, sheet chrome, and player presentation.
- `SportsToolbarPlacement` nevertheless has identical `#if` branches, and `isTelevision` is an instance property on every `View` rather than a platform capability/value.
- Large files still contain many inline branches: the scan found 37 platform/focus/presentation occurrences in `GuideView`, 28 in `ScoresView`, and 16 in `PlayerView`.
- Recommendation: delete no-op branching, expose a small `SportsPlatform` capability (`isTV`, supports pop-out, supports notifications), and move whole TV/phone subtrees into separate views rather than branching inside modifiers and labels.

### B2 — Platform support is sometimes represented as dead controls rather than absent controls (**P0/P1**)

- Apple `PlayerView.playerChromeControlsRow` always renders the pop-out icon; on tvOS its action returns without feedback (`popOutToFloatingPlayer`, lines 624–635).
- Android `PlayerScreen` always renders pop-out and `SportsDashRoot` always supplies `vm.popOutPlayer`, including television devices.
- Recommendation: capability-gate the control itself. Unsupported actions must not be focusable or announced.

### B3 — TV presentation wording and implementation diverge (**P1 docs/architecture**)

- Code uses `fullScreenCover` on both Apple platforms.
- `docs/tv-surfaces.md` lines 26–31 still says the player presents as a “sheet”; checklist entries repeatedly say “Player sheet.”
- `docs/ARCHITECTURE.md` says fullScreenCover on TV but later describes presentation generically as full-screen TV versus phone sheets. The implementation should be the source of truth and the docs should use exact terms.

## TV Surfaces

### C1 — Android TV violates full-screen-only player law via pop-out (**P0**)

- `SportsDashRoot.kt` passes `onPopOut = { vm.popOutPlayer() }` to every `PlayerScreen`, independent of `isTelevision`.
- `PlayerScreen.kt` lines 376–395 renders the pop-out control independent of television capability.
- `AppViewModel.popOutPlayer()` sets `floating = true`; root then leaves full-screen and renders `FloatingPlayerBar` over the tab shell.
- This directly contradicts the Apple TV no-float correction and the stated TV product law.
- Fix: add `supportsPopOut = !isTelevision`, omit the button on TV, and make the view-model event reject TV routes defensively (or keep platform capability outside the view model and never dispatch it).

### C2 — Apple TV has a focusable no-op pop-out button (**P0**)

- `PlayerView` bottom controls render `rectangle.inset.filled.and.person.filled` on all platforms.
- The tvOS implementation of `popOutToFloatingPlayer` immediately returns.
- Impact: a remote user can focus and press a control that does nothing.
- Fix: wrap the entire control in `#if os(iOS)`, not only the confirmation-dialog action.

### C3 — Android TV top/bottom shell uses phone Material navigation without explicit TV focus treatment (**P1 dogfood risk**)

- `SportsDashRoot.kt` correctly keeps shell chrome on TV, but `TopAppBar`/`IconButton` and Material3 `NavigationBarItem` are not using the project `tvFocusRing` helpers or a TV navigation layout.
- The current documentation claims shell D-pad reachability, but code-level focus styling is only explicit inside screens/player.
- Recommendation: add a TV shell composable with clear selected/focused states and deterministic traversal, or at minimum apply TV focus treatment and test top action → content → bottom nav transitions on AVD/hardware.

### C4 — TV Scores filters/favorite rail remain phone-density chrome above TV rails (**P1 UX**)

- Android passes `landscape || isTelevision`, but `ScoresTopChrome` ignores its `landscape` and `status` parameters and always uses 11sp compact chips, 30dp logos, and 2dp vertical padding.
- Apple tvOS uses larger `SportsFilterChip` defaults, but still places filters/context above Netflix rails.
- Recommendation: make a dedicated 10-foot browse header: larger focus targets, optional favorite-picker action, concise context, and no unused phone-density parameters.

### C5 — TV detail/picker presentation remains under-verified (**P1**)

- Apple game details and favorite picker are `.sheet`; Guide category picker is also invoked with `.sheet` plus `sportsLargePresentation`, whose tvOS branch is a no-op rather than changing the presentation API.
- The TV law says category needs a full-screen opaque picker, but the call site is still `.sheet`.
- Recommendation: create `sportsLargeCover` that selects `fullScreenCover` on tvOS and sheet on iOS, then use it for category/favorite flows that require remote-safe full-screen presentation. Device/simulator verification is still required.

## Player & Engine

### D1 — Apple buffer setting is ignored (**P0 truth/implementation**)

- `PlayerPrefs.bufferSeconds` is exposed and editable in `PlayerSettingsView` as 1–15 seconds.
- `PlaybackController.configure` passes it to `VLCPlayerController.configure`.
- `VLCPlayerController.configure` explicitly discards it (`_ = bufferSeconds`), while `start` hard-codes network/live/sout caching to 1500ms.
- Fix: store a clamped millisecond value and apply it to all three VLC options, or remove the setting until supported. Add a unit test for conversion/clamping.

### D2 — Apple aspect settings are a no-op (**P0 truth/implementation**)

- UI exposes Auto/Fit/Fill/16:9/4:3/Stretch and a player toolbar cycle.
- `PlayerView.applyAspect()` reduces these to a boolean.
- `PlaybackController.setAspectFill` discards the boolean and comments that surfaces use defaults.
- Fix: implement video gravity/aspect on both AV and VLC surfaces, with an engine capability mapping, or restrict the UI to the actual default mode.

### D3 — Captions and PiP are presented as available but are stubs (**P0 truth/implementation**)

- `PlaybackController.subtitleOptions()` returns an empty list; selection/cycle only posts “not wired” banners.
- `togglePictureInPicture()` only posts instructions and `isPiPActive` is always false.
- `PlayerView` still renders captions and “System Picture in Picture” controls, including on TV where applicability differs.
- Recommendation: remove/disable with explicit “Unavailable” state until implemented. Do not offer controls whose only result is a diagnostic banner.

### D4 — Android playback state is optimistic and not event-driven (**P1 reliability**)

- `VlcPlayerController` has a `setEventListener` method but `PlayerScreen` never uses it.
- Compose keeps `isPlaying` as local state initialized `true`, then updates it immediately after commands; there is no buffering, error, ended, or actual-playing state.
- Impact: controls can show Pause while playback failed or is buffering, and there is no user-facing timeout/error/fallback state comparable to Apple.
- Recommendation: expose a `StateFlow<PlaybackState>` from the controller (`Idle/Opening/Buffering/Playing/Paused/Failed`) and render retry/error/loading UI from it.

### D5 — Android can issue duplicate initial play calls (**P1 reliability**)

- `DisposableEffect(url)` calls `controller.play(url)`.
- `AndroidView.factory` attaches the layout and also calls `controller.play(url)`.
- `attach()` itself may resume `currentUrl` through `playInternal`.
- Recommendation: make one owner of media start (prefer `LaunchedEffect(url)` after surface readiness). `factory/update` should attach only; controller should make idempotence explicit.

### D6 — Apple fallback/engine API carries stale legacy cases and comments (**P2 hygiene**)

- `PrimaryVideoPlayer` retains `ksPlayer`/`mpvKit` cases only for decoding migration; `PlaybackController` switches on them as VLC.
- `PlaybackController` header says Android is “later,” and `PlayerSettingsView` footer says Android later, although Android libVLC ships now.
- Recommendation: isolate legacy raw-value migration in a custom decoder and keep runtime enum cases to selectable engines only; update comments/UI copy.

### D7 — Player parity is asymmetric but undocumented at control level (**P1 parity**)

- Apple exposes alternate streams, aspect, captions stub, engine fallback/retry, AirPlay, and a broad options dialog.
- Android exposes play/pause, rejoin, mute, ticker, and pop-out but no current-channel alternate-stream control, aspect, or error/fallback UI.
- The accepted engine delta is documented, but control-surface parity is not.
- Recommendation: add a capabilities matrix to `dual-platform-parity.md`; implement Android alternate-stream picker first, then explicitly mark other differences intentional or backlog.

## Documentation

### E1 — `docs/tv-surfaces.md` contradicts current TV player law (**P0 docs**)

- It says “Player presents as sheet” and checklist items say “Player sheet,” even though `sportsPlayerCover` is `fullScreenCover` and recent product law says never sheet on TV.
- It says floating pop-out should “park safely if used,” contradicting full-screen-only TV.
- Fix immediately: replace sheet language with full-screen cover, remove floating TV steps, and mark rails/focus status accurately.

### E2 — `android/README.md` contains mutually exclusive Android TV status (**P0 docs**)

- Lines 137–140 say “Not ready. Phone UI only (no leanback launcher / D-pad).”
- Lines 168–183 then describe Android TV 1.2.0+/1.2.1 focus as shipped.
- Fix: remove the obsolete section and retain one current setup/dogfood section.

### E3 — Other high-level docs remain stale after the architecture rewrite (**P1 docs**)

- `docs/dual-platform.md` still lists Android EPG and Scores as TBD and says “When Android is real.”
- `docs/vlc-main-engine.md` says “Same family later on Android” and has an “Android later” section.
- `PlayerSettingsView.swift` repeats “Android later.”
- `docs/dual-platform-parity.md` still marks TV “in progress” with pre-rail residual wording even though both rail implementations are present; device sign-off remains outstanding, but implementation status should be separated from dogfood status.

### E4 — Architecture documentation has factual deltas (**P1 docs**)

- `docs/ARCHITECTURE.md` says floating player and notifications are iOS-only. Android code has `FloatingPlayerBar` and `GameNotificationHelper`.
- It cites `android/build.gradle.kts` for libVLC, but the dependency is in `android/app/build.gradle.kts`.
- Recommendation: distinguish “implemented,” “supported on phone,” “supported on TV,” and “device-verified” instead of platform-wide yes/no labels.

### E5 — Build documentation is duplicated and inconsistent (**P2**)

- Android README recommends multiple menu paths and contains old/new TV sections; architecture, parity, TV, and VLC docs repeat engine/build facts with drift.
- Recommendation: one canonical build page per platform and short links elsewhere. Add a doc freshness checklist to release/version updates.

## Parity & Naming

### F1 — `DashboardFilter.all` means Final while Android says `FINAL` (**P1 naming debt**)

- Swift retains `.all` solely as a legacy raw value, labels it “Final,” and filters only final games.
- Android uses `ScoresFilter.FINAL`.
- This is documented in comments, but the mismatched runtime name keeps producing mental overhead and makes “all” easy to misuse.
- Recommendation: introduce `.final` as the runtime case with a custom decoder mapping legacy `all` → `final`, then align names across code and docs.

### F2 — Android Guide search state is dead/stale naming (**P2**)

- `AppUiState.searchQuery` and `setSearchQuery` remain, but the current Guide product surface intentionally has no search and no inspected UI consumes this state.
- Recommendation: remove dead state/event or explicitly reintroduce a product-approved category search capability later; do not retain misleading dormant API.

### F3 — “Game alerts” parity is overstated (**P0/P1**)

- iOS schedules a five-minute `UNCalendarNotificationTrigger`, emits just-started, and compares 45-second polls.
- Android has no scheduled start-soon reminder and no recurring scores poll; it only emits changes observed when scores happen to refresh.
- `docs/ARCHITECTURE.md` incorrectly calls notifications iOS-only, while UI/docs elsewhere call Android alerts shipped.
- Recommendation: define the product contract precisely. If start-soon is required on Android, schedule local alarms/work with platform constraints; otherwise label Android as foreground/manual-refresh alerts and do not claim parity.

### F4 — Android Upcoming empty-shelf parity appears absent (**P1**)

- Apple `ScoresView.buildSections` deliberately synthesizes empty selected league shelves for Upcoming.
- Android `sportScoreSections()` groups only `filteredGames`, and `flattenScoreRows` omits empty shelves.
- Impact: selected leagues can disappear from Android Upcoming while Apple explains “None scheduled.”
- Recommendation: move empty-shelf construction into Android `ScoreboardGrouping` or a shared screen transformation and add a parity test.

### F5 — Dedupe normalization differs (**P2**)

- Apple Guide dedupe keys on `ChannelNameCleanup.displayName(..., enabled: true)`.
- Android keys on raw `ch.name.lowercase().trim()`.
- Thus `Channel HD` and `Channel 4K` can dedupe on Apple but remain duplicate rows on Android.
- Recommendation: use Android `ChannelNameCleanup.displayName(..., enabled = true)` for dedupe keys regardless of display preference, matching Apple.

## Code Quality / Hygiene

### G1 — No automated tests were found (**P0 quality**)

- File search found no tracked Swift/Kotlin files matching `*Test*`.
- Both XcodeGen schemes declare empty test targets.
- High-risk pure logic is testable without UI/network: league-scoped ID migration, ESPN parsing, filter semantics, favorite sorting, ticker ordering, EPG timeline gap construction, channel dedupe, preference migrations, and URL/container routing.
- Recommendation: establish Swift Testing/XCTest and JUnit test targets before further parity expansion.

### G2 — No Android CI gate (**P0 quality**)

- `.github/workflows/ios.yml` builds iOS and tvOS only.
- The local Android build could not be run on this Linux review host because no Java runtime/JAVA_HOME is installed; this makes a repository CI gate more important, not less.
- Recommendation: add an Ubuntu Android job with JDK 21 and `./gradlew :app:assembleDebug test`; cache Gradle dependencies. Keep Apple workspace builds unchanged.

### G3 — Unused parameters and dead helpers obscure intent (**P2**)

- Android `ScoresTopChrome` receives `landscape` and `status` but does not use them.
- Swift `PlayerView.utilityButton` is defined but unused.
- `PlaybackController.applyGlobal` is a no-op but is called from settings.
- Android `setShowScoresTicker` and legacy ticker preference APIs remain alongside the three-mode API.
- Recommendation: remove no-op/dead APIs after migrations, or document why they remain and test their compatibility path.

### G4 — Errors are swallowed broadly (**P1**)

- Apple Sports API uses `try?` for every request and returns empty data on HTTP failure.
- Apple audio-session setup catches and ignores all errors.
- Android VLC catches most exceptions silently; callers receive no failure state.
- Recommendation: use structured, privacy-safe logging and typed errors. Never log stream credentials/URLs, but do record engine state, HTTP status category, and operation names.

### G5 — Versioned release facts are scattered (**P2**)

- Apple marketing version/build live in `Project.yml`; Android version and suffix live in app Gradle; docs embed 1.2.0/1.2.1/1.2.3 labels in multiple places.
- Recommendation: add a release checklist/script that verifies version alignment and updates canonical status docs.

## Other

### H1 — Android credentials are redundantly stored but not securely encrypted (**P1 security/trust**)

- `PrefsStore.encodePlaylist` includes plaintext password.
- The encoded JSON is stored in DataStore, SharedPreferences named `sportsdash_secure_backup`, and `filesDir/playlist_config_backup.json`.
- These are app-private, which is appropriate for basic local storage and update persistence, but “secure” is misleading and `allowBackup=true` broadens the threat/restore boundary.
- Apple uses Keychain per playlist and strips passwords from UserDefaults JSON.
- Recommendation: rename the backup store, document app-private plaintext accurately, evaluate Android Keystore-encrypted credentials, and explicitly decide backup/restore policy. Do not silently promise parity with Keychain.

### H2 — Cleartext transport permissions are intentionally broad (**P1 security/config**)

- Apple `Project.yml` sets `NSAllowsArbitraryLoads=YES` globally.
- Android manifest sets `usesCleartextTraffic=true` and references a network security config.
- IPTV providers may require HTTP, but global allowances also affect unrelated ESPN/rating traffic if code regresses.
- Recommendation: constrain exceptions where platform/provider URL variability permits, prefer HTTPS first, and document why release builds require any broad allowance.

### H3 — Hard-coded Apple development team reduces portability (**P2 build hygiene**)

- `Project.yml` sets `DEVELOPMENT_TEAM` globally and in both targets. Comments acknowledge it is dogfood-only.
- Recommendation: move this to an untracked/local signing config or environment-generated XcodeGen setting; CI already disables signing.

### H4 — Android application icon uses the foreground drawable directly (**P2 polish**)

- Manifest sets both `icon` and `roundIcon` to `@drawable/ic_launcher_foreground`, rather than a mipmap/adaptive icon resource.
- Recommendation: wire proper adaptive launcher icons while retaining the TV banner.

### H5 — Product-law wording around “favorites” needs consistent qualification (**P2 docs**)

- Scores correctly favorites teams only; Guide correctly favorites channels. Some docs state “Favorite teams only” without qualifying that this is the Scores domain, while parity tables separately mention Guide favorites.
- Recommendation: consistently write “Scores favorites = teams only; Guide favorites = channels.”

## Concrete recommendations

1. **Establish platform capabilities.** Define `supportsPopOut`, `supportsLocalNotifications`, `supportsAirPlay`, `supportsDualEngine`, and `isTelevision`; use them to omit unsupported UI rather than no-op actions.
2. **Make player UI truthful.** Build a capability-backed control model. A control is shown only when its engine/platform implementation exists. Remove buffer/aspect/captions/PiP claims until wired.
3. **Introduce observable playback state on Android.** Route libVLC events into StateFlow and render opening/buffering/error/retry. Make one coroutine own URL changes and one surface lifecycle own attach/detach.
4. **Persist all user choices symmetrically.** Add Android league persistence now; then audit launch tab, Guide layout, filter, selected category, and player preferences against Apple’s persistence contract.
5. **Define notification tiers explicitly.** Separate scheduled start-soon, foreground poll start, and score-change alerts in docs/state. Either implement Android scheduling/polling or call out the intentional delta.
6. **Extract pure domain transformations.** Favorite migration, score filtering/grouping, upcoming empty shelves, ticker ordering, and Guide dedupe should be testable pure functions outside UI/state containers.
7. **Split TV and phone view implementations at subtree boundaries.** Keep shared models/actions but avoid modifier-level platform branching across thousand-line files.
8. **Add minimum CI before new features.** Android assemble + unit tests; Apple logic tests + current iOS/tvOS build matrix. Treat device dogfood as an additional gate, not a substitute.
9. **Consolidate documentation.** Make `ARCHITECTURE.md`, `dual-platform-parity.md`, and `tv-surfaces.md` canonical; convert `dual-platform.md` into a redirect/short current map; remove contradictory historical status from Android README.
10. **Harden credential/transport language and storage.** Preserve no-secret-in-git law, use platform secure stores where practical, and state exactly what app-private backup does and does not protect.

## Prioritized backlog

### P0 — correctness, product-law, and trust

| ID | Action | Evidence / acceptance |
|---|---|---|
| P0.1 | Remove floating-player controls and routes on Apple TV and Android TV. | `PlayerView` has a tvOS no-op pop-out; Android TV can enter `floating=true`. On TV no pop-out control is focusable, Back/Close exits full-screen, and no floating bar renders. |
| P0.2 | Make Apple player settings truthful: implement buffer and aspect or remove them. | VLC currently ignores `bufferSeconds`; `setAspectFill` is no-op. A changed setting must measurably alter engine/surface configuration, with tests. |
| P0.3 | Hide/disable stub captions and system PiP controls until implemented. | Subtitle list is empty and PiP only posts banners. No UI should claim an unavailable action. |
| P0.4 | Persist Android selected leagues. | Add PrefsStore key/flow/write; customized selection survives process restart and drives first refresh. |
| P0.5 | Add Android CI and foundational unit-test targets on both stacks. | CI runs `assembleDebug` + JVM tests; Apple logic tests run alongside both builds. Cover favorites IDs/migration, filters, sorting, and prefs migration first. |
| P0.6 | Correct TV and Android status docs. | `tv-surfaces.md` says full-screen cover/no TV float; Android README has one current TV section; stale TBD/later statements are removed from `dual-platform.md` and `vlc-main-engine.md`. |
| P0.7 | Define and enforce notification contract. | Docs and UI distinguish iOS scheduled start-soon from Android behavior; either add Android lifecycle-aware polling/scheduling or explicitly mark the delta. |

### P1 — reliability, parity, and maintainability

| ID | Action | Evidence / acceptance |
|---|---|---|
| P1.1 | Add Android observable playback state and eliminate duplicate initial `play`. | One owner starts media; UI reflects libVLC buffering/playing/paused/error events and supports retry. |
| P1.2 | Surface Apple aggregate scores failure. | All-board failure displays error; partial league failures retain games and show a warning. |
| P1.3 | Add Android Upcoming empty shelves. | Every selected league remains represented under Upcoming with “None scheduled,” matching Apple. |
| P1.4 | Split `AppModel`/`AppViewModel` into focused feature coordinators. | Screen-facing state remains stable; network/persistence/player/notification orchestration moves behind protocols/classes with unit tests. |
| P1.5 | Split large Guide/Scores files into phone, TV, picker/dialog, and pure-transform units. | No behavior change; platform branches reduce materially and pure logic is independently tested. |
| P1.6 | Build a TV-specific shell/header focus pass. | Remote traverses refresh/nav/content deterministically; TV score header uses 10-foot targets rather than 11sp phone chrome. |
| P1.7 | Make TV large presentations truly full-screen where required. | Category and favorite pickers use a presentation helper that selects fullScreenCover on tvOS and sheet on iOS; verified on simulator/device. |
| P1.8 | Align Guide dedupe and persistence policy. | Android dedupe uses cleaned names like Apple; decide and implement selected-category/Guide-layout persistence consistently. |
| P1.9 | Add structured privacy-safe diagnostics. | Score/EPG/player errors are observable without logging credentials or full signed stream URLs. |
| P1.10 | Evaluate Android Keystore storage and backup policy. | Security note documents current plaintext app-private storage; implementation either encrypts credentials or records an explicit accepted-risk decision. |

### P2 — naming, cleanup, and polish

| ID | Action | Evidence / acceptance |
|---|---|---|
| P2.1 | Rename Swift runtime filter case `.all` to `.final` with legacy decode migration. | Runtime names align with Android/product labels; old stored `all` still decodes. |
| P2.2 | Remove dead APIs/state/parameters. | Delete Android `searchQuery` if search remains out, unused Scores chrome args, Swift `utilityButton`, and no-op compatibility calls after migrations. |
| P2.3 | Move Apple team signing ID to local configuration. | Clean clone/build generation is not tied to one team; dogfood docs explain local signing. |
| P2.4 | Wire Android adaptive launcher icon resources. | Phone launcher uses proper foreground/background/mipmap assets; TV banner remains correct. |
| P2.5 | Consolidate build/release documentation and automate version checks. | One canonical Apple and Android build recipe; script/check verifies marketing/versionCode status. |
| P2.6 | Reduce global cleartext allowances where feasible. | HTTPS-first service traffic remains strict; provider HTTP exception is documented and constrained. |

## Method

### Repository/state verification

- Ran `pwd`, `git rev-parse --short HEAD`, `git branch --show-current`, `git status --short`, and `git remote -v` in `/opt/data/workspace/sportsdash-apple`.
- Confirmed `main` at `e4c8008`, origin `chumpuckai-devteam/sportsdash-apple`, 47 tracked Swift files, 28 tracked Kotlin files, and 22 tracked top-level docs markdown files.
- Searched Swift/Kotlin sources for platform branches, TV focus, player presentation, dialogs, TODO/stub language, notifications, preferences, and tests.
- Attempted `./gradlew :app:assembleDebug`; it did not start because this review host has no Java executable and `JAVA_HOME` is unset. No build result is claimed.

### Swift / Apple files inspected

- `SportsDash/App/AppModel.swift`
- `SportsDash/App/RootTabView.swift`
- `SportsDash/Theme/PlatformChrome.swift`
- `SportsDash/Features/Scores/ScoresView.swift`
- `SportsDash/Features/Scores/ScoresTVGameCard.swift`
- `SportsDash/Features/Guide/GuideView.swift`
- `SportsDash/Features/Player/PlayerView.swift`
- `SportsDash/Features/Player/PlaybackController.swift`
- `SportsDash/Features/Player/VLCPlayerController.swift`
- `SportsDash/Core/Models/PlayerPrefs.swift`
- `SportsDash/Core/Services/SportsAPI.swift`
- `SportsDash/Core/Services/StorageService.swift`
- `SportsDash/Core/Services/GameNotificationService.swift`
- `SportsDash/Features/Settings/PlayerSettingsView.swift`
- Relevant search hits in `SportsDash/Features/Settings/SettingsView.swift`

### Kotlin / Android files inspected

- `android/app/src/main/java/com/samirpatel/sportsdash/MainActivity.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/AppViewModel.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/core/platform/DeviceProfile.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/core/player/VlcPlayerController.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/core/notifications/GameNotificationHelper.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/data/PrefsStore.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/SportsDashRoot.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/ScoresScreen.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/PlayerScreen.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/tv/TvFocus.kt`
- Relevant search hits in `android/.../ui/GuideScreen.kt`, `GuideTimeline.kt`, and `SettingsScreen.kt`

### Build/configuration and docs inspected

- `Project.yml`
- `Podfile`
- `.github/workflows/ios.yml`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/README.md`
- `docs/ARCHITECTURE.md`
- `docs/dual-platform-parity.md`
- `docs/tv-surfaces.md`
- `docs/dual-platform.md`
- `docs/vlc-main-engine.md`
- Search-based comparison against `docs/ux-ui-review-2026-08-gpt56-sol.md`, `docs/game-notifications.md`, `docs/goal-run-2026-08-status.md`, and other current docs for stale status/terminology.

## Closing assessment

SportsDash has crossed the line from a phone prototype with TV aspirations into a credible dual-mobile/dual-TV product codebase. The recent TV rails, exact favorites, EPG safeguards, and player presentation fixes are meaningful. The next phase should not add Cast, multiview, push, or another player engine. It should make existing claims true, enforce TV capabilities, persist Android state, test the parity rules, and split the four oversized files that currently hold too much product law. That work will improve shipping confidence more than another feature wave.
