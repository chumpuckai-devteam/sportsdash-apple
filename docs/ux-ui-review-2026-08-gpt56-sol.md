# SportsDash UX/UI Review — 2026-08-05 (gpt-5.6-sol)

## Executive summary

SportsDash has a strong, differentiated product core: it is recognizably a **Guide-first IPTV product with a sports dashboard**, not a cable clone and not a sports-news feed. The shipped A+D direction is visible on both platforms: favorite-team logos and My Games lead Scores, the player carries a top live-games ticker, and WATCH routes into IPTV matching. The void/gold/live-mint system is coherent and generally avoids reference-brand imitation.

The implementation is much closer to the intended product than the original sketches. In particular, iOS now has the preferred symmetric score rows, outside-corner favorite stars, a borderless void score list, full-bleed player video, opaque ticker pills, and a single horizontally scrolling control row. Android has the same three tabs, team picker, My Games pin, full-bleed libVLC player, favorite-first three-mode ticker, stream selection on ticker changes, and an honest full-guide loading state.

The most consequential remaining issues are not taste nits:

1. **Android landscape can strand the user on a tab.** `SportsDashRoot.kt` removes both top and bottom shell chrome in landscape, but Scores and Settings do not provide a replacement route. Guide alone exposes a route to Scores—and labels it “Guide.” Rotating into landscape can therefore turn a three-tab app into a one-screen island.
2. **iOS Guide can default to an empty Favorites category.** `GuideView.swift` prepends `★ Favorites` and then chooses `groupNames.first`, so a configured user with no starred channels can initially see “No channels in this category” instead of their provider’s first category.
3. **Android Scores visually under-communicates the product’s core WATCH action.** `ScoresScreen.kt` shows `TAP TO WATCH` only for upcoming games; live/final rows show status and score without the gold WATCH affordance used on iOS. A tap still opens `StreamPickerDialog`, but the interaction is not visible.
4. **Player accessibility is incomplete.** iOS `PlayerView.swift` gives most icon-only controls no explicit VoiceOver label, while the Android ticker, compact score chips, and custom clickable rows need stronger merged semantics and minimum-target verification.
5. **The platforms look related but not yet equal in density and row anatomy.** iOS is the cleaner A+C implementation: void list, 32-point scores, outside-corner stars, gold WATCH. Android still uses filled panel cards, inline stars, a combined center score string, and broadcast text below, which makes the product feel one redesign behind.
6. **Trust messaging is strongest on Android but too buried and too absolute in places.** Android correctly says install over rather than uninstall and explains that uninstall wipes data. This should become release/update messaging, not just text inside a long Settings page. iOS should use similarly explicit “saved / leave blank to keep” credential behavior rather than hydrating the stored password into an editor field.

The recommended two-week focus is a parity-and-trust sprint, not a net-new feature sprint: fix landscape escape routes, correct iOS Guide initial selection, make Android score rows express WATCH, close accessibility labels and target sizes, then align Settings hierarchy and player timing. Do not start Cast, multiview, push, Android TV, or a news surface.

## Method & sources

### Review method

This is a static implementation review of the current working tree at:

`/opt/data/workspace/sportsdash-apple`

Review time: **2026-08-05 02:08 UTC**. Repository HEAD was `fcc234e` (`fix(ios): add tickerButtonFill computed property to PlayerView`). The working tree contained uncommitted Android/docs changes, so findings describe the files actually read, not only the committed HEAD. No code was changed except this report.

The review compared:

- the earlier sample-derived patterns;
- the A+D product decision and later dogfood law;
- actual SwiftUI and Compose hierarchy, controls, labels, empty/loading states, and navigation;
- cross-platform behavior that is user-visible or trust-sensitive;
- official Apple and Android interface/accessibility guidance.

This is not a visual screenshot audit on physical devices. Items involving clipping, contrast in motion, TalkBack traversal, VoiceOver announcements, and landscape safe areas must still be dogfooded on an iPhone and an Android phone.

### Canonical inspiration and product-law files read

- `/opt/data/skills/software-development/sportsdash-continue-shipping/SKILL.md`
- `/opt/data/skills/software-development/sportsdash-continue-shipping/references/ui-inspiration-samples.md`
- `/opt/data/skills/software-development/sportsdash-continue-shipping/references/ios-android-parity-ad.md`
- `/opt/data/skills/software-development/sportsdash-continue-shipping/references/ui-liquid-glass.md`
- `/opt/data/skills/software-development/sportsdash-continue-shipping/references/scores-dashboard-chrome.md`
- `/opt/data/skills/software-development/sportsdash-continue-shipping/references/android-player-ticker.md`
- `/opt/data/workspace/sportsdash-apple/docs/dual-platform-parity.md`
- `/opt/data/workspace/sportsdash-apple/docs/ui-liquid-glass.md`
- `/opt/data/workspace/sportsdash-apple/docs/android-login-persist.md`

### Interactive sketches read

- `/opt/data/workspace/sportsdash-apple/sketches/index.html`
- `/opt/data/workspace/sportsdash-apple/sketches/001-my-games-first/index.html`
- `/opt/data/workspace/sportsdash-apple/sketches/002-dense-board/index.html`
- `/opt/data/workspace/sportsdash-apple/sketches/003-symmetric-watch/index.html`
- `/opt/data/workspace/sportsdash-apple/sketches/004-player-ticker-top/index.html`

