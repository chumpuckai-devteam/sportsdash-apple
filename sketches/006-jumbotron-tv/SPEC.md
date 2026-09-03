# 006 · Jumbotron TV — SPEC

Build from this file. `index.html` is the reference render (1920×1080 frames). Phone lock is
`sketches/005-jumbotron/` — every token, state and rule there applies unless this file overrides
it for 10-foot. Where 005 and this file disagree on a TV surface, this file wins.

Parity target: a person who uses the phone app should sit down at the TV and see the **same
product** — same three screens, same favorites model, same WATCH rule, same guide data at the
same speed — laid out for a couch, not a thumb.

## 0. Parity contract (explicit)

| Law | Phone (005, shipped) | TV (this drop) |
|---|---|---|
| Tokens | `SportsColors` / `Theme.kt` Jumbotron set | **Same values, no third palette.** TV-only additions in §1 |
| IA | Scores · Guide · Settings | Same three; no Channels tab; no fourth tab |
| Favorites | Teams on Scores (league-scoped ESPN ids), channels on Guide | Same two domains, same storage, same pickers |
| WATCH | Rendered only when `matches(for:)` is non-empty; filled on hero, outline on rows | Same rule: card shows filled WATCH only when matched, otherwise `NO STREAM` caption, card still selectable for details |
| My Games | First pinned favorite game is the hero | My Games **rail first** (existing), hero treatment on the first card |
| EPG | `EpgStore` · `XmltvStreamScanner` streaming parse · throttled publishes · negative short-EPG cache · playlist refresh honoured | **Identical pipeline; no TV fork.** Extra TV duties in §6 |
| States | loading / empty / error / no playlist / no favorites / partial warning | Same six, 10-foot sizes (§5) |
| Player | Full-screen cover; phone has pop-out | **Full-screen only; pop-out does not exist on TV** |
| Chrome | Switchboard filter, Now-bar list, 80pt tab bar | **Not ported.** TV keeps rails, chips, timeline rows, system/bottom shell (§4) |

## 1. Tokens

Reuse 005 §1 verbatim: `void`, `panel`, `panelElevated`, `border`, `gold`, `goldDim`, `live`,
`danger`, `text`, `textSecondary`, `muted`, `gridDot`, `ledGlow`, `liveGlow`, `panelGradient`,
`digitBox`, team edge accents, `JumbotronBrand.stripe` / `brandStripe()`.

TV-only additions (add to `SportsTVMetrics` / a new `TvJumbotron` object in `Jumbotron.kt`):

| Token | Value | Use |
|---|---|---|
| `tvHairline` | **3pt** (`3.dp`) | Every line that is 1–2pt on phone: panel border, row divider, toggle border, digit box. 1pt vanishes at 10 feet on 1080p; 2pt shimmers on interlaced/scaled panels |
| `tvFocusRing` | 3pt `gold` border + `.shadow(color: ledGlow, radius: 14)` | Every focusable panel/card/row/chip when focused. Replaces the current `border.opacity(0.35)` → `gold` swap |
| `tvFocusScale` | `SportsTVMetrics.focusScale` = **1.045** (cards/rows); `chipFocusScale` 1.06 (chips/icons) | Existing; keep |
| `tvFocusFill` | gold fill + `void` text | Chips, channel cells, icon buttons when focused (existing S-TV.1 rule). Cards/rows do **not** fill — they ring + glow so team colors stay readable |
| `tvGridDot` | 2pt dot on a **12pt** grid, `gridDot` color | Screen ground on tvOS (`JumbotronGridDot` tile ×2) and Android TV (`gridDotGround` with 12dp step). 6pt phone grid aliases on TV |
| `tvEdgeBar` | **6pt** team edge bars | Cards and hero (5pt phone bar reads as 1px at distance) |
| `tvStripe` | **6pt** brand stripe | Guide channel cell |
| `tvRivet` | 8pt | Hero card only |
| Glow radii | ledGlow radius 10 (digits), 14 (focus); liveGlow 8 | Static, never pulsing (005 §7) |

Radius stays **0** on every Jumbotron panel/card/row/chip on TV. `SportsTVMetrics.focusCorner` (18)
and `channelCorner` (14) become 0 for Jumbotron surfaces; keep 18 only on the player's circular
transport buttons (they are circles) and on system sheets.

