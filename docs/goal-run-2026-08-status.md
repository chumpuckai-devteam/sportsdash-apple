# Dual-platform goal run — status

**Started:** 2026-08 goal command  
**HEAD at start:** `2227bf6`

## Shipped this run

### P0 — Favorite team id collisions (S-BUG.FAV.1)
ESPN reuses bare numeric team ids across sports (**NFL Buccaneers `27` == MLB Rockies `27`**).  
Ids are now **`{league}:{espnId}`** (e.g. `nfl:27`, `mlb:27`) on iOS + Android scoreboard + roster parse.  
Legacy bare ids migrate on scores refresh by name/abbrev match; ambiguous bare ids are dropped.

### P0 — iOS Guide empty Favorites landing
Default category is first **populated** group; empty ★ Favorites no longer traps the user.

### P0 — Android landscape nav escape
Slim **Scores | Guide | Settings** strip when shell bars hide in landscape.

### P0 — Android WATCH affordance
Gold **WATCH** pill on live/final/upcoming rows; lighter void-friendly row background.

### Parity polish
- iOS filter label **Final** (was ALL); Final filter shows completed games only.
- iOS player chrome auto-hide **4.5s** (was 6s).

## Still open (next slices)
- Android row anatomy full parity with iOS (outside-corner stars, large split scores) — partial
- Accessibility labels pass
- FB.14 tester blurb / install-over verify (code already dual-write)
- Cast / TV / multiview remain blocked

## Dogfood

### Android
```bash
cd ~/agency/sportsdash-apple && git pull origin main
cd android && ./gradlew :app:clean :app:assembleDebug
# app/build/outputs/apk/debug/app-debug.apk — install OVER previous (do not uninstall)
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

### Favorite id retest
1. Clear or re-add favorites after upgrade (migration may drop ambiguous bare ids).
2. Star **Buccaneers** only → Rockies must **not** star; Rays@Rockies must **not** enter My Games unless Rockies/Rays starred.
3. Star **Braves** → only Braves games in My Games.