### iOS implementation files read

- `SportsDash/App/RootTabView.swift`
- `SportsDash/Theme/SportsColors.swift`
- `SportsDash/Features/Scores/ScoresView.swift`
- `SportsDash/Features/Scores/GameMatchupRow.swift`
- `SportsDash/Features/Scores/FavoriteTeamPickerView.swift`
- `SportsDash/Features/Player/PlayerView.swift`
- `SportsDash/Features/Player/LiveScoresStrip.swift`
- `SportsDash/Features/Guide/GuideView.swift`
- `SportsDash/Features/Settings/SettingsView.swift`
- `SportsDash/Features/Settings/PlaylistSettingsView.swift`
- `SportsDash/Features/Settings/PlayerSettingsView.swift`
- supporting favorite/matching paths in `SportsDash/App/AppModel.swift`

### Android implementation files read

- `android/app/src/main/java/com/samirpatel/sportsdash/ui/SportsDashRoot.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/ScoresScreen.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/PlayerScreen.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/GuideScreen.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/GuideTimeline.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/SettingsScreen.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/ui/theme/Theme.kt`
- `android/app/src/main/java/com/samirpatel/sportsdash/core/player/ScoresTickerMode.kt`
- supporting favorite/ticker/stream-picker paths in `android/app/src/main/java/com/samirpatel/sportsdash/AppViewModel.kt`

### Canonical platform references

- Apple HIG, Buttons: https://developer.apple.com/design/human-interface-guidelines/buttons
- Apple HIG, Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- Apple HIG, Playing video: https://developer.apple.com/design/human-interface-guidelines/playing-video
- Apple HIG, Going full screen: https://developer.apple.com/design/human-interface-guidelines/going-full-screen
- SwiftUI accessible descriptions: https://developer.apple.com/documentation/swiftui/accessible-descriptions
- Android Compose accessibility: https://developer.android.com/develop/ui/compose/accessibility
- Android Compose API defaults / minimum targets: https://developer.android.com/develop/ui/compose/accessibility/api-defaults
- Android Compose semantics: https://developer.android.com/develop/ui/compose/accessibility/semantics
- Android edge-to-edge and insets: https://developer.android.com/develop/ui/compose/system/insets
- Android navigation bar: https://developer.android.com/develop/ui/compose/components/navigation-bar

Apple recommends at least a 44×44-point hit region for buttons. Android’s Compose guidance uses 48dp minimum interactive targets and meaningful semantics for TalkBack. Those targets are used below as verification criteria, not as requests to enlarge the visible chrome itself.

## What works (aligned with A+D + brand)

### Product identity and information architecture

- Both shells implement **Scores · Guide · Settings only**. `RootTabView.swift` and `SportsDashRoot.kt` correctly avoid a redundant Channels tab.
- Scores is not a passive sports feed. Tapping a game enters IPTV matching: iOS goes through `GameDetailSheet`/stream selection, and Android calls `vm.openStreamPicker()` into `StreamPickerDialog`.
- Guide remains the only browse-and-play surface. Both platforms offer timeline and grid/list representations without creating a cable-style channel silo.
- The app does not drift into sports news, editorial cards, league-pass upsell, or favorite-game concepts.

### A+D direction

- **A / My Games:** `ScoresView.swift` and `ScoresScreen.kt` both render a logo rail and a My Games block before broader sport/league sections.
- **A / favorites:** both platforms persist team metadata, show logos when available, and provide the required **Sport → League → Team** flow (`FavoriteTeamPickerView.swift`, `FavoriteTeamPickerDialog` in `ScoresScreen.kt`).
- **B retained selectively:** both platforms keep collapsible sport hierarchy; iOS also preserves empty Upcoming league shelves instead of silently dropping quiet leagues.
- **C used selectively:** iOS `GameMatchupRow.swift` uses the strongest symmetric matchup anatomy—team marks outside, large scores, center action/status—without copying NBA art or branding.
- **D / player ticker:** both players put a horizontally scrolling live-game ticker at the top of full-bleed video.

### Brand and hierarchy

- The token systems are coherent: `SportsColors.swift` and Android `Theme.kt` consistently define void, gold, live mint, muted text, and elevated dark surfaces.
- Gold generally communicates **action/selection**; mint communicates **live/current state**. This is the right semantic split.
- iOS uses Liquid Glass only on floating control/navigation surfaces. `SportsColors.swift` correctly gates `glassEffect` by compiler and OS while keeping content cards opaque or material-backed.
- iOS Scores correctly removed the gray game-list plate: `ScoresView.swift` and `GameMatchupRow.swift` explicitly use clear backgrounds for iPhone rows and league groups.
- There are no reference trademarks, team-color hero washes, or one-for-one ESPN/CBS/NFL/NBA clones.

### Scores

- `ScoresView.swift` keeps Live/Upcoming/All and the favorite rail in one short row.
- `ScoresScreen.kt` also uses a single row, despite an obsolete comment at lines 117–118 claiming a stacked layout.
- iOS favorite stars are in the requested outside corners in `GameMatchupRow.swift`: away top-leading, home top-trailing.
- iOS uses short team labels under the mark, preserving score legibility on narrow screens.
- iOS Upcoming keeps selected-league shelves visible with “None scheduled,” which improves trust compared with a disappearing league.
- Both implementations use exact team IDs for favorite state (`AppModel.isTeamFavorite`, `AppViewModel.isTeamFavorite`) rather than city or abbreviation matching. That avoids Tampa Bay-style city collisions.