## 2. Type, spacing, hit targets (1080p points)

Fonts are the 005 bundle: Bebas Neue (display), Orbitron Black (digits), Space Mono (body). Already
in the tvOS target via `JumbotronFonts.register()`; Android `res/font` is shared with phone.

| Role | Face | TV size | Phone (005) | Where |
|---|---|---|---|---|
| Screen title | Bebas | **64** | 40 | `SCORE**BOARD**`, `CHANNEL **GUIDE**`, `CONTROL **ROOM**` |
| Rail / section header | Bebas | **30** | 20 | `★ MY GAMES`, `PREMIER LEAGUE` |
| Team abbr (card) | Bebas | **34** | 22 | |
| Team name (hero card) | Bebas | **44** | 32 | |
| Chip / tab label | Bebas | **26** | 18/20 | filters, category button, GRID / MOVIES |
| Settings row label | Bebas | **30** | 22 | |
| Guide channel name | Bebas | **26** | 18 | 220pt channel column |
| Hero digit | Orbitron 900 | **96** | 58 | first My Games card only |
| Card digit | Orbitron 900 | **44** | 26 | 005 §6 already says 44 |
| Status LED | Orbitron 900 | **18** | 12 | `Q4 · 3:12`, `67'`, `▲ 7` |
| Guide channel no. | Orbitron 900 | **16** | 13 | |
| Guide time / `LIVE` badge | Orbitron 900 | **14 / 12** | 10 / 8 | program blocks |
| Body / caption | Space Mono 400 | **16 / 14 / 13** | 11 / 10 / 9 | records, program subtitles, footers |
| Header clock / counters | Orbitron 900 | **28 / 16** | 16 / 10 | |

Spacing:

- Screen inset **48pt** (existing rail inset). Rail gap **36pt**. Card gap inside a rail **24pt**.
- Card **420×236** on tvOS (existing `ScoresTVGameCard`), **380×210 dp** on Android TV (existing). Hero card (first My Games card) is **560×236** / **500×210 dp**.
- Guide rows **88pt** tvOS (`SportsTVMetrics.channelRowHeight`), Android TV keeps its existing TV timeline row height; channel column 220pt; hour column 280pt (`pxPerHour` ×2 of phone).
- Settings rows **66pt** min (`minFocusSize`), secondary rows 56pt. Toggle **72×36**, knob 30×26.
- Chips **56pt** tall, min width 160pt.
- **Every focusable ≥ 66pt on tvOS** (`SportsTVMetrics.minFocusSize`); ≥ 56dp on Android TV. Focus scale needs 8pt margin around cards — keep rail vertical padding 14.
- Safe area: nothing focusable or textual inside the outer **60pt** (tvOS title-safe); Android TV uses the same 60dp inset instead of 40dp.

## 3. Component inventory

