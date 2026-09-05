# SportsDash Apple — performance playbook (implementation instructions)

Branch `ui/005-jumbotron`. Written 2026-09-05 against HEAD `d279bec` (Jumbotron phone + TV,
`EpgStore`, streaming XMLTV, collapsing TV rail). Audience: Grok (implements), Samir (verifies in
Instruments). Every item below names the file, the anti-pattern as it exists today, the exact
change, and how to prove it worked. Nothing here changes product behaviour.

Sources studied (Apple Developer Documentation, current text):
`xcode/improving-your-app-s-performance` · `xcode/understanding-hangs-in-your-app` ·
`xcode/understanding-hitches-in-your-app` · `xcode/understanding-user-interface-responsiveness` ·
`xcode/improving-app-responsiveness` · `xcode/analyzing-responsiveness-issues-in-your-shipping-app` ·
`xcode/reducing-your-app-s-launch-time` · `xcode/understanding-and-improving-swiftui-performance` ·
`xcode/writing-and-running-performance-tests`.

---

## 1. Principles from Apple's pages, mapped to this app

| Apple says | Threshold / tool | Where SportsDash violates it today |
|---|---|---|
| Work the cycle: gather → measure → change **one thing** → compare before/after profiles. | Organizer, MetricKit, Instruments before/after. | Perf work so far was shipped without a "before" trace. Every P0 below records one first (§4). |
| A **hang** is main-thread work that delays a discrete interaction. System reports ≥ 250 ms; users notice at ~100 ms. Keep discrete interactions < 100 ms, continuous ones < 5 ms of main-thread work per frame. | Time Profiler + Hangs track; on-device Hang Detection; Thread Performance Checker. | `AppModel.matches(for:)` runs full-playlist matching synchronously inside `ScoresView.body` for every row (P0-1). `GuideLinkedScrollView.updateUIView` re-hosts and `layoutIfNeeded()`s every visible row on every Guide invalidation (P0-5). |
| A **hitch** is a missed frame in continuous motion. Budget 16.7 ms at 60 Hz (Apple TV, most iPhones), 8.3 ms at 120 Hz. **Commit hitches** = expensive body/layout on main; **render hitches** = offscreen passes: shadows, blur, masks, high view counts. Good ≤ 10 ms/s, warning ≤ 25, critical ≤ 50. | Animation Hitches template; Core Animation "Color Offscreen-Rendered". | Every LED digit, WATCH, lamp, chip and focus ring carries its own `.shadow` — a TV rail of 6 cards is ~40 offscreen passes per frame while the focus scale animates (P1-1). Sidebar collapse animates the content width so all rails relayout every frame (P1-2). |
| **SwiftUI: keep `body` cheap; do not compute or allocate in `body`, `onAppear`, `onChange`.** Move logic into the model; cache results. | SwiftUI instrument: Long View Body Updates (orange > 500 µs, red > 1 ms), Time Profiler "Show calls made by *.body". | `ScoresView.scoresContent` sorts, pins and groups the whole board on every evaluation (P0-2); `PlayerView` rebuilds and re-sorts the ticker strip on every playback state flip (P0-4); `GuideView.guideRows` dedupes the category per evaluation (P1-5); `DateFormatter()` allocated inside row bodies (P1-4). |
| **Reduce update frequency: a view that observes an `ObservableObject` re-evaluates when *any* `@Published` on that object changes.** Apple's stated fix: migrate to `@Observable`, which tracks only the properties a body reads. Also: don't store closures that capture `self`/a model in view structs — the view then updates on every change of what the closure captured. | Cause & Effect graph in the SwiftUI instrument; `Self._printChanges()`. | `AppModel` has 24 `@Published`; 15 views take it as `@EnvironmentObject`, so `isLoadingAccount`, `lastUpdated`, `xtreamAccount` etc. re-render Scores, Guide, Settings and the Player. `EpgStore` was split out for that reason; the rest still hammers. `ScoresTVRail(hasMatch: { … appModel … })` stores a closure per rail (P0-1, P0-3). Deployment target is **17.0**, so `@Observable` is available on both iOS and tvOS. |
| Lazy containers only build what is on screen; re-load only visible data, never the whole list. | — | Phone Scores and TV rails are already `LazyVStack`/`LazyHStack`; TV timeline rows are lazy. Inside them, though, `ForEach(games)` in `leagueBlock` sits in a non-lazy `VStack` (fine — short), and each recycled TV card re-fetches and re-decodes its logo through `AsyncImage` (P1-3). |
| Images: decode at the size you draw; never decode full assets for thumbnails. | Allocations, Time Profiler (`ImageIO`). | ESPN logos (500×500 PNG) decode full size for 44–56 pt boxes on every card/pill/rail logo (P1-3). |
| Launch: defer non-first-frame work; keep the first hierarchy simple; measure with the App Launch template. | App Launch template; Organizer Launch Time. | `AppModel.init()` reads Keychain and decodes prefs synchronously (prefs are decoded a second time in `SportsDashApp.init`); the three tabs are mounted under the splash (P2-1). |
| Write **performance tests** with baselines so the fix cannot regress: `measure(metrics:)` with `XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`; baseline discrete work at 100 ms, continuous at 5 ms. | XCTest, Release configuration, no coverage/sanitizers. | No perf tests exist (P2-6). |