### Player

- Both players are actually full-bleed. Video is the base layer; ticker and chrome overlay it.
- Both maintain an always-present Back control while Close appears with chrome.
- Android shows system bars and handles system Back in `PlayerScreen.kt`.
- Ticker visibility is the required three-state model on both platforms: Off → Fade → Pin, persisted behind one sports button.
- Ticker sorting is favorite-first and passes favorite IDs into both ticker implementations.
- Ticker taps open a stream picker rather than silently autoplaying the first channel.
- Ticker rows remain transparent while individual pills are opaque panel/gold, preserving video and score readability.
- Android uses explicit z-order and click layers; the implementation reflects the hard-won VLC hit-testing law.
- iOS uses one horizontal strip of circular controls under multi-line programme information, matching the post-dogfood direction.

### Guide and loading honesty

- Both platforms implement an actual hour timeline, not just a channel list.
- Both default the timeline window to the current hour and fill gaps rather than leaving black holes.
- iOS deduplicates channel clones by cleaned name and keeps the richer EPG record.
- Android preserves provider category order.
- Android shows `EpgLoadingCard` when a category has zero coverage during a full download, which is substantially more honest than a silent spinner.
- iOS publishes explicit guide coverage (`Guide X/Y in this category`) and displays “No guide” only as muted gap content, not as a fabricated programme.
- Both support separate channel favorites in Guide, preserving the distinction from team favorites in Scores.

### Settings and trust

- iOS has a clear Settings hub with Setup, Playlists, App, and About sections.
- Android hydrates saved host/username asynchronously, leaves the password field blank, and explicitly says blank keeps the saved password.
- Android correctly explains **install over = retained data; uninstall = wiped data**.
- Both disclose VLC/libVLC and LGPL use, and both avoid real provider credentials in examples.

## Critical issues (P0)

| Priority | Finding | Evidence | User harm | Recommendation | Effort / platform |
|---|---|---|---|---|---|
| P0 | Landscape tab trap | `SportsDashRoot.kt` hides top and bottom bars whenever `landscape`; `ScoresScreen.kt` and `SettingsScreen.kt` have no replacement tab route. Guide has only a route to Scores. | Rotation can strand users in Scores or Settings; Android Back may exit instead of returning to another app surface. | Keep shell chrome visually compact in landscape but preserve navigation: use a small three-destination rail/overlay, or an explicit Back-to-previous-tab model. Test all 3 tabs in both orientations. Do not add TV chrome. | M · Android |
| P0 | iOS Guide initially selects empty Favorites | `GuideView.swift` builds `[★ Favorites] + provider groups` and sets `selectedGroup = groupNames.first`. | First useful Guide visit can show an empty category even though channels are loaded, making setup appear broken. | Initial selection should be Favorites only when it contains channels or was explicitly last-selected. Otherwise choose the persisted last provider category, then first provider category. | S · iOS |
| P0 | Core WATCH action is visually missing from live/final Android score rows | `GameRow` in `ScoresScreen.kt` uses score text for live/final and `TAP TO WATCH` only for upcoming. Tapping all rows still opens the picker. | Users cannot see that live games are watchable—the product’s main differentiator becomes a hidden gesture. | Use a compact gold **WATCH** capsule in the center for every watchable row, with status below; scores should remain large on the sides, not merged into one center string. | M · Android |
| P0 | iOS player icon controls lack explicit VoiceOver names | `chromeIconButton` in `PlayerView.swift` adds button traits but accepts only an SF Symbol name, not a user-facing accessibility label. Most controls therefore lack deliberate labels. | VoiceOver users can encounter ambiguous symbol-derived names for Back, Close, play/pause, rejoin, pop-out, mute, aspect, streams, subtitles, and options. | Change helper signature to require `accessibilityLabel` and optional hint. Announce current toggle state for play, mute, and ticker. Verify rotor order on video. | M · iOS |
| P0 | Compact custom controls are below platform target guidance | iOS favorite logos are 26pt with 30pt Add; Android score chips use visible text padding around ~21–27dp height and rail cells are 34dp. | Missed taps, especially one-handed, on small screens or for motor accessibility. | Preserve visible density but wrap each control in an invisible minimum 44pt/48dp hit region. Verify no overlap and test with accessibility inspector. | M · both |
| P0 | Incorrect Android landscape navigation label | `GuideActionBar` calls `onGoScores` but uses a Live TV icon with `contentDescription = "Guide"`. | TalkBack announces the opposite destination; sighted users also receive an unclear affordance. | Label the destination “Scores” and use a sports/score icon if this control remains after the broader landscape fix. | S · Android |

### P0 acceptance outcomes

- From any Android tab in portrait or landscape, a user can reach the other two tabs in at most one deliberate navigation action; system Back never unexpectedly closes the app from an orientation-induced dead end.
- An iOS user with a loaded playlist and zero channel favorites sees a populated provider category on first Guide entry.
- Every watchable Android game exposes a visible gold WATCH affordance and opens the picker on tap.
- Every player control has a stable, state-aware VoiceOver/TalkBack name.
- Automated and manual accessibility checks report no interactive target smaller than 44pt on iOS or 48dp on Android, while visible chrome remains dense.