| Component | Anatomy (TV) | Focus | Live | Upcoming | Final | Unmatched |
|---|---|---|---|---|---|---|
| **TV score card** (`ScoresTVGameCard` / Compose `ScoresTVGameCard`) | `panelGradient`, 3pt `border`, radius 0, 6pt away/home edge bars; row 1 logo 56 + abbr 34 · status LED · logo + abbr; row 2 two `digitBox` LEDs 44; row 3 matchup caption 13 + WATCH filled (36pt tall, Bebas 22) right | ring + glow + 1.045 | status `live` LED, caption (`2ND HALF`), trailing digit 0.5 opacity | digits `–` muted; status = start time muted LED | `FINAL` muted, loser 0.5 | caption `NO STREAM MATCHED` muted, **no WATCH**; card still opens detail |
| **Hero card** (first My Games card) | 560 wide; hero bleed (away 0.55 / panel / home 0.60) over `panelGradient`; `live @ 0.45` border; 8pt rivets; team names 44 + records 16; digits **96** in boxes; clock LED 28; streams caption + filled WATCH | same | same | | | |
| **Rail** (`ScoresTVRail`) | header: 6×24 league-color tick + Bebas 30 + right `N LIVE` mint LED 16 (or `N UPCOMING` / `N FINAL` muted); `LazyHStack` cards; `.focusSection()` per rail | left/right within rail, up/down between rails (existing) | | `None scheduled` Space Mono 16 muted for empty selected leagues (existing) | | |
| **My Games rail** | title `★ MY GAMES`, gold tick; hero card first, then plain cards | | | | | hidden when no favorite games (existing) |
| **Filter chips** (tvOS `SportsFilterChip`, Android `ScoreFilterChip`) | 56pt, Bebas 26, `panelGradient` + 3pt `border`; selected = gold fill + `void` text + glow; count LED 16 right | gold fill (same as selected) + 1.06 — distinguish by the count LED turning `void` | | | | |
| **Edit favorites chip** | `★ EDIT FAVORITES` outline gold, opens `FavoriteTeamPickerView` / picker screen (existing) | | | | | shows `★ PICK TEAMS` when none |
| **Guide channel cell** | 220×88: 6pt brand stripe · LED no. 16 gold · Bebas 26 name (2 lines) · `★` when favorite | gold fill + `void` text (existing S-TV.1) | | | | |
| **Guide program block** | `panelGradient`, 3pt `border`, title Space Mono 700 16, time LED 14; airing block: `gold @ 0.18` fill, gold border, `LIVE` Orbitron 12 right | blocks are not focusable (row-level focus on channel cell; select = play) | | | | gap blocks `panel @ 0.35`, label `No guide` |
| **Guide time header** | 36pt, hours Bebas 22 `goldDim`; now marker 3pt `live` line + `▼ 19:42` LED 14 | | | | | |
| **Guide action bar** | category button (in-content, 66pt, `★ FAVORITES ▾` gold outline) · GRID · MOVIES chips · `RELOAD` icon | gold fill | | | | |
| **Guide status strip** | `GUIDE 62/80 IN THIS CATEGORY` Space Mono 14 + right `epgStatus` (only when it contains "ready") — existing logic | — | | | | |
| **Settings hub** (`SettingsView` tvOS / `SettingsScreen` TV) | lamp card full width at top; then `SOURCE` and `SYSTEM` panels in a **two-column** grid (1080p has the width; one long list wastes it); rows: 36pt icon cell · Bebas 30 · value Space Mono 16 · chevron / toggle 72×36 | row ring + glow; toggle ring | | | | |
| **Lamp card** (`JumbotronLampCard`) | lamps 14pt; `SETUP n/3` Bebas 32 + LED 30; CTA gold filled 44pt tall | CTA focus = ring | | | | |
| **Shell — tvOS** | **System `TabView`** (top tab bar), `.tint(gold)`. Not the phone `JumbotronTabBar` | system | | | | |
| **Shell — Android TV** | Existing bottom `NavigationBar` restyled: `panel` fill, 3pt top `border`, Bebas 26 labels, 28×4 lamp above active (gold + glow) — i.e. `JumbotronTabBar` at TV size. Top app bar removed; the screen title replaces it | ring on items | | | | |

Rules carried from 005: trailing side digit 0.5 opacity; `Program` when no title; channels without a
playable URL are not listed; brand stripe from channel **group** only, no per-channel logo colors.

## 4. Platform table

| Surface | Do | Don't |
|---|---|---|
| **Apple TV** | System `TabView` shell tinted gold; Netflix rails with My Games first; hero card in rail; `SportsFilterChip` restyled; Guide = `GuideTimelineGrid` 88pt rows + brand stripe; opaque full-screen category picker (existing); Settings two-column hub with lamp card; `sportsPlayerCover` full screen; `SportsTVFocused` + `sportsTVFocusClean()` everywhere; grid ground via `JumbotronGridDot` tile ×2 | No `JumbotronTabBar`, no switchboard, no Now-bar list, no `GuideNowBarList`, no `.buttonStyle(.card)`, no white focus plume, no Liquid Glass/material on panels, no 1–2pt hairlines, no rounded panels, no pop-out, no floating player, no alerts section (tvOS notification service is a no-op) |
| **Android TV** | Same rails/cards via `ScoresTVBrowse`; bottom nav restyled as Jumbotron tab bar; Guide keeps existing TV timeline/grid surfaces + brand stripe on the channel cell; Settings hub with lamp card (ALERTS section stays — Android alerts exist on TV as app-refresh-observed); `tvFocusRing` upgraded to 3dp + glow (`Modifier.shadow` is not glow — draw the ring with `drawBehind` blur or a second border at 0.35 alpha); `gridDotGround()` at 12dp; full-screen `PlayerScreen`, `onPopOut` stays `{}` on TV | No top app bar, no Material3 elevation shadows, no ripple other than gold @ 0.2, no phone Now-bar/switchboard, no pop-out (`isTelevision` gate stays), no `NavigationBar` default indicator pill |
| **Phone (both)** | Untouched by this drop | Do not touch `JumbotronScoreRow`, `JumbotronHeroBoard`, `GuideNowBarList`, phone switchboard |