Two rules that follow from the above and apply to every item:

1. **Main thread = UI only.** Anything that touches `channels` (5 000+ items), the EPG map, or sorts games runs in a `Task.detached`/actor and publishes **one** result.
2. **One publish per event.** A refresh, a merge, a focus move must invalidate the smallest view that actually shows the change, once.

---

## 2. Ranked work list

Format: **file** · *anti-pattern today* · **change** · *verify*.

### P0 — hangs and stalls users feel today

**P0-1 · Matching runs on the main thread inside `body`, once per row, on every invalidation**
- `SportsDash/App/AppModel.swift` `matches(for:)` (calls `MatchingService.matchGameToChannels` synchronously); `SportsDash/Features/Scores/ScoresView.swift:235` (hero `matchCount`), `:370` and `:385` (`hasMatch: { !appModel.matches(for: $0).isEmpty }` per TV rail), `:992` (`scoreRow`); `SportsDash/Core/Matching/MatchingService.swift` (`detectEventGroups` + `score` over **every channel** per game).
- *Today:* 30 games × 5 000 channels of string scoring ≈ 150 k `score()` calls per `ScoresView` body. Body runs on every `AppModel` publish (45 s poll, `isLoadingScores` flips, favorites, account refresh). This is the measurable Scores hang and the reason TV rails stutter while scores refresh.
- **Change:**
  1. Add to `AppModel`: `@Published private(set) var matchCountByGameId: [String: Int] = [:]` (after P0-3 it becomes a plain observed property).
  2. Add `private func rebuildMatchIndex()`; call it at the end of `refreshScores` (after `games` is set), in `applyChannels` when the list actually changed, and from `playerPrefs` changes that affect matching (none today). Body: snapshot `games` + `channels`, `Task.detached(priority: .userInitiated)` → `MatchingService().matchGameToChannels(g, channels:, limit: 1).isEmpty ? 0 : count` for each game (use `limit: 3` so the hero's "N STREAMS OK" stays correct up to 3; the detail sheet already computes the full list itself) → back on main set `matchCountByGameId` **once**. Debounce with a generation counter so a stale index never overwrites a newer one.
  3. `AppModel.matches(for:)` stays for `GameDetailSheet`/`PlayerView` pickers (they already run it detached), but no `View.body` may call it: replace the four call sites with `appModel.matchCountByGameId[game.id, default: 0]`. `ScoresTVRail` takes `matchedGameIds: Set<String>` (a value), not a closure.
  4. Rows that appear before the index is built show no WATCH for ≤ 1 s, then it appears — identical to today's behaviour after the first refresh. WATCH rules unchanged.
- *Verify:* Time Profiler, filter `MatchingService` — zero samples under `ScoresView.body` / `ScoresTVRail.body`; SwiftUI instrument "Long View Body Updates" for `ScoresView` < 1 ms on a 5 000-channel playlist; scores refresh with TV focus moving across a rail shows no hang > 100 ms in the Hangs track.

**P0-2 · Scores board is sorted, pinned and grouped inside `body`**
- `ScoresView.swift:196–207` (`scoresContent`: `myGamesPin`, `filteredGames`, `buildSections`), `AppModel.swift` (`filteredGames`, `myGamesPin`, `favoriteTeamsRail` are computed properties that filter/sort `games` on every read).
- *Today:* three full passes over `games` plus a stable sort per body evaluation; evaluation happens on every `AppModel` publish.
- **Change:** introduce `struct ScoreboardSnapshot: Equatable { pin: [Game]; sections: [SportScoreSection]; rail: [TeamInfo]; filter; }` and `@Published private(set) var board: ScoreboardSnapshot` on `AppModel`. Rebuild in one place, `rebuildBoard()`, called when `games`, `dashboardFilter`, `selectedLeagues`, `favoriteTeamIds` or `favoriteTeams` change (do it in the setters/`refreshScores` tail, not in a view). Grouping is pure (`ScoreboardGrouping` is already nonisolated) — run it in the same detached task as P0-1 and publish `board` and `matchCountByGameId` together. `ScoresView` reads `appModel.board.pin` / `.sections`; `LeagueShelf` and `SportScoreSection` get `Equatable` so `ForEach` diffs cheaply. Keep `filteredGames`/`myGamesPin` as thin accessors over `board` for the two non-view callers.
- *Verify:* SwiftUI instrument: `ScoresView` body ≤ 0.5 ms idle; Time Profiler shows no `pinFavoriteGames`/`sportSections` frames during focus movement or ticker refresh.

**P0-3 · Whole-object invalidation: `ObservableObject` + `@EnvironmentObject` for `AppModel` and `EpgStore`**
- `AppModel.swift` (24 `@Published`), `App/EpgStore.swift` (8), every `@EnvironmentObject private var appModel` (15 files), `RootTabView`, `SportsDashApp` (`@StateObject`), all `.environmentObject(…)` injection sites (8 pairs).
- *Today:* any published write (`isLoadingAccount`, `lastUpdated`, `xtreamAccount`, `channelsError`, `epgStatus`…) re-evaluates every screen and the full-screen player. The `EpgStore` split limited EPG ticks; the remaining 24 still fan out.
- **Change (Apple's recommended fix, do after P0-1/P0-2 have a before/after trace):**
  1. `@Observable @MainActor final class AppModel` — delete every `@Published`; leave stored properties as they are. Same for `EpgStore`. Keep `PlaybackController`/engines on `ObservableObject` for now (their Combine `$isLoading` sinks depend on it — P2-3).
  2. Views: `@EnvironmentObject private var appModel: AppModel` → `@Environment(AppModel.self) private var appModel`; `@EnvironmentObject private var epg: EpgStore` → `@Environment(EpgStore.self) private var epg`. `SportsDashApp`: `@StateObject` → `@State private var appModel = AppModel()`. `.environmentObject(appModel)` → `.environment(appModel)` (all 8 sites, both objects).
  3. Bindings into the model (`$appModel.dashboardFilter`, `$appModel.fullScreenPlayer`, `GeneralSettingsView` writes): add `@Bindable var appModel = appModel` at the top of that `body`.
  4. `epgFlushTask`/`Timer` closures already hop to `@MainActor`; nothing else changes. Tests that construct `AppModel()` still compile.
  5. Do **not** wrap in `withObservationTracking` anywhere; SwiftUI does it.
- *Verify:* SwiftUI instrument Cause & Effect: select a `ScoresView` update during an EPG load → no edge from `EpgStore`; during `refreshXtreamAccount` → no `ScoresView`/`GuideView` update at all. `Self._printChanges()` (temporary) prints only the property that changed.

**P0-4 · Player body rebuilds the ticker on every playback state flip**
- `Features/Player/PlayerView.swift:166–175` (`LiveScoresStrip(games: appModel.games.filter {…})`), `Features/Player/LiveScoresStrip.swift:18–48` (`liveOrdered` sort + `sportSections` grouping are computed properties read by `body`), `PlaybackController.swift:331–374` (VLC/AV engine flags forwarded as `@Published`; `isBuffering`/`isPlaying` flip repeatedly while VLC fills its cache).
- *Today:* each flip → `PlayerView.body` → filter `games`, sort ≤ 40 games, group into sections, rebuild pill views — while VLC decodes on the same device. This is the "janky while watching" residue that the EPG cadence change did not cover.
- **Change:** `PlayerView` keeps `@State private var tickerSections: [SportScoreSection]` and `@State private var tickerGames: [Game]`, recomputed in `.onChange(of: appModel.games)` (and once in `.onAppear`) — the sort/group runs off-main in a `Task.detached` and assigns on main. `LiveScoresStrip` receives the precomputed `sections`/`ordered` and becomes `Equatable` (compare game ids + status + scores, `currentGameId`, `favoriteTeamIds`), applied with `.equatable()`. Nothing in `LiveScoresStrip.body` may sort. Keep the strip's own collapse `@State`.
- *Verify:* SwiftUI instrument while a stream plays for 60 s: `LiveScoresStrip` body count ≤ number of `games` changes (≈ 1–2), not the number of `PlaybackController` publishes; Time Profiler: no `sportSections` under `PlayerView.body`.

**P0-5 · tvOS Guide re-hosts every visible timeline row on every invalidation**
- `Features/Guide/GuideView.swift:1532–1545` (`GuideLinkedScrollView.updateUIView`: `hosting.rootView = content()` + `scrollView.layoutIfNeeded()`), `:1199` (`timelineBlocks` computed per body).
- *Today:* any `GuideView` invalidation (EPG merge, minute tick, favorites, `epgStatus`) re-assigns the hosted SwiftUI root of every visible row and forces a synchronous UIKit layout — 10 rows × hosted relayout on the main thread, inside the SwiftUI commit. On a 4K Apple TV this is the Guide scroll stutter during a load.
- **Change:**
  1. `GuideTimelineRow` becomes `Equatable` on `(row.channel.id, row.programs, windowStart, nowMinute, isFavorite, cleanUpNames)` — pass `now` truncated to the minute (`nowTick` already ticks per minute) — and is used with `.equatable()` in `GuideTimelineGrid`.
  2. `GuideLinkedScrollView` gains `let contentKey: Int` (hash of the same tuple). In `updateUIView`, if `context.coordinator.lastKey == contentKey` → only run the offset-sync branch and return; otherwise assign `rootView`, set `lastKey`, and replace `layoutIfNeeded()` with `setNeedsLayout()` (the offset correction can run in `layoutSubviews` of a tiny `UIScrollView` subclass, or on the next runloop turn via `DispatchQueue.main.async`) — never force a synchronous layout inside a SwiftUI update.
  3. `timelineBlocks` → memoised in the row via `@State` keyed by the same tuple, or computed once in `GuideChannelRowData` when `guideRows` is built (P1-5) so the row is pure display.
- *Verify:* Time Profiler during an XMLTV load with the Guide open: `UIHostingController.rootView.setter` and `-[UIView layoutIfNeeded]` under `GuideLinkedScrollView.updateUIView` drop to zero while nothing visible changed; Animation Hitches while scrolling the timeline ≤ 10 ms/s.

### P1 — hitches and invalidation you can see on TV

**P1-1 · Per-element shadows = offscreen render passes (render hitches on TV rails)**
- `Theme/Jumbotron.swift` (`JumbotronLED` `.shadow` per digit, `jumbotronLedGlow`, `jumbotronLiveGlow`, `JumbotronWatchButton`, `JumbotronToggle` ×2, `JumbotronLampCard` lamp + CTA, `jumbotronTVFocusRing`, `JumbotronTVSidebar` row), `Features/Scores/ScoresTVGameCard.swift` (card focus `.shadow` + `WATCH` `.shadow` + 4–5 `JumbotronLED`s), `GuideView.swift` focus rings, `SettingsView.swift` tvOS rows.
- *Today:* a focused TV card composites ≈ 7 shadowed layers, each an offscreen pass, and the `scaleEffect` animation re-renders them for 14 frames; a rail shows 4–6 cards. Apple lists shadow/blur/mask offscreen rendering as the primary render-hitch cause.
- **Change (tvOS only; phone 005 pixels untouched):**
  1. `JumbotronLED`: on tvOS wrap the `Text` + shadow in `.drawingGroup(opaque: false)` — static digits are rasterised once by Metal and re-used until the text changes. Do not apply to phone (`#if os(tvOS)`).
  2. Cards/rows: replace the card-root `.shadow(color: ledGlow…)` with `.compositingGroup()` **before** the single focus `.shadow`, so the whole card is one offscreen pass rather than one per child. Same in `jumbotronTVFocusRing`, `GameScoreFocusRow` tvOS branch, Settings rows.
  3. Inside a card, remove the extra `.shadow` on `WATCH` and on `STREAM OK` when focused == false is not needed — one glow per card is the 006 look at 10 ft; keep the LED digit glow via the drawingGroup above.
  4. Focus ring animation: `.animation(SportsTVFocusMotion.animation, value: focused)` stays 0.14 s; do not add `repeatForever` glows anywhere (005 §7: static glow).
- *Verify:* Animation Hitches template on Apple TV (device, not simulator): scroll a 6-card rail end to end, hitch rate ≤ 10 ms/s, no render hitch > 16 ms. In the simulator, Debug → "Color Offscreen-Rendered Yellow" (Core Animation FPS instrument options) shows one yellow region per card, not per glyph.

**P1-2 · Sidebar collapse animates the page width — every rail relayouts per frame**
- `App/RootTabView.swift` `tvSidebarShell` (`HStack { JumbotronTVSidebar(expanded:) ; tvTabPage }` + `.animation(.easeOut(0.18), value: expanded)`), `Theme/Jumbotron.swift` `JumbotronTVSidebar` (`frame(width: expanded ? 280 : 72)`).
- *Today:* expanding the rail resizes `tvTabPage` from 1848 to 1640 pt; SwiftUI relayouts Scores rails / Guide grid / Settings for 11 frames. Collapse behaviour itself is product (keep it).
- **Change:** `ZStack(alignment: .leading) { tvTabPage.padding(.leading, 72) ; JumbotronTVSidebar(...) }` — the page keeps a constant width; the expanded rail overlays the first 208 pt of content with a `SportsColors.voidBlack.opacity(0.35)` scrim on the rail's trailing edge. Focus sections unchanged (`onExitCommand` still returns focus to the rail). Animate only the rail's width/opacity.
- *Verify:* Animation Hitches while pressing Menu on Scores and moving back: no commit hitch; Time Profiler shows no `ScoresTVRail.body` during the 0.18 s.

**P1-3 · Logos: `AsyncImage` per instance, full-size decode, re-fetch on recycle**
- `ScoresTVGameCard.swift` `logoBox` (2 per card), `ScoresView.swift:431` `railLogo`, `Features/Scores/GameMatchupRow.swift:30`, `Features/Player/LiveScoresStrip.swift:95`, `Features/Scores/FavoriteTeamPickerView.swift`.
- *Today:* each view instance owns its own load; `LazyHStack` recycling re-runs it; ESPN PNGs decode at native size on every card.
- **Change:** add `Theme/TeamLogo.swift`: `actor TeamLogoCache` (NSCache<NSString, UIImage>, 200 entries) with `func image(for url: URL, maxPixel: CGFloat) async -> UIImage?` that downloads via the shared `URLSession` (default `URLCache` on, 50 MB disk) and decodes with ImageIO `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize` = 2× the display size (88 / 112 px). `struct TeamLogo: View { url; size; fallback }` reads the cache synchronously first (`nonisolated` NSCache lookup) so recycled cards paint immediately, else `.task` loads. Replace the five `AsyncImage` sites. Same fallback glyph as today.
- *Verify:* Allocations: steady heap while scrolling a rail back and forth (no growth per pass); Time Profiler: `ImageIO` decode once per distinct URL per session; Network instrument: no repeat GETs for the same logo.

**P1-4 · `DateFormatter()` allocated in hot bodies**
- `GuideView.swift:1032` `hourLabel` (12× per timeline header body), `Core/Models/Game.swift:120` (`formatStartTime`, called from `statusLine` → every upcoming row, every body), `Core/Models/IptvChannel.swift:82`, `SportsAPI.swift:243/502–510` (off-main, leave), `EpgService.swift:791` (off-main, leave).
- **Change:** `static let` formatters with `locale = .autoupdatingCurrent` on the type (`Game.startTimeFormatter`, `GuideView.hourFormatter`); a `DateFormatter` is ~50 µs to create and not thread-safe to share across actors — main-thread only for these.
- *Verify:* Time Profiler filter `NSDateFormatter init` while scrolling Scores/Guide → 0 samples.

**P1-5 · Guide rows rebuilt on every Guide invalidation**
- `GuideView.swift:61–84` (`guideRows` → `dedupeChannels` + program lookup per channel per body), `:575` (`withGuide` count filters the category per body), `Features/Guide/GuideNowBarList.swift:25–35` (`playable` filter + `liveCount` per body).
- **Change:** `EpgStore` gets `@Published private(set) var revision = 0` (bump inside every write of `epgByChannel` — one place: make `epgByChannel` `private(set)` and add `func replace(_:)` / `merge(_:)` used by `AppModel`). `GuideView` keeps `@State private var rows: [GuideChannelRowData]` + `@State private var withGuide = 0`, rebuilt in one `.task(id: RowsKey(selectedGroup, moviesOnly, epg.revision, appModel.channels.count, cleanNames))` — the rebuild runs off-main (`dedupeChannels` is static) and assigns once. `GuideNowBarList` receives `playable` and `liveCount` as inputs, computed in the same rebuild (`liveCount` uses the minute `nowTick`).
- *Verify:* SwiftUI instrument: `GuideView` body ≤ 1 ms; `GuideNowBarList` updates only on `rows`/`nowTick`/favorites changes.

**P1-6 · Timers and the minute tick fan out to every row**
- `GuideView.swift:265` (`Timer.publish(every: 60)` → `nowTick` → every row's `now`), `AppModel.swift:323/337/359` (three `Timer.scheduledTimer`), `ScoresView` blink (`repeatForever` on `isLoadingScores`).
- *Today:* acceptable frequency; the cost is that `nowTick` is a `Date` with sub-second precision passed into every row, so `Equatable` rows (P0-5, P1-5) would still differ.
- **Change:** pass `nowMinute: Date` (truncated to the minute) into rows; one `AppClock` (`@Observable`, `minute: Date`) owned by `AppModel` replaces the Guide timer so Scores/Guide/Player share a single 60 s tick. Keep the 45 s scores poll, 15 min playlist poll, 30 min guide poll as they are (already `RunLoop.common`, already `weak self`).
- *Verify:* Cause & Effect: one update group per minute in Guide, rows with unchanged programs do not re-evaluate.

### P2 — launch, tests, secondary invalidation

**P2-1 · Launch path**
- `App/SportsDashApp.swift` `init` decodes `playerPrefs` (JSON) and registers fonts; `App/AppModel.swift` `init()` decodes prefs **again**, reads Keychain per playlist (`StorageService.loadPlaylists`), favorites, leagues — all synchronous on main before the first frame; `RootTabView` mounts all three tabs at `opacity 0.001` under the splash.
- **Change:** decode prefs once (pass the value into `AppModel.init(prefs:)`); keep Keychain (few ms) but move `favoriteTeams` JSON decode and `loadPlaylists` into `bootstrap()` right after the channels cache (they are needed before the first Scores paint only for the switchboard — provide empty defaults for the first frame). Leave the splash/tab strategy; measure it first.
- *Verify:* App Launch template on iPhone 12-class and Apple TV HD: time to first frame ≤ 400 ms / ≤ 800 ms; `AppModel.init` ≤ 20 ms in the Time Profile lane.

**P2-2 · `PlaybackController` → `@Observable`** — after P0-3 has a clean trace. Keep engines as `ObservableObject` and bridge with `.sink` as today, or replace the eleven forwarded flags with a single `PlaybackState` struct published once per engine callback (fewer publishes even without the migration).

**P2-3 · `MovieRatingsStore` publishes per rating** — `Features/Player/MovieRatingsStore.swift` (`@Published ratings`, `loading`): every arrival re-renders every `MovieRatingLoader` on screen. Coalesce writes (collect for 300 ms, publish once) and make `MovieRatingLoader` `Equatable` on its key.

**P2-4 · Materials over video on the phone floating player** — `FloatingPlayerView.swift` (7× `sportsGlass`) is allowed by 005 §6, but each is a live blur over decoding video on iOS < 26. Measure GPU with Metal System Trace; only if GPU > 40 % while floating, switch the seven circles to one glass capsule container (visual review needed — not in this pass).

**P2-5 · Android parity pointers (one line each; same stall pattern exists)**
- `android/.../AppViewModel.kt:108` `AppUiState` is one `StateFlow` collected in `SportsDashRoot.kt:73` — every EPG/score/status write recomposes every screen = P0-3's pattern; the `EpgUiState` split is in `sketches/006-jumbotron-tv/SPEC.md §7`.
- If the Kotlin matcher is called from a composable per row (check `ScoresScreen.kt` `WATCH` gating), hoist it exactly like P0-1 (`matchCountByGameId` in the VM, computed on `Dispatchers.Default`).
- Logo loading already goes through Coil (cached, downsampled) — no P1-3 equivalent.

**P2-6 · Performance tests (XCTest, `SportsDashTests/`)** — Release configuration, no coverage, no sanitizers:
- `MatchingPerfTests.testBoardMatchIndex`: 30 synthetic games × 5 000 channels through `MatchingService` — `measure(metrics: [XCTClockMetric(), XCTCPUMetric()])`, baseline whatever P0-1 measures, max STDDEV 15 %.
- `ScoreboardPerfTests.testSportSections`: 400 games → `ScoreboardGrouping.sportSections`, baseline ≤ 5 ms (continuous-interaction budget).
- `XmltvPerfTests.testStreamScan50MB`: generate 50 MB XMLTV in `setUp` (temp file, reused), `XmltvStreamScanner` in 64 KB chunks — `XCTClockMetric` + `XCTMemoryMetric`; baseline on Samir's Mac; guards the parser.
- `GuideRowsPerfTests.testDedupe2000Channels`: `GuideView.dedupeChannels` (make it `internal static`) — baseline ≤ 5 ms.

---

## 3. Do / Do not

**Do not**
- Change product IA (Scores · Guide · Settings), WATCH rules (only when matched; filled on hero, outline on rows), the VLC/AVPlayer engine split, or add Cast / multiview / remote push.
- Un-collapse or re-time the TV rail collapse; P1-2 changes only *how* the page is laid out under it.
- Pixel-break phone 005: every `#if os(iOS)` Jumbotron branch and `sketches/005-jumbotron/phone.png` must match after each PR (compare screenshots on the same simulator).
- Add `@Published`/observed properties that are written more than once per user-visible event.
- Call `MatchingService`, `ScoreboardGrouping`, `dedupeChannels`, JSON decode, Keychain, or `DateFormatter()` from any `View.body`, `onAppear`, `onChange`, or `updateUIView`.
- Use `drawingGroup()` on views containing `AsyncImage`/`TeamLogo` that are still loading, or on anything that scales every frame (rasterisation per frame is worse than the shadows).

**Do**
- Keep the main thread free: heavy work in `Task.detached`/actors, one publish back.
- Reduce SwiftUI invalidation: `@Observable` for `AppModel`/`EpgStore`; `Equatable` + `.equatable()` on row/card/strip views; values (`Set<String>`, snapshots) instead of closures in view inputs; stable identity (`game.id`, `channel.id`) in every `ForEach`.
- Lazy lists: `LazyVStack`/`LazyHStack` stay; do not put full-list work inside a lazy child.
- Cheaper materials/shadows on TV: `compositingGroup()` + one shadow per card; `drawingGroup()` on static LED text; no `repeatForever` glows.
- Timers: one shared minute tick; keep polls on `RunLoop.common`, `weak self`, and skip while a load is in flight (already true for the guide poll).
- Image/logo loading through one downsampling cache.
- Record a **before** trace for every P0 (§4) and attach both traces to the PR.

---

## 4. Instruments checks for Samir (Xcode → Product → Profile, Release scheme, device where possible)

Run each before Grok's PR and after; keep the `.trace` files.

| # | Check | Template / steps | Pass |
|---|---|---|---|
| 1 | **Scores hang** | Time Profiler on iPhone + Apple TV. Open Scores with a ≥ 5 000-channel playlist, wait for two 45 s polls, move focus/scroll during the second. In the track list enable **Hangs**. Filter call tree by `MatchingService`. | No hang ≥ 100 ms; zero `MatchingService` samples under `*.body`. |
| 2 | **Body cost / fan-out** | **SwiftUI** template, 60 s, during an XMLTV load with Scores visible; then switch to Guide; then Settings. Lanes: *Long View Body Updates*, *Update Groups*. Right-click an update → *Show Causes*. | No red (> 1 ms) body for `ScoresView`, `GuideView`, `PlayerView`; Cause & Effect for a `ScoresView` update never starts at `EpgStore` or at `AppModel.isLoadingAccount`/`lastUpdated`. |
| 3 | **Rail hitches (TV)** | **Animation Hitches** on Apple TV device. Scroll a 6-card rail end to end twice; expand/collapse the sidebar 5×. | Hitch rate ≤ 10 ms/s; no render hitch > 16 ms; commit hitches 0 during collapse. |
| 4 | **Offscreen passes (TV)** | Core Animation FPS instrument (or simulator Debug menu) → **Color Offscreen-Rendered Yellow** with a rail focused. | One yellow region per focused card, none per LED glyph. |
| 5 | **Player jank** | **SwiftUI** template + **Time Profiler** while a VLC stream plays 60 s with the ticker on Persistent. | `LiveScoresStrip` body updates ≤ 3; main-thread CPU from the app < 10 % (VLC threads excluded); no `sportSections`/`sort` under `PlayerView`. |
| 6 | **Guide timeline (TV)** | Time Profiler with Guide open during an XMLTV load; filter `layoutIfNeeded` and `rootView`. Then Animation Hitches while scrolling the timeline. | Both ≈ 0 while no visible row changed; scroll hitch rate ≤ 10 ms/s. |
| 7 | **Logos** | **Allocations** + **Network**: scroll a rail back and forth 5×. | Heap flat after the first pass; each logo URL fetched once. |
| 8 | **Launch** | **App Launch** template, cold launch ×3 on iPhone 12-class and Apple TV HD. | First frame ≤ 400 ms / ≤ 800 ms; `AppModel.init` ≤ 20 ms. |
| 9 | **Field data** | Xcode Organizer → Hangs / Hitches / Launch for the TestFlight build after the PR. | Hang rate trending down vs previous build; no new hang signature in `ScoresView`/`GuideView`. |
| 10 | **Regression guard** | Run the P2-6 XCTest performance tests from the scheme (Release, no coverage). | All within baseline + max STDDEV. |

Also flip on **Thread Performance Checker** in the Run scheme diagnostics and, on the dogfood iPhone, Settings → Developer → **Hang Detection** with the 250 ms threshold; both surface regressions without Instruments open.

---

## 5. Grok task list (paste as-is)

1. Record before-traces for Instruments checks 1, 2, 3, 5 on `d279bec`; attach to the PR.
2. P0-1: `matchCountByGameId` on `AppModel`, built off-main on `refreshScores`/`applyChannels`; remove all `matches(for:)` calls from views; `ScoresTVRail` takes `matchedGameIds: Set<String>`.
3. P0-2: `ScoreboardSnapshot` (`pin`, `sections`, `rail`) published once per board change; `ScoresView` reads it; `LeagueShelf`/`SportScoreSection` `Equatable`.
4. P0-4: `PlayerView` keeps ticker data in `@State` rebuilt `onChange(of: games)` off-main; `LiveScoresStrip` takes precomputed sections, `Equatable` + `.equatable()`.
5. P0-5: `GuideTimelineRow` `Equatable`; `GuideLinkedScrollView.updateUIView` skips re-host when `contentKey` unchanged and never calls `layoutIfNeeded()`.
6. Re-profile checks 1, 2, 5, 6; then P0-3: `@Observable` for `AppModel` and `EpgStore` (`@Environment`, `.environment`, `@Bindable`), engines stay `ObservableObject`.
7. P1-1: tvOS-only `drawingGroup()` in `JumbotronLED`, `compositingGroup()` + one shadow per card/row/chip; delete inner `WATCH`/`STREAM OK` shadows on TV.
8. P1-2: sidebar as `ZStack` overlay over a constant-width page; collapse behaviour and timing unchanged.
9. P1-3: `TeamLogoCache` + `TeamLogo` (ImageIO downsample, NSCache); replace the five `AsyncImage` sites.
10. P1-4 + P1-6: static `DateFormatter`s; `nowMinute` into rows; one shared minute clock.
11. P1-5: `EpgStore.revision`; `GuideView` rows/counts in `@State` rebuilt off-main via `.task(id:)`; `GuideNowBarList` takes `playable`/`liveCount`.
12. P2-6 perf tests with baselines; P2-1 single prefs decode; verify phone 005 screenshots pixel-identical and re-run Instruments checks 1–8 after.
