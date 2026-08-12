# Dual-platform goal run — status

**Goal command active** · Latest ship: see `git log`

## Completed slices

| Area | Status | Notes |
|------|--------|--------|
| League-scoped favorite team ids | **Done** `8d40f0d` | `nfl:27` vs `mlb:27` (Bucs ≠ Rockies) |
| iOS Guide empty Favorites landing | **Done** `8d40f0d` | First populated category |
| Android landscape tab escape | **Done** `8d40f0d` | Slim Scores/Guide/Settings strip |
| Android gold WATCH | **Done** `8d40f0d`+ | All watchable rows |
| Final filter parity | **Done** `8d40f0d` | iOS label + finals-only list |
| Player chrome 4.5s fade | **Done** `8d40f0d` | iOS matched Android |
| Android score row anatomy | **Done** (this ship) | Outside stars, split scores, void, WATCH center |
| A11y player/scores | **Done** (this ship) | iOS chrome labels; Android row/ticker merge semantics |
| FB.14 install-over messaging | **Done** | Settings + `docs/android-login-persist.md` + README |
| Ticker 3-mode / fav-first / picker | **Done** earlier | OFF/FADE/PIN |
| Full-bleed player | **Done** earlier | |
| Dense scores chrome one-row | **Done** earlier | |

## Intentionally deferred (parity freeze)
- Cast / AirPlay deep / Chromecast
- Android TV / tvOS expansion
- Multiview
- Push notifications
- Reinstall-survive credential export

## Dogfood

### Android **1.1.19-goal-parity**
```bash
cd ~/agency/sportsdash-apple && git pull origin main
cd android && ./gradlew :app:clean :app:assembleDebug
# Install OVER previous app — do not uninstall
```

### iOS
```bash
cd ~/agency/sportsdash-apple
git checkout -- SportsDash.xcodeproj/project.pbxproj 2>/dev/null || true
git pull origin main
rm -rf Pods ~/Library/Developer/Xcode/DerivedData/SportsDash-*
xcodegen generate && pod install
open SportsDash.xcworkspace
```

### Favorite retest
1. After upgrade, re-star teams if stars look odd (legacy bare ids migrate/drop).
2. Buccaneers only → Rockies off; Rays@Rockies not in My Games.
3. Landscape: tab strip still switches Scores/Guide/Settings.


## TV goal (Samir unlocked)

- Apple TV: compile gates + focus law documented; scheme SportsDashTV
- Android TV: leanback launcher + banner + DeviceProfile + shell chrome kept on TV (`1.2.0-tv`)
- See `docs/tv-surfaces.md`