## 5. States (10-foot)

| State | Scores | Guide | Settings |
|---|---|---|---|
| Loading (first) | chips shown; one rail titled `LOADING…` with 3 skeleton cards 420×236 in `panelGradient` + `border` shimmer, no LED | action bar + 6 skeleton rows 88pt | rows render; values `…` muted LED |
| Refreshing | header `●` blinks 1 Hz (existing) | now marker updates | — |
| Empty (filter) | one panel 960 wide centered: Bebas 40 `emptyTitle`, Space Mono 16 subtitle, outline gold CTA (`UPCOMING ▸` / `LEAGUES ▸`) — replaces `ContentUnavailableView` | `NO CHANNELS IN THIS CATEGORY` panel + `CHOOSE CATEGORY` CTA (focusable) | — |
| Error | panel with `danger` tick, `SCORES UNAVAILABLE`, error text, outline `RETRY` focusable | `EPG UNAVAILABLE` + `RELOAD EPG` | Xtream status LED `danger`: `EXPIRED` / `OFFLINE` |
| No playlist | lamp card full width above the rails (`SetupChecklistCard`, TV size) | full-screen lamp card `LOAD A PLAYLIST FIRST` + gold CTA to Settings (focusable; the only focusable on screen) | lamp card at top |
| No favorites | no My Games rail; edit chip reads `★ PICK TEAMS` | `★ FAVORITES` falls back to first populated group (existing rule) | `FAVORITES` lamp gold |
| Partial scores warning | one-line strip under chips: `danger` tick + Space Mono 14, no panel (existing `scoresWarning` text) | — | — |

Focus never lands on a skeleton, a status strip, or a gap block. Every empty/error state has exactly
one focusable CTA and it receives default focus.

## 6. Focus, D-pad, Back

- **tvOS**: `SportsTVFocused` + `sportsTVFocusClean()` on every control; `.focusSection()` per rail, per chip row, per Guide list (existing). Default focus on launch = first chip (LIVE) via `prefersDefaultFocus` in the Scores `focusScope`; on Guide = first channel cell (existing `GuideDefaultFocusModifier`). Menu/Back: pops the player cover, then the category picker, then goes to the tab bar (system). Play/Pause on a focused card = WATCH if matched, else no-op.
- **Android TV**: `tvFocusRing` / `tvFocusGroup` (existing) upgraded per §1; `LazyRow` rails keep `tvFocusGroup()`; Back: player → hide chrome → exit player; Guide category picker → Back closes; root → system. D-pad center on card = same as click (detail/stream picker); long-press = favorite toggle (existing `onGameLongClick`).
- Focus ≠ selection (HIG): selected chip is gold-filled; focused unselected chip is also gold-filled but its count LED goes `void` and it scales — accepted per S-TV.1. Cards/rows never fill on focus.
- Focus must not be stolen by EPG ticks: rails/rows are keyed by stable ids (`game.id`, `channel.id`); an `EpgStore` publish must not recreate the `LazyHStack`/`LazyRow` identity (§7).

## 7. EPG + speed on TV

Inherited from this branch, **unchanged** (do not fork for TV):

