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

## Updating (keep Xtream login) — read this first

**Do not uninstall SportsDash to install a newer dogfood APK.**

| Path | Xtream / M3U login |
|------|--------------------|
| **Install over** (open new APK while old app is still installed, or `adb install -r`) | **Kept** — same `applicationId` `com.samirpatel.sportsdash` |
| **Uninstall → install** | **Wiped** — Android deletes app private storage (DataStore + backups) |

Friends who uninstall and reinstall will always need to re-enter credentials. That is normal Android behavior, not a regression.

Details: [`../docs/android-login-persist.md`](../docs/android-login-persist.md)

## Install on Samsung — “App not installed”

Do these **in order**. Step 1 fixes most modern Galaxy phones.

### 1. Turn OFF Auto Blocker (One UI 6 / 7)

**Settings → Security and privacy → Auto Blocker → Off**

Samsung blocks many sideloaded APKs with a generic **App not installed** when this is on.

### 2. Allow installs from My Files

**Settings → Apps → ⋮ → Special access → Install unknown apps → My Files → Allow**

### 3. Play Protect

If a shield notification appears: **More details → Install anyway**  
(or Play Store → profile → Play Protect → settings → briefly disable scanning)

### 4. Prefer install-over (keep login)

Leave the existing SportsDash app installed. Open the new `app-debug.apk` and choose **Update** / install.

**Only uninstall** if install fails with signature mismatch (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) or a truly broken install — then you **will** need to re-enter Xtream.

### 5. Use a full APK (not a tiny file)

After rebuild, `app-debug.apk` should be **roughly 50–120 MB** (libVLC).  
If it’s under ~10 MB, the build/copy is wrong.

Share via **Google Drive / AirDrop**, not SMS/iMessage (can corrupt).

### 6. Install via USB (shows the real error)

On Mac, with USB debugging enabled on the phone:

```bash
cd ~/agency/sportsdash-apple
git pull origin main
cd android
./gradlew :app:clean :app:assembleDebug
# Install OVER the existing app (keeps login). Do NOT adb uninstall first.
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

If it fails, `adb` prints a code like:

| Code | Meaning |
|------|---------|
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Different signing key — uninstall old app, then install (login lost) |
| `INSTALL_FAILED_INVALID_APK` | Bad/corrupt file — rebuild + re-copy |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | Wrong CPU APK (rebuild after latest pull) |
| `INSTALL_FAILED_USER_RESTRICTED` | Auto Blocker / unknown apps still on |
| `INSTALL_FAILED_VERSION_DOWNGRADE` | Newer version already installed — ship a higher `versionCode` |

Copy/paste that `INSTALL_FAILED_…` line back to me.

### Rebuild dogfood APK

```bash
cd ~/agency/sportsdash-apple
git pull origin main
cd android
./gradlew :app:clean :app:assembleDebug
open app/build/outputs/apk/debug/
# → app-debug.apk
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

## Playlist login persistence

Full write-up: [`../docs/android-login-persist.md`](../docs/android-login-persist.md)

- Xtream host/user/password and M3U URL live in **DataStore** (`sportsdash_prefs`) and are multi-written to:
  - **SharedPreferences** `sportsdash_secure_backup` (sync `commit`)
  - **`filesDir/playlist_config_backup.json`** (atomic rewrite)
- **APK update-install** (same `applicationId` `com.samirpatel.sportsdash`, rising `versionCode`) keeps private storage — login loads without re-entry.
- Settings shows saved host/user; **password field stays blank** meaning “keep existing” on Save.
- **Uninstall** clears app private storage (DataStore + backups). Expected Android behavior — not fixed by dual-write.

## License

libVLC Android — LGPL. See `../docs/LGPL-NOTICE.md`.