## High-priority improvements (P1)

| Priority | Finding | Recommendation | Measurable outcome | Effort / platform |
|---|---|---|---|---|
| P1 | Android score rows are visually one generation behind iOS | Align anatomy with `GameMatchupRow.swift`: logo + short label, large side score, center WATCH + status, and outside-corner stars. Reduce solid card mass; use void rows with subtle separators or a very light favorite tint. | Side-by-side screenshots show the same scan order and no full-width gray board dominance. | M · Android |
| P1 | Android sport headers reintroduce gray panels | `SportSectionHeader` uses `Panel.copy(alpha=.72)` even though phone-dashboard law favors borderless void. Move hierarchy into typography, spacing, count, and chevron rather than a filled slab. | At least one more matchup row fits above the fold on a typical phone without reducing row tap target. | S · Android |
| P1 | Android favorite stars are inline and duplicated by favorite row tint | Move stars outside logo corners, as on iOS, and keep the row tint subtle or remove it. | Favorite side is identifiable without changing team-label width or shifting score alignment. | M · Android |
| P1 | Filter vocabulary is not at parity | `DashboardFilter.label` in iOS is **LIVE / UPCOMING / ALL** while Android is **Live / Upcoming / Final**. The current dense-chrome product law calls for Final. Align code and `docs/dual-platform-parity.md` so the third filter has one meaning and label. | Test plans and screenshots no longer disagree about Final vs All. | S · iOS/docs |
| P1 | iOS auto-fade timing differs from Android/product law | iOS waits 6.0s in `PlayerView.swift`; Android uses 4.5s. Standardize at approximately 4.5s unless device dogfood proves iOS needs longer. Reset after any control interaction. | Same Fade-mode expectation on both platforms; ticker disappears with chrome at the same perceived cadence. | S · iOS |
| P1 | iOS hides status/system overlays in player while Android explicitly shows system bars | `PlayerView.swift` uses `.statusBarHidden(true)` and `.persistentSystemOverlays(.hidden)`. This conflicts with the current cross-platform “show system bars / preserve system navigation” product law, though Apple permits full-screen video. | Decide one explicit iOS policy: show status/system chrome, or document why iOS is intentionally immersive while preserving a guaranteed 44pt Back. Test Home indicator and gesture areas. | S–M · iOS/product decision |
| P1 | Player text can become unreadable over bright video | Both players intentionally avoid a full-width ticker scrim, which is correct, but programme text at the bottom has no localized backing. Use a narrow text-only gradient or shadow behind the programme block—not behind the ticker row or whole video. | White text remains readable over a bright test clip while video remains visibly full-bleed. | S · both |
| P1 | Android lacks an in-player current-channel stream/alternate picker | Android can change streams from a ticker game, but the bottom utility cluster lacks the iOS list/alternate-stream action. | Add a compact Streams control only if alternate matches exist; opens a picker and never silently switches. | M · Android |
| P1 | Android Guide category sheet violates its own “categories only” rule | `GuideCategoryMenuSheet` includes “Reload guide.” Keep reload in the root app-bar refresh or Guide status surface; the sheet should select categories and close. | One action has one home; no duplicate refresh paths in the category chooser. | S · Android |
| P1 | Android category chooser is fixed to 380dp and has no fast traversal | Keep the no-search product choice, but add section/letter jump, recent categories, or a taller adaptive sheet if real providers have 100–200 groups. Do not alphabetize provider order. | Returning to a previously used category takes materially fewer swipes while provider order remains intact. | M · Android |
| P1 | iOS configured-but-loading Guide is conflated with no playlist | `GuideView.swift` checks only `appModel.channels.isEmpty` and says “Load a playlist first.” Distinguish no config, loading cached/network channels, and genuine load failure. | No valid configured account is told to configure again during bootstrap. | M · iOS |
| P1 | Settings parity is structurally weak | Android is one long form; iOS is a navigable hub. Give Android grouped destinations/sections: Playlist, Guide/EPG, Scores & leagues, Display, Ratings, About. Keep phone-first Material navigation. | Users can reach any setting category without scrolling through credentials and every league. | L · Android |
| P1 | Android Settings shows a refresh button that does nothing | `SportsDashRoot.kt` always renders the top refresh icon in portrait, but the tab switch has no action for Settings. Hide it on Settings or change it to a relevant action. | No visible enabled control is a no-op. | S · Android |
| P1 | Update-retention trust copy is buried | Keep the accurate Android text, but show install-over guidance with dogfood release notes / first launch after version change. Avoid repeatedly alarming normal users in the primary credential form. | Testers can state “update over; uninstall wipes data” before installing an APK. | M · Android/release UX |
| P1 | iOS credential editor hydrates the saved password | `PlaylistEditorSheet.hydrate()` assigns `existing.xtreamPassword` into the `SecureField`. Match Android’s safer trust pattern: blank field, explicit “saved · leave blank to keep,” and preserve existing password on blank save. | Editing a playlist name or host cannot accidentally expose or clear a saved password. | M · iOS |
| P1 | Ticker pills need complete spoken content | The compact tickers visually show abbreviations and scores, but their buttons lack explicit game/status/action labels. | VoiceOver/TalkBack announces “Twins 3, Mariners 2, bottom seventh; opens stream choices,” not a concatenated visual string. | M · both |
| P1 | TalkBack semantics for custom clickable score/game rows are incomplete | `ScoresScreen.kt`, `GuideTimeline.kt`, and custom chips lean on raw `clickable`/`combinedClickable` and nested text. Add merged semantics, role, selected state, long-click description, and deterministic traversal. | TalkBack reads each game or channel as one actionable unit with favorite and watch state. | M · Android |