- `EpgService.loadGuide` → streaming `XmltvStreamScanner` (no temp file, no 120 MB reject, 1 GB abort guard), `XmltvTime` integer parse, `XMLParser` fallback.
- `EpgStore` observed only by Guide / Player / Settings; Scores never re-renders on EPG ticks.
- Merge flush 350 ms (2.5 s while a player is on screen), status ≤ 2 Hz (3 s in player), debounced off-main cache write, off-main channel cache encode, unchanged playlist not republished.
- Short-EPG negative cache (6 h per host) + in-flight dedupe; manual Reload EPG bypasses it.
- Last-good bulk URL first; no `type=m3u_plus` duplicates; ETag / Last-Modified conditional GET while the map is < 12 h old; 304 keeps the build stamp.
- Launch playlist refresh honours `playlistRefresh` (Manual skips).

TV-specific duties (new work in this drop):

1. **Don't block first rail paint.** Scores must paint from `games` alone. On tvOS `PlayerView`/`GuideView` are the only `EpgStore` observers; on Android, `ScoresScreen` must **not** read `state.epgByChannelId` — pass Guide-only slices (see 4 below).
2. **In-session refresh on a long-lived process.** A TV stays open for days. Add a `Timer` (tvOS) / `viewModelScope` ticker (Android) every **30 min** that: reloads scores (already 45 s), and calls `reloadEpg(force: true)` when `lastEpgReload` is older than **3 h** (same threshold as launch). Because the map's build stamp survives 304s, the 12 h age triggers a real download at most twice a day. Never run it while `isLoadingEpg`.
3. **Player-aware cadence on TV too.** `playerDidAppear/Disappear` must be called from the tvOS `PlayerView` (same file, already done) and the Android `PlayerScreen` (add `isPlayerOnScreen` to the VM: flush batches at 2.5 s while true).
4. **Android: stop copying `AppUiState` per EPG batch.** `AppUiState.epgByChannelId` lives in the one monolithic `StateFlow`; every `st.copy(epgByChannelId = …)` re-emits the whole state to every collector (Scores, Settings, shell) — the Android twin of the `AppModel` problem this branch fixed on iOS. Split `epgByChannelId`, `epgStatus`, `isLoadingEpg`, `isAutoFillingEpg` into an `EpgUiState` on its own `StateFlow` (`vm.epg`), collected only by Guide, Player and the Settings lamp. Batch merges coalesce at 350 ms (`conflate()` + delay) — do not `update` per short-EPG wave.
5. **Android: remove the 150 MB reject.** `EpgRepository.MAX_DOWNLOAD_BYTES` rejects after download, like iOS did. Stream the OkHttp body through `XmlPullParser` (it already takes an `InputStream`) instead of `downloadXmltvToFile` → parse; keep the file cache only for the parsed `tvgCache`. Window stays −6/+36 h, 16 per channel (Android's existing numbers; do not change to iOS's −1/+18/12 in this drop).
6. **Android: negative short-EPG cache + in-flight dedupe** in `EpgRepository`, same rules as `EpgService` (6 h per host, empty-200 only, manual reload bypasses).
7. **Android: last-good bulk URL first** and drop `type=m3u_plus` from `xtreamXmltvUrls`.
8. Guide rows on TV render **Now / Next / +1** only from `programs(for:)`; the 12-hour timeline window on tvOS (`GuideMetrics.hours = 12`) stays, but blocks outside `[now − 1 h, now + 4 h]` are not materialised until the row scrolls (they are already lazy per row; make `buildTimelineBlocks` lazy per hour column).

Speed acceptance numbers are in §11.

## 8. Player (product law)

- Full-screen only: `sportsPlayerCover` on tvOS, full-screen `PlayerScreen` on Android TV. No pop-out, no floating player, no PiP control, no "Pop out player" menu item (already gated; keep the gate).
- Chrome: existing circular transport buttons keep radius (circles); ticker pills adopt gold LED digits (005 §4 "Ticker"). Program info block: channel group Bebas 20 gold · name Bebas 34 · program Space Mono 18 · `Next:` 16. Engine chip unchanged.
- Back/Menu hides chrome first, then dismisses (existing).
- Player observes `EpgStore` for now/next only; it must not observe `AppModel` for anything EPG-related.

## 9. Blocked (do not build, do not stub UI for)

Cast · multiview · remote push · a Channels tab · TV pop-out / floating player · a fourth tab ·
per-channel logo color fetching · a separate Android TV application id or BrowseFragment.

## 10. File map

Apple (`SportsDash/`, tvOS scheme `SportsDashTV`):

