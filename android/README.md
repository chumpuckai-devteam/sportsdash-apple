# SportsDash Android

Compose + **libVLC** (`org.videolan.android:libvlc-all`) dogfood app.  
Same repo as iOS/tvOS (`sportsdash-apple`). Shared product law: **TS → VLC**, Xtream/M3U, LGPL.

## JDK / Gradle note

1. **Gradle JDK = 21** (JetBrains Runtime) in Studio:  
   **Settings → Build Tools → Gradle → Gradle JDK → 21**
2. We do **not** pin `jvmToolchain(17)` (that requires a separate JDK 17 install and breaks with only JBR 21).
3. App still compiles to **Java 17 bytecode** via `compileOptions` / `jvmTarget = "17"`.

Ignore “New Minor Gradle Version” for now.

## Open & run (emulator / your phone via USB)

```bash
cd ~/agency/sportsdash-apple
git pull origin main
# Android Studio → Open → select android/
```

Sync → Run.

## Build a friend APK (sideload)

### In Android Studio

1. `git pull origin main`
2. Open **`android/`**
3. **Build → Clean Project**
4. **Build → Rebuild Project**
5. **Build → Build Bundle(s) / APK(s) → Build APK(s)**
6. Click **locate** when finished, or open:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

### CLI

```bash
cd ~/agency/sportsdash-apple/android
./gradlew :app:clean :app:assembleDebug
open app/build/outputs/apk/debug/   # Finder
```

Package id: **`com.samirpatel.sportsdash`**  
File: **`app-debug.apk`** (debug-signed — fine for dogfood, not Play Store)

### Share

- AirDrop / Drive / Dropbox — send the **`.apk` file only** (not a zip of the whole project).
- Prefer **Google Drive “anyone with link”** over SMS (SMS can corrupt large APKs).

## Install on Samsung (and most Android phones)

1. On the phone: open the APK with **My Files** or **Files** (not a random browser cache if possible).
2. If blocked: **Settings → Apps → More → Special access → Install unknown apps → My Files** (or Chrome) → **Allow**.
3. If **Play Protect** blocks: open the Protect notification → **More details → Install anyway** (or briefly disable Play Protect scans).
4. If it says **App not installed**:
   - Uninstall any older **SportsDash** first.
   - Re-download the APK (don’t rename oddly; keep `.apk`).
   - Confirm file size is **tens of MB** (libVLC) — a tiny APK is incomplete.
   - Phone must be **Android 8+** (`minSdk 26`).
5. After install, open **SportsDash** → Settings → Xtream → wait for full guide on first load.

### USB install (most reliable)

```bash
# Phone: Developer options → USB debugging ON
adb devices
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

`-r` replaces an existing install. If signature conflict:

```bash
adb uninstall com.samirpatel.sportsdash
adb install app/build/outputs/apk/debug/app-debug.apk
```

## Android TV

**Not ready.** Phone UI only (no leanback launcher / D-pad). Sideload may open on some sticks but UX is poor. TV shell is later.

## Layout

```
android/
  app/src/main/java/com/samirpatel/sportsdash/
    core/iptv/     Xtream + M3U
    core/epg/      xmltv bulk + short EPG
    core/player/   VlcPlayerController
    core/sports/   ESPN scores
    ui/            Compose screens
```

## License

libVLC Android — LGPL. See `../docs/LGPL-NOTICE.md`.