## Polish / later (P2)

| Priority | Improvement | Why it is later | Effort / platform |
|---|---|---|---|
| P2 | Add restrained filter/count micro-motion | Current state changes work; motion should wait until navigation, targets, and parity are stable. Use short state transitions and respect Reduce Motion. | S · both |
| P2 | Animate sport collapse with matching motion curves | iOS animates; Android snaps. Align after density is finalized. | S · Android |
| P2 | Improve “No other live games” ticker behavior | When no live games exist, consider collapsing ticker space entirely in Fade/Pin while keeping Back. Avoid a persistent empty pill message over video. | S · both |
| P2 | Persist collapsed sport sections | Current collapse state is session/rotation-local. Persistence is optional and should not make quiet leagues disappear unexpectedly. | S · both |
| P2 | Add content descriptions for team/channel logos only where informative | Avoid duplicate announcements when the parent row already names the team/channel. Decorative marks should remain hidden/null. | S · both |
| P2 | Add current-time line and periodic refresh consistency | Android computes the now line from current time but should verify minute-level recomposition; iOS already updates at 60 seconds. | S · Android |
| P2 | Refine Android color-token parity | Android’s `VoidBlack`/`Panel` are warmer and flatter than iOS’s blue-black/elevated pair. Align perceived brand while respecting platform rendering, not exact RGB cloning. | S · Android/design |
| P2 | Clarify iOS About wording | “Native SwiftUI · iOS & Apple TV” is correct for Apple, but parity freeze and Android existence could be acknowledged in product-level About copy if desired. | S · iOS/product |
| P2 | Device-specific landscape optimization | After the escape-route fix, tune ticker pill count, centre transport spacing, and programme-line limits on small phones and camera-cutout devices. | M · both |
| P2 | Add screenshot regression baselines | Capture Scores, Guide timeline, player chrome visible/hidden, and Settings at compact phone sizes and landscape. | M · both/QA |

## Screen-by-screen

### Scores

#### Information architecture

The high-level order is right: filter/favorites chrome → setup state if needed → My Games → full sport/league board. That directly reflects ESPN’s “My Games first” structure without importing ESPN’s visual identity.

On iOS, `ScoresView.swift` has particularly good hierarchy:

- one-row filter + logo rail;
- My Games only when relevant;
- strong collapsible sport header;
- quiet uppercase league label;
- selected quiet leagues remain represented under Upcoming;
- void rows keep the eye on teams and scores rather than containers.

Android’s structure is equivalent, but visual grouping is heavier. `SportSectionHeader` and `GameRow` both paint broad `Panel` surfaces. The result is more “stack of dark cards” and less “live scoreboard on void.” The fix is not to remove hierarchy; it is to make typography, spacing, counts, and separators do more work.

The top chrome on both platforms is appropriately dense. However, the visible compactness must not shrink the actual hit region. The correct implementation is a 44pt/48dp invisible interaction box around a 26–30pt visible logo, not a larger visible rail.

#### Row anatomy and WATCH

`GameMatchupRow.swift` is the strongest shipped component in the product:

- 44pt team marks;
- short names beneath the marks;
- 32pt monospaced scores;
- losing side dimmed;
- gold WATCH centered above a two-line status;
- team stars outside the logo corners.

This is a successful A+C synthesis. It steals matchup symmetry and status placement without copying NBA branding.

Android `GameRow` does not yet match that scan path:

- scores are combined in the center (`away - home`) instead of sitting near their teams;
- WATCH is absent for live/final rows;
- stars are inline with labels;
- broadcast names add a full line beneath the card;
- every row has a rounded panel.

Recommendation: port the **anatomy**, not SwiftUI styling. Place each score adjacent to its team, use a gold WATCH button as the central action for all watchable states, place status below, and move broadcast/match details to the picker or detail surface. A live row should answer, in one glance: who, score, game state, and can I watch?

#### Favorites

Both apps correctly treat favorites as teams. Exact team IDs are used for pinning, row state, and ticker sorting. This is the correct defense against loose city/abbreviation matching such as Tampa Bay teams.

The Sport → League → Team picker is clear and progressive on both platforms. Improvements:

- add explicit retry when team loading fails;
- preserve the chosen sport/league if a transient fetch fails;
- expose selected count in the picker title or Done action;
- make the rail tap semantics explicit: currently tapping any existing logo opens the editor rather than filtering to that team. That is acceptable, but should be announced as “Edit favorite teams,” not only the team name.

On iOS, `favoriteTeamsRail` labels an existing-logo button only with `team.name`, even though the action opens the picker. VoiceOver could reasonably infer it filters the board. Use “Edit favorite teams; [team] is selected” or change tap behavior to focus the team. Do not leave action and label mismatched.