| File | Change |
|---|---|
| `Theme/SportsColors.swift` | `SportsTVMetrics`: add `hairline = 3`, `edgeBar = 6`, `stripe = 6`, `rivet = 8`, `gridStep = 12`; set `focusCorner`/`channelCorner` to 0 for Jumbotron surfaces (keep a `circleControl` case for player buttons) |
| `Theme/Jumbotron.swift` | `JumbotronGridDot` tile ×2 on tvOS; `JumbotronLED` glow radii by platform; add `JumbotronTVFocusRing` view modifier (3pt gold + ledGlow, scale) used by cards/rows/chips |
| `Features/Scores/ScoresTVGameCard.swift` | Rebuild card + rail chrome per §3 (edge bars, digit boxes, LED status, WATCH-only-when-matched → needs `hasMatch: Bool` from `appModel.matches(for:)`, computed off the hot path as on phone); add `ScoresTVHeroCard` (first My Games card) |
| `Features/Scores/ScoresView.swift` (`#if os(tvOS)` branches) | Title `JumbotronScreenTitle` 64; chip row restyle; My Games hero; empty/error/warning panels per §5; default focus on LIVE chip; 30-min refresh hook |
| `Features/Guide/GuideView.swift` (`GuideTimelineGrid`, `GuideTimelineRow`, channel cell, time header) | Brand stripe + LED channel no. in cell; radius 0; 3pt lines; airing block gold; now marker; action bar restyle; status strip; skeleton rows |
| `Features/Settings/SettingsView.swift` (`#if os(tvOS)` branches) | Two-column hub, lamp card, 66pt rows, 72×36 toggles; no alerts section on tvOS |
| `Features/Player/PlayerView.swift` | Program info type only; no structural change |
| `App/AppModel.swift` | `startGuideRefreshPolling()` (30 min, tvOS + iOS both fine) calling `reloadEpg(force:true)` when stale > 3 h |
| `App/RootTabView.swift` | `legacyTabView` `.tint(gold)`; nothing else |
| `SportsDashTests/` | `ScoreboardGrouping.tvScoreRails` unchanged; add a test that the refresh poll is a no-op while `isLoadingEpg` |

Android (`android/app/src/main/java/com/samirpatel/sportsdash/`):

| File | Change |
|---|---|
| `ui/theme/Theme.kt` | `TvHairline = 3.dp`, `TvEdgeBar = 6.dp`, `TvStripe = 6.dp`, `TvGridStep = 12.dp`, `TvChipHeight = 56.dp`, `TvRowMin = 56.dp` |
| `ui/theme/Jumbotron.kt` | `gridDotGround(step)`; `jumbotronPanel(border, width)`; `JumbotronTabBar(tv = true)` sizes; `JumbotronLed` glow by profile |
| `ui/tv/TvFocus.kt` | `tvFocusRing`: 3dp gold + glow layer (second border gold @ 0.35 at +3dp, or `drawBehind` blur), `scaleFocused` 1.045 default, shape default `RectangleShape` |
| `ui/ScoresScreen.kt` (`ScoresTVBrowse`, `ScoresTVRail`, `ScoresTVGameCard`, `ScoresTVTeamBlock`, `ScoreFilterChip` tv path) | Card/rail chrome per §3; hero card; `hasMatch` from `vm.matchesFor(game)`; empty/error panels; no `Surface` elevation |
| `ui/GuideScreen.kt` (TV branches: `GuideActionBar`, timeline/grid rows, channel cell) | Brand stripe, LED no., 3dp lines, airing block gold, now marker, status strip |
| `ui/SettingsScreen.kt` | TV two-column hub; lamp card already Jumbotron; row heights/toggle sizes by `isTelevision` |
| `ui/SportsDashRoot.kt` | Remove top app bar on TV; `JumbotronTabBar(tv = true)` replaces Material `NavigationBar`; `gridDotGround()` also on TV (currently `background(VoidBlack)` only) |
| `ui/PlayerScreen.kt` | `vm.playerDidAppear()/playerDidDisappear()` |
| `AppViewModel.kt` | `EpgUiState` + `val epg: StateFlow<EpgUiState>`; 350 ms coalesced merge; `isPlayerOnScreen`; 30-min guide refresh ticker |
| `core/epg/EpgRepository.kt` | Stream parse from `InputStream` (drop `MAX_DOWNLOAD_BYTES` reject; keep a 1 GB abort); negative cache + in-flight set; last-good URL; drop `type=m3u_plus` |
| `ui/EpgLoadingCard.kt` | Restyle as Jumbotron skeleton panel |
| `app/src/test/…` | `EpgRepository` chunk-boundary test mirroring `XmltvParserTests` (feed the same XMLTV through 1-byte and 4 KB streams, compare maps) |

