# SportsDash TV surfaces

Updated 2026-08-12. TV implementations are present on both stacks; simulator/hardware dogfood remains a separate release gate.

## TV product law

- Player playback is full-screen-only TV product law on both platforms. Pop-out removed (gated for TV).
- Apple uses `fullScreenCover` through `sportsPlayerCover`; never use `.sheet` for the TV player.
- No floating mini-player or pop-out control may be rendered on TV.
- TV Scores uses horizontal My Games first + per-league rails (not sport-flat), not the phone dense list.
- Use remote-safe, focusable, in-content controls. Category lists that need 10-foot traversal use an opaque full-screen presentation on tvOS.
- No `.buttonStyle(.card)` white focus plume over SportsDash gold focus styling.
- Shell navigation remains reachable on TV.

## Apple TV

| Item | Current implementation |
|---|---|
| Scheme | `SportsDashTV` in `SportsDash.xcworkspace` |
| Bundle | `com.samirpatel.sportsdash.tvos` |
| Engine | TVVLCKit hard path; AVPlayer clean-HLS path |
| Focus | `SportsTVFocused`, `sportsTVFocusClean()`, focus sections |
| Scores | Horizontal TV rails (per-league for Upcoming incl empty) with My Games first |
| Guide category | In-content trigger and opaque full-screen picker |
| Player | `fullScreenCover`, full-bleed surface, no pop-out |
| Notifications | tvOS-safe no-op service; Settings alert controls omitted |
| CI | Apple workflow builds the generic tvOS Simulator scheme |

### Apple TV dogfood

```bash
cd ~/agency/sportsdash-apple
git pull origin main
xcodegen generate && pod install
open SportsDash.xcworkspace
# Select SportsDashTV and an Apple TV simulator/device.
```

Checklist:

1. Launch to Scores; no white system focus plume obscures the first control.
2. Live/Upcoming/Final and TV rails receive deterministic focus.
3. My Games and favorite-team editing are remote reachable.
4. Guide category opens an opaque full-screen list; selection returns to Guide.
5. WATCH and Guide playback open a screen-filling player, never a small sheet/card.
6. Player Back, play/pause, mute, ticker, stream selection, and supported engine controls receive focus.
7. No pop-out/floating control is focusable; Menu/Back dismisses full-screen playback.
8. Settings and playlist setup remain remote reachable.

## Android TV

| Item | Current implementation |
|---|---|
| APK | Same `com.samirpatel.sportsdash` APK as phone |
| Launcher | `LEANBACK_LAUNCHER`; touchscreen and leanback features are optional |
| Banner | `@drawable/tv_banner` |
| Detection | `DeviceProfile.isTelevision` |
| Focus | `tvFocusRing`, `tvFocusCircle`, `tvFocusGroup` on core surfaces |
| Scores | Horizontal `ScoresTVBrowse` rails |
| Guide | Timeline/grid/category surfaces with D-pad treatment |
| Player | Media keys and D-pad chrome behavior; full-screen only (pop-out removed and gated) |
| Shell | Top app bar and bottom navigation remain visible/reachable on TV |

Android TV is implemented, not “phone UI only.” TV pop-out removed and Kotlin changed in this revision; device/AVD dogfood verifies full-screen only on TV. A dedicated BrowseFragment or separate TV application ID is not part of the shipped contract.

### Android TV dogfood

```bash
cd ~/agency/sportsdash-apple/android
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
# TV AVD 1080p: open SportsDash from the leanback row.
```

Checklist:

1. Scores: D-pad through filters and rails; WATCH opens stream picker then full-screen playback.
2. Guide: timeline/grid/category controls focus and select without touch.
3. Player: media keys work; D-pad reveals chrome; Back hides chrome then exits.
4. TV pop-out removed on both platforms; full-screen only. Pop-out gated off for television devices.
5. Bottom navigation reaches Scores, Guide, and Settings without phone-landscape hiding.

## TV Scores rails

Both TVs render:

- My Games first when favorite-team games exist.
- Per-league rails on both (Apple now aligned); Upcoming renders empty selected leagues with "None scheduled". Sport headers may group but rails are league-level.
- Large focusable cards with logos, status, scores when applicable, and gold WATCH.
- Left/right navigation within a rail and up/down traversal between rails.

Scores favorites = teams. Guide favorites = channels. There is no favorite-game model.