#### Empty and error states

The iOS states are specific and generally constructive. Upcoming explains the date window and suggests league settings. Android states are shorter and sometimes over-index on long press (“Long-press a game to ★ a team”) even though the primary favorite flow is the + picker. The empty state should lead with “Add a favorite team” via the picker, and mention long press as a shortcut.

### Player

#### Full-bleed and chrome budget

Both implementations respect the rejected-band lesson: no black ticker band reserves height above video. Back, ticker, and Close occupy one overlay row. This is the right D evolution.

The ticker pills are well constrained: current game gold; other games opaque panel; strip itself clear. Both also rank favorite games first and reset ticker scroll after a switch.

Chrome timing is inconsistent: Android uses 4.5 seconds, iOS 6 seconds. Fade mode therefore behaves differently even though the labels and state model are identical. Standardize unless dogfood shows a platform-specific need.

#### Control layout

The iOS bottom control row is coherent and scalable. It horizontally scrolls one family of 44pt circles under programme information. It includes play/pause, rejoin, pop-out, mute, aspect, ticker mode, streams, AirPlay, captions, more, and an engine chip.

Android uses a center play/rejoin pair plus a right-side vertical stack for pop-out/ticker/mute. This is usable in landscape but less complete:

- there is no current-game/channel Streams control;
- utility discovery depends on chrome being visible;
- portrait has a tall right stack competing with programme information;
- the pattern differs materially from iOS.

A platform-native compromise is preferable to pixel parity: keep centre transport, but place utilities in one bottom horizontal row or compact overflow. Ensure the stream chooser is available when alternatives exist.

#### Exit and platform behavior

Android is strong here: explicit always-on Back, optional Close, `BackHandler`, visible system bars, insets, and solid dark system appearance.

iOS always renders its custom Back, but also hides the status bar and persistent system overlays. Apple allows immersive full-screen video, so this is not automatically wrong, but it conflicts with the current SportsDash “show system bars” law and creates a parity decision that is undocumented. Choose and document one policy; do not accidentally inherit immersive behavior.

#### Readability and accessibility

The no-scrim ticker row should remain. Bottom programme text, however, needs a local readability treatment over bright footage: text shadow or a narrow gradient behind only the information block. Do not add a full-width opaque band.

The iOS helper must require labels. Android’s `CircleControl` does better by requiring `contentDescription`, but ticker pills still need complete game/status/action semantics. Both should announce mode changes, e.g. “Scores ticker, pinned” after cycling.

### Guide

#### Timeline and hierarchy

The Guide implementation has moved beyond an IPTV channel list into a credible guide:

- current-hour left edge;
- 12-hour scrollable window;
- fixed channel column;
- continuous muted gap fillers;
- provider categories;
- channel favorites;
- Hour and Grid representations;
- movie-now filtering and ratings.

That aligns well with IPTVx structure while preserving SportsDash branding.

The largest iOS IA defect is selecting Favorites by default even when empty. Favorites should be a deliberate shelf, not an empty landing page. Persist last category, with a populated provider category as fallback.

Android’s main action bar is dense but understandable: ★, Hour, Grid, Movies, category name, menu. The category chooser keeps provider order and scrolls to the current item. The embedded Reload action is inconsistent with the stated “categories only” contract and should leave the sheet.

#### EPG honesty

Android’s `EpgLoadingCard` is excellent product behavior. It explains that a full guide is being loaded when coverage is zero. The inline status also exposes download/EPG state.

iOS distinguishes loading and coverage, but its top-level empty state does not distinguish unconfigured from configured-but-loading. A returning user should see “Loading saved playlist…” or a cached/refresh state, not “Load a playlist first.”

Both gap-fill implementations avoid invented programme names. That is the right trust choice.

#### Timeline interaction

Android adds Earlier/Now/Later controls above the timeline. They are discoverable but add vertical chrome. Once device tested, consider moving them into a compact time header if they materially reduce visible channels.

iOS links every timeline row’s horizontal position with the header, which provides a true TV-grid feel. Verify on device that interacting with one row does not cause jitter as lazy rows recycle.

Channel favorite behavior is long-press/context-menu based on both platforms. This preserves row tap for immediate play, but first-use education is necessary. The empty Favorites state already explains long press on Android; iOS should provide equivalent hinting when Favorites is empty.

### Settings

#### iOS

The iOS hub is well organized and brand-consistent. Setup, Playlists, App, and About provide progressively deeper navigation instead of one giant form. Account status, expiration, connections, EPG state, playback engine, and LGPL attribution are visible.

The main trust issue is the editor’s password behavior. `PlaylistEditorSheet.hydrate()` loads the stored password into `@State` and displays it as a filled SecureField. Android’s blank-but-saved pattern is clearer and safer: display “Password saved · leave blank to keep,” retain the stored value on blank edit, and never rehydrate it into the field.

The About text is technically rich but dense. Consider moving long license detail into a dedicated About/Licenses destination while keeping “VLC hard engine + AVPlayer for HLS” visible.

#### Android

Android Settings contains the right content but has weak information architecture. Credentials, update instructions, EPG, movie keys, display, every score league, and About all live in one `LazyColumn`. This is functional for dogfood but hard to scan and costly to revisit.