Do **not** touch: matching (`MatchingService` / Kotlin matcher), `PlaybackController` / `VlcPlayerController`, the phone Jumbotron components, `ScoreboardGrouping`.

## 11. Acceptance (Apple TV simulator + Android TV AVD, 1080p)

Visual / parity:

- [ ] All three screens use the 005 palette only; no Material3 surface tint, no system blue, no white focus plume.
- [ ] Every hairline ≥ 3pt/dp; every panel radius 0; team edge bars 6pt on every score card; brand stripe 6pt on every guide channel cell.
- [ ] Focus ring = 3pt gold + glow + 1.045 on cards/rows; gold fill on chips/channel cells; ring visible on the darkest card from 3 m on a 1080p panel.
- [ ] Scores: My Games rail first; first card is the hero (560 wide, 96 digits, bleed); other cards 420×236 / 380×210 with LED 44 digits.
- [ ] Scores: WATCH appears only on matched games (compare with the phone on the same playlist — identical set); unmatched shows `NO STREAM MATCHED`.
- [ ] Scores: partial warning strip, error panel with focusable RETRY, empty panel with focusable CTA; no favorites → no My Games rail + `★ PICK TEAMS`.
- [ ] Guide: 88pt rows (tvOS), brand stripe + LED channel number, airing block gold with `LIVE`, now marker mint; `GUIDE n/m` count equals phone for the same category.
- [ ] Guide: category picker opens opaque full screen and returns focus to the channel cell.
- [ ] Settings: lamp states equal phone (`SetupChecklist` / `LampKind`); two-column hub; tvOS has no ALERTS section; Android TV has it.
- [ ] Shell: tvOS system tab bar gold; Android TV Jumbotron tab bar with lamp; no top app bar on Android TV.
- [ ] Player: full-screen only; no pop-out control anywhere; Back hides chrome then exits.

Speed (Instruments / Perfetto, release build, playlist ≥ 5 000 channels, XMLTV ≥ 100 MB):

- [ ] First Scores rail paints < 1.5 s from launch on a cache-hit launch; EPG download must not delay it (Clear EPG data, relaunch so the XMLTV download starts at boot → same number).
- [ ] No "guide file too large" for a 150 MB XMLTV on either platform; guide populates progressively during download (Android after streaming change).
- [ ] While the XMLTV load runs: D-pad moves focus across rails within one frame (≤ 16 ms hitch), no main-thread stall > 100 ms in Instruments' Hangs / Perfetto's main-thread track.
- [ ] Scores screen recomposition/body count is **0** during an EPG load (SwiftUI `Self._printChanges()` / Compose Layout Inspector recomposition counts).
- [ ] Player: while VLC decodes, EPG merges publish ≤ 1 per 2.5 s (log `flushEpgMerge`).
- [ ] Leave the TV app open 4 h: guide still shows the current programme (30-min poll + 3 h stale rule), `lastEpgReload` advances, and a 304 does not advance the build stamp.
- [ ] Playlist refresh set to Manual → relaunch does not hit `get_live_streams`.

## 12. Non-goals

- Do not rebuild matching, the player engines, or `ScoreboardGrouping`.
- Do not port the phone switchboard / Now-bar list / 80pt tab bar to TV.
- Do not split the remaining god objects (`GuideView.swift`, `ScoresView.swift`, `ScoresScreen.kt`, `AppViewModel.kt`) beyond what §7 requires for invalidation (`EpgUiState` on Android is required; nothing else is).
- Do not add new EPG windows, per-channel logo colors, or a TV-specific EPG pipeline.
- Do not change phone behaviour; every phone screenshot from 005 must be pixel-identical after this drop.
