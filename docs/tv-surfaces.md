# SportsDash TV surfaces

**Updated:** 2026-08-12 — residual Apple TV dogfood after main **1.2.0** (`S-TV.APPLE.2`).

## Apple TV (SportsDashTV)

| Item | Detail |
|------|--------|
| Scheme | **SportsDashTV** in `SportsDash.xcworkspace` |
| Bundle | `com.samirpatel.sportsdash.tvos` |
| Engine | **TVVLCKit** (CocoaPods) |
| Focus | S-TV.1 — `SportsTVFocused` + `sportsTVFocusClean()` |
| Tabs | Scores · Guide · Settings |
| Icons | `AppIcon` tv idiom PNGs in Assets |
| CI | `.github/workflows/ios.yml` also builds **SportsDashTV** (generic tvOS Simulator) |

### Mac dogfood
```bash
cd ~/agency/sportsdash-apple   # or this repo path
git pull origin main
xcodegen generate && pod install
open SportsDash.xcworkspace
# Scheme: SportsDashTV → Apple TV simulator or device
```

### Product law on TV
- No `Menu`-only pickers — in-content + fullScreenCover/sheet
- No `.buttonStyle(.card)` under brand gold
- Gate iOS-only APIs via `PlatformChrome` / `#if os(iOS)`
- Player presents as **sheet** (`sportsPlayerCover`), not phone immersive status-bar hide
- Prefer plain `HStack` + `.focusSection()` over horizontal `ScrollView` for focusable chips (filters + player chrome)

### Residual fixes (this card)
| Area | Issue | Fix |
|------|--------|-----|
| Scores | `myGamesSection` lived under `#if os(iOS)` but called from shared `scoresContent` → **SportsDashTV compile break** when My Games pin path is compiled | Shared `myGamesSection` + TV focus inset / `.focusSection()` |
| Scores | Favorite picker sheet iOS-only; row star actions disabled on TV | Toolbar ★ + My Games “Edit favorites” → `FavoriteTeamPickerView` sheet |
| Favorites sheet | League/team rows missing TV focus clean | `.sportsTVFocusClean()` on all picker steps |
| Player | Horizontal `ScrollView` chrome + plain buttons → weak/no D-pad focus | TV: plain `HStack` + S-TV.1 gold focus on chrome icons + ticker |
| CI | Only iOS scheme built | Add SportsDashTV simulator build |

### Device / sim dogfood checklist (Samir)
Run scheme **SportsDashTV** on Apple TV **sim or hardware** after pull. Mark PASS/FAIL:

1. **Launch** — splash → Scores tab; gold tint; no white system focus plume on first control
2. **Categories (Guide)** — Category control opens **fullScreen** picker; search + list focus; select group returns to grid
3. **Scores focus** — Live / Upcoming / Final chips focusable; sport headers expand/collapse; game rows gold focus (no `.card` white lift)
4. **My Games** — With starred teams, pin section appears; rows focusable; **Edit favorites** / toolbar ★ opens picker; star/unstar teams
5. **Game detail** — Select row → sheet; streams / WATCH path works
6. **Player sheet** — Open from Guide or Scores stream; **VLC** chip when hard path; play/pause, mute, aspect, streams list, ticker cycle all take focus without ScrollView trap
7. **Back / Menu** — Dismiss player sheet; floating pop-out parks safely if used
8. **Settings** — Xtream login + engine preference reachable with remote

**Linux CI host cannot sign off device ACs** — static + workflow gate only. Attach screenshots / short notes on the kanban card when done.

## Android TV (started 1.2.0-tv)

| Item | Detail |
|------|--------|
| Same APK | `com.samirpatel.sportsdash` with `LEANBACK_LAUNCHER` |
| Leanback feature | `required=false` (phone install still OK) |
| Touchscreen | `required=false` |
| Banner | `@drawable/tv_banner` |
| Detection | `DeviceProfile.isTelevision` |
| Shell | TopAppBar + bottom nav **always** on TV (D-pad); phone landscape still hides shell |

### D-pad focus (**1.2.1-tv-focus** · S-TV.AND.2)
| Surface | Focus law |
|---------|-----------|
| Helpers | `ui/tv/TvFocus.kt` — `tvFocusRing` / `tvFocusCircle` / `tvFocusGroup` (gold + scale; no double-`focusable` with clickable) |
| Shell | TopAppBar + bottom nav **always** on TV |
| Scores | Live/Upcoming/Final chips, favorite rail, sport headers, game rows, stream picker rows |
| Guide | Action bar focus group; Hour timeline channel col + row; Grid cards; category sheet rows |
| Player | Media play/pause keys; DPAD reveals chrome when hidden; CENTER only intercepts when chrome down; Back hides chrome first; circle controls + ticker pills |
| Phone | All rings gated by `DeviceProfile.isTelevision` — phone UX unchanged |

### Emulator dogfood checklist
1. Install debug APK on **TV AVD 1080p** · open from leanback row (banner)
2. Scores — D-pad chips → game row gold ring → select opens stream picker → play
3. Guide Hour — earlier/now/later; channel column focus → play; Grid cards focus → play
4. Player — transport + mute/ticker focus; media key play/pause; Back hides chrome then exits
5. Bottom nav — Scores/Guide/Settings always reachable (shell not landscape-hidden)

### Not yet (follow-on)
- Dedicated Leanback BrowseFragment / sidemenu redesign
- Separate `applicationId` TV flavor
- Device stick dogfood sign-off (needs hardware / AVD session from Samir)