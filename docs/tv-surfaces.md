# SportsDash TV surfaces

**Updated:** 2026-08 goal — complete Apple TV path + start Android TV.

## Apple TV (SportsDashTV)

| Item | Detail |
|------|--------|
| Scheme | **SportsDashTV** in `SportsDash.xcworkspace` |
| Bundle | `com.samirpatel.sportsdash.tvos` |
| Engine | **TVVLCKit** (CocoaPods) |
| Focus | S-TV.1 — `SportsTVFocused` + `sportsTVFocusClean()` |
| Tabs | Scores · Guide · Settings |
| Icons | `AppIcon` tv idiom PNGs in Assets |

### Mac dogfood
```bash
cd ~/agency/sportsdash-apple
git pull origin main
xcodegen generate && pod install
open SportsDash.xcworkspace
# Scheme: SportsDashTV → Apple TV simulator or device
```

### Product law on TV
- No `Menu`-only pickers — in-content + fullScreenCover/sheet
- No `.buttonStyle(.card)` under brand gold
- Gate iOS-only APIs via `PlatformChrome` / `#if os(iOS)`
- Player sheet (not phone immersive status-bar hide)

## Android TV (started 1.2.0-tv)

| Item | Detail |
|------|--------|
| Same APK | `com.samirpatel.sportsdash` with `LEANBACK_LAUNCHER` |
| Leanback feature | `required=false` (phone install still OK) |
| Touchscreen | `required=false` |
| Banner | `@drawable/tv_banner` |
| Detection | `DeviceProfile.isTelevision` |
| Shell | TopAppBar + bottom nav **always** on TV (D-pad); phone landscape still hides shell |

### D-pad focus (1.2.1-tv-focus)
- `ui/tv/TvFocus.kt` — gold focus ring + scale on focused items
- Scores filter chips + game rows
- Guide grid cards + timeline rows  
- Player: media play/pause, DPAD center, enter, back keys

### Not yet (follow-on)
- Dedicated Leanback BrowseFragment / sidemenu redesign
- D-pad focus audit on every Guide cell
- Android TV remote play/pause key mapping beyond VLC
- Separate `applicationId` TV flavor

### Emulator dogfood
```bash
cd android && ./gradlew :app:assembleDebug
# AVD: TV (1080p) API 34 · install APK · open from TV home row
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Kanban
- **S-PARITY.C4** `t_8867a2a0` — this track
