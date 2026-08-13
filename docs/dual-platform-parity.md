# Dual-platform parity matrix

Updated 2026-08-12. SportsDash ships from one monorepo. Parity means the same core product journey; intentional platform capabilities are stated rather than hidden.

## Shared baseline

| Area | Shared behavior |
|---|---|
| Navigation | Scores · Guide · Settings |
| Hard engine | VLC/libVLC, TS-first |
| Scores | ESPN Live / Upcoming / Final; favorite teams pin first using league-scoped IDs |
| Watch from Scores | Select game → match IPTV channels → choose stream → play |
| Guide | Current-hour timeline + Grid, provider category order, automatic full EPG |
| Guide favorites | Star channels; distinct from Scores team favorites |
| Movies Now | Movie-like now-playing filter and ratings where configured |
| Player | Full-bleed video, Back, play/pause, rejoin, mute, three-mode ticker |
| Settings | Xtream/M3U, leagues, EPG status/reload, name cleanup, LGPL attribution |
| TV Scores | Horizontal My Games/sport rails on Apple TV and Android TV |
| Brand | Void, gold WATCH, live mint |

## Capability matrix

| Capability | iOS/iPadOS | tvOS | Android phone | Android TV |
|---|---|---|---|---|
| Player presentation | Full-screen cover | Full-screen cover | Full-screen player | Full-screen player |
| Floating pop-out | Supported | Not supported; control omitted | Supported | Pop-out removed on TV (Kotlin updated) |
| Engine routing | Auto TS→VLC, HLS→AV; override/fallback | Same Apple routing | VLC-only | VLC-only |
| AirPlay | AV path/system route | Platform route where available | No Cast claim | No Cast claim |
| Notification start-soon | One-shot local schedule | No-op | Not supported | Not supported |
| Start/score observations | 45-second foreground in-process poll | None | Existing app-driven refreshes only | Existing app-driven refreshes only |
| TV rails/focus | Phone list, touch targets | Implemented; device dogfood gate remains | Phone list | Implemented; device dogfood gate remains |

Notification behavior is not parity: see `docs/game-notifications.md`. No push, WorkManager, alarm, Cast, or multiview is implied.

## Shipped product slices

- Team picker and metadata persistence; no favorite-game concept.
- Live/Upcoming/Final filters and favorite-first grouping.
- Channel favorites in Guide on both stacks.
- Automatic bulk XMLTV plus progressive gap fill.
- Android phone floating player and Apple phone floating player.
- Apple TV and Android TV horizontal Scores rails, focus helpers, leanback target/entry, and TV player controls.
- VLC family on all platforms; Apple retains AVPlayer as its HLS/system path.

## Remaining intentional deltas and gates

1. Android stays VLC-only; Apple dual-engine Auto is not an Android backlog promise.
2. Liquid Glass and some system route surfaces are Apple-specific chrome.
3. TV implementations ship, while simulator/device interaction sign-off remains a release gate.
4. iOS has scheduled start-soon and recurring foreground score polling; Android alerts only observe refreshes the app already performs.
5. Cast, multiview, and remote push remain blocked unless explicitly reopened.

## Dogfood acceptance

Phone:
- Load Xtream; second launch paints cached channels quickly.
- Install Android APK over the old build; saved configuration remains. Uninstall is destructive.
- Add favorite teams through Sport → League → Team; favorite-team games pin first.
- Star Guide channels independently from Scores teams.
- Play from Scores and Guide, change ticker stream through the picker, and exit with always-on Back.
- Pop out and restore only on phone/tablet surfaces.

TV:
- Apple TV uses `SportsDashTV`; player always covers the screen and exposes no floating pop-out.
- Android TV launches from the leanback row; D-pad reaches filters, rails, Guide, player controls, and shell navigation. TV pop-out removed.
- Both TVs show horizontal My Games + per-league (not sport-flat) Scores rails rather than the dense phone list. Sport grouping headers may be present in sections but individual rails use league titles.

## iOS System Picture-in-Picture (updated 2026-08-13)
- System PiP = AV/HLS via AVPlayerViewController automatic (primary path).
- AVPlayerSurface sets `allowsPictureInPicturePlayback = true` and `canStartPictureInPictureAutomaticallyFromInline = true` (iOS 14.2+).
- AVPlayerEngine keeps `isSystemPiPActive` / `setSystemPiPActive` + supports check; startSystemPiPIfPossible is no-op for AV (auto from surface).
- Coordinator (AVPlayerViewControllerDelegate) updates engine state on PiP start/stop/restore.
- NO separate unattached AVPictureInPictureController / playerLayer (removed competing owner).
- VLC/TS → safe handoff to HLS candidate when available (via playbackURLCandidates .m3u8 or alternateXtreamContainer). Starts AV briefly in parallel without stopping VLC first. On AV playing success within ~5s: stop VLC, switch activeBackend=.av, surface swaps to AVPlayerSurface (auto-PiP). On fail/timeout: stop AV attempt, restore VLC active + state, no black screen.
- If no HLS alternate: one-shot banner "System video PiP needs HLS/AV. Audio may continue; in-app pop-out stays in SportsDash." (no spam).
- Do NOT claim PiP success banner unless isPiPActive becomes true.
- Post background signal on .inactive and .background to avoid double-fire.
- In-app pop-out (FloatingPlayerView) for phone multitasking in foreground.
- Phone pop-out stays; TV no float (per product law).
- PlayerView onDisappear skips stop() when `isPiPActive`.
- Full-screen + floating both use the shared surface/engine for their backend.
- UIBackgroundModes audio already present — no change.
- Android untouched.