The update copy is accurate and valuable:

- install over the existing app;
- do not uninstall first;
- same package/signature preserves app-private data;
- uninstall clears it.

However, it should also be delivered with each tester build or once after an app version change. Users rarely open Settings before installing an update.

The root refresh icon is a no-op on Settings. Remove it on that tab. No visible enabled action should silently do nothing.

### Cross-platform parity

#### Parity that is genuinely achieved

- three-tab IA;
- VLC/libVLC hard player;
- Live/Upcoming plus a third completed-slate filter (Android **Final**, iOS currently **All**);
- favorite-team logo rail;
- My Games pin;
- Sport → League → Team picker;
- team metadata persistence;
- timeline + grid Guide;
- channel favorites;
- Movies Now and ratings;
- full-bleed player;
- three-mode ticker;
- favorite-first ticker ordering;
- ticker tap → stream picker;
- always-on Back;
- pop-out mini player;
- void/gold/mint brand.

#### User-harmful parity gaps

1. **Android orientation navigation:** no equivalent problem on iOS.
2. **Android WATCH discoverability:** iOS exposes gold WATCH on all matchup rows; Android hides it for live/final.
3. **Score-row anatomy:** iOS is symmetric and borderless; Android is panel-heavy and centre-score-heavy.
4. **Favorite-star placement:** iOS outside corners; Android inline.
5. **Settings structure:** iOS hub vs Android long form.
6. **Player control completeness:** iOS has Streams/AirPlay/captions/more; Android has the smaller core set and no explicit current-stream chooser.
7. **Auto-fade timing:** 6.0s iOS vs 4.5s Android.
8. **System UI policy:** Android explicitly shows bars; iOS hides them.
9. **Credential editing:** Android blank-keeps; iOS hydrates the password.
10. **Accessibility completeness:** Android circle controls have explicit descriptions; iOS player helper does not. Both need ticker/row semantics and target-size verification.

Intentional differences should remain intentional:

- iOS can keep Liquid Glass on eligible control chrome; Android should use Material rather than fake Apple glass.
- iOS can expose AirPlay while Android Cast remains blocked.
- Android remains phone-first; do not add a fake TV shell.
- iOS Auto can route clean HLS to AVPlayer while Android remains VLC-only during the parity freeze.

## Inspiration gap analysis (samples vs shipped)

| Inspiration source | Extracted structural cue | Shipped state | Gap / recommendation |
|---|---|---|---|
| ESPN | Favorite-logo rail | Shipped both | Keep compact. Make tap action semantics clear; no ESPN red or wordmarks. |
| ESPN | My Games first | Shipped both | Strong. Empty-state CTA should favor the picker over teaching long press first. |
| ESPN | Dense rows + Watch pill | Strong on iOS; partial Android | Android needs visible gold WATCH on live/final and less panel mass. |
| CBS | Date strip | Not selected | Correct omission for now; the compact status filters are simpler. First align iOS **All** with Android/product-law **Final**; do not add a date strip unless users need day-level planning. |
| CBS | Collapsible leagues/sports | Shipped both | Keep. Android collapse motion can be polished later. |
| CBS | Two-up dense board | Not selected | Correct; it weakens logos and tap targets on small phones. |
| Bleacher Report | Following logo grid / edit | Rail + picker shipped | Progressive picker is more precise for SportsDash. Add selected-count feedback, not social-feed affordances. |
| NBA | Symmetric matchup | Strong on iOS, partial Android | Port the anatomy to Android without copying NBA typography or art. |
| NBA | Stream line under game | Replaced by WATCH → picker | Correct product adaptation. Avoid broadcast clutter under every Android row. |
| NFL | Top multi-game ticker | Shipped both | Strong. Add spoken status/action labels and empty-strip behavior. |
| NFL | Selected ticker context | Current pill gold both | Strong; favorite-first ordering is a SportsDash improvement over pure current-first. |
| Smarters/IPTVx/Chillio | Fullscreen chrome | Shipped both | Strong full-bleed direction; programme text readability needs localized treatment. |
| Smarters/IPTVx/Chillio | Mini-player + Guide continuity | Pop-out shipped both | Verify mini-player does not cover bottom controls/nav on smallest phones. |
| IPTVx | Hour Guide | Shipped both | Strong; iOS initial Favorites category is the main IA regression. |
| IPTV players | Options / stream switch | Stronger iOS; partial Android | Add current-stream/alternate picker on Android if alternatives exist. |

The product should not move toward a pure CBS grid, a news feed, a cable-clone channel tab, branded broadcast art, or team-color hero gradients. The best next design work is **convergence and legibility**, not another reference-derived layout.

## Recommended next 2-week design/engineering plan

### Week 1 — unblock navigation, watchability, and trust

#### Day 1–2: Android landscape navigation (P0, M)

Owner: mobile-engineer + QA

- Define a compact, phone-native landscape navigation affordance for Scores, Guide, Settings.
- Keep top/bottom bars hidden if needed for content height, but preserve all three destinations.
- Correct the Guide-to-Scores content description.
- Test portrait → landscape → portrait from every tab and from floating/fullscreen playback.

Acceptance:

- zero tab dead ends;
- Android Back behavior is predictable;
- no thin inset hairline returns;
- system bars remain visible in player.

#### Day 2: iOS Guide initial-category fix (P0, S)

Owner: mobile-engineer

- Persist or reuse last valid category.
- Choose Favorites only when non-empty or explicitly selected.
- Otherwise choose first provider category.
- Separate unconfigured, loading, failed, and empty-category states.

Acceptance:

- loaded playlist + zero favorites opens populated Guide;
- Favorites remains available and shows an instructional empty state when deliberately selected.

#### Day 3–4: Android score-row parity (P0/P1, M)

Owner: mobile-engineer with product-design review

- Implement side scores and center gold WATCH/status.
- Move favorite stars outside logo corners.
- Reduce panel/header fill while retaining hierarchy.
- Preserve exact-ID favorites, My Games pin, and long-press shortcut.

Acceptance:

- WATCH visible on every watchable game;
- tap opens stream picker;
- row remains at least 48dp interactive;
- screenshot scan order matches iOS without cloning it pixel-for-pixel.

#### Day 5: Credential/update trust (P1, M)

Owner: mobile-engineer + security review

- iOS: blank-but-saved password editing and blank-keeps semantics.
- Android: move install-over guidance into tester release copy / one-time version-change notice.
- Hide no-op Settings refresh.

Acceptance:

- editing non-password fields never clears or reveals stored password;
- update instructions are visible before testers uninstall;
- no enabled no-op control remains.

### Week 2 — accessibility, player convergence, and QA

#### Day 6–7: Accessibility pass (P0/P1, M)

Owner: QA + mobile-engineer

- Require explicit labels/hints for every iOS player icon control.
- Merge Android row semantics; set role, selected/favorite state, and long-click action description.
- Add full spoken labels to ticker pills.
- Enforce invisible 44pt/48dp target wrappers for top filters and favorite logos.
- Verify dynamic type / font scaling at the largest practical size without losing WATCH.

Acceptance:

- complete VoiceOver and TalkBack scripts can navigate Scores → stream picker → Player → Back;
- no ambiguous “button” or raw-symbol announcements;
- no overlapping touch targets.

#### Day 8: Player policy and parity (P1, M)

Owner: product + mobile-engineer

- Decide/document iOS system-overlay policy.
- Align auto-fade timing around 4.5 seconds.
- Add localized programme-text readability treatment.
- Add Android Streams control only when alternatives exist.

Acceptance:

- Fade and Pin behavior match mode names;
- Back always works with chrome hidden;
- bright-video test retains readable programme title;
- stream switch always opens a chooser.

#### Day 9: Settings/Guide cleanup (P1, M–L slice)

Owner: mobile-engineer

- Remove Reload from Android category sheet.
- Make category sheet height adaptive while retaining provider order and no-search law.
- Start Android Settings grouping; at minimum add clear section headers and collapsible/navigable league settings.

Acceptance:

- category sheet performs category selection only;
- Settings destinations are scannable without traversing the credential form.

#### Day 10: parity release gate

Owner: QA

Test matrix:

- iPhone compact portrait + landscape player;
- Android small phone portrait + landscape on all three tabs;
- VoiceOver and TalkBack;
- no playlist / loading / bad credentials / cached warm start;
- zero favorite teams / several favorite teams;
- zero favorite channels / populated Favorites;
- Live / Upcoming / third-filter parity (target Final), including a quiet selected league;
- player Off / Fade / Pin with chrome visible and hidden;
- ticker switch with zero, one, and multiple matched streams;
- install-over Android build with retained host/user and blank saved password;
- uninstall control path clearly documented as destructive.

Release gate metrics:

- 0 navigation dead ends;
- 0 no-op enabled controls;
- 100% icon-only player controls explicitly labeled;
- 100% watchable score rows visibly expose WATCH;
- 0 touch targets below platform minimums;
- both apps complete the same core journey: favorite team → My Games → WATCH → choose stream → full-screen player → ticker switch → Back.

## Open questions for Samir

1. On iOS full-screen player, should SportsDash explicitly **show** status/system overlays for parity, or keep Apple-style immersive video while guaranteeing the custom Back control? The current implementation hides them; Android shows them.
2. When a user taps a favorite logo in the Scores rail, should it open the favorite editor (current behavior) or temporarily focus/filter the board to that team? The label and action need to agree either way.
3. Should Android score rows move all broadcast names into the stream picker/detail surface, leaving only WATCH + status on the dashboard?
4. For Android landscape, which compact navigation is preferred: a small side rail, a top destination switcher, or Back-to-previous-tab plus a menu? The current no-shell approach creates dead ends.
5. Should the last selected Guide category persist across launches, with provider-first fallback when Favorites is empty? This review recommends yes.
6. Is iOS’s 6-second player fade deliberate, or should both platforms use the shipped Android/product-law timing of about 4.5 seconds?
7. For large Android provider category lists, should the no-search rule remain strict, with recent/letter-jump navigation, or can category search be reopened later? Provider order should remain authoritative either way.
8. Should login-retention guidance remain dogfood-only copy, or become a one-time in-app notice after Android version upgrades?
9. Is Android Settings ready to become a navigable hub matching iOS, or should the first parity slice only group/collapse the existing long form?
10. After the P0/P1 parity pass, which physical devices define the small-screen release gate? A compact iPhone and Samir’s Samsung should be the minimum pair.
