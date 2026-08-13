# SportsDash Android

Compose + libVLC application for Android phone and Android TV. Production Android code lives in this monorepo under `android/`; do not create a separate repository.

## Toolchain

- Android Studio Gradle JDK: 21 (JetBrains Runtime).
- Do not pin `jvmToolchain(17)` when only JBR 21 is installed.
- Source/target bytecode remains Java 17 through `compileOptions` and Kotlin `jvmTarget`.
- Ignore optional “new minor Gradle version” prompts during dogfood.

## Open and run

```bash
cd ~/agency/sportsdash-apple
git pull origin main
# Android Studio → Open → select android/
# Sync, then Run ▶ on phone, emulator, or TV AVD.
```

CLI debug build:

```bash
cd ~/agency/sportsdash-apple/android
./gradlew :app:clean :app:assembleDebug
# android/app/build/outputs/apk/debug/app-debug.apk
```

Package ID: `com.samirpatel.sportsdash`. The debug APK is dogfood-only, not a Play Store artifact.

## Updating without losing IPTV configuration

Install the new APK over the existing application. Do not uninstall first.

| Operation | App-private data |
|---|---|
| Open newer APK over installed app or `adb install -r` | Preserved when application ID and signing key match |
| Uninstall, then install | Deleted by Android; credentials must be entered again |

The application writes playlist configuration to DataStore and app-private compatibility backups. Those locations improve update resilience but are not described as encrypted credential storage. See `../docs/android-login-persist.md` for the current storage contract.

## Friend APK and Samsung sideloading

Share `app-debug.apk` directly through Drive/AirDrop rather than messaging compression. A full libVLC APK is normally tens of megabytes; a tiny file indicates the wrong artifact.

On current Samsung devices:

1. Settings → Security and privacy → Auto Blocker → Off.
2. Allow “Install unknown apps” for the app opening the APK.
3. Approve Play Protect's “Install anyway” flow if shown.
4. Install over the old build.

USB installation gives the actionable error code:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

| Error | Meaning/action |
|---|---|
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Signing mismatch; uninstall is the last resort and deletes app data |
| `INSTALL_FAILED_INVALID_APK` | Rebuild and recopy the artifact |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | Wrong/stale APK; rebuild current source |
| `INSTALL_FAILED_USER_RESTRICTED` | Auto Blocker or unknown-app restriction remains enabled |
| `INSTALL_FAILED_VERSION_DOWNGRADE` | Installed versionCode is newer |

## Android TV

Android TV support is implemented in the same APK:

- `LEANBACK_LAUNCHER` and TV banner provide a home-row entry.
- Touchscreen and leanback hardware features are optional, preserving phone installability.
- `DeviceProfile.isTelevision` selects TV behavior.
- Scores renders horizontal TV rails.
- `tvFocusRing`, `tvFocusCircle`, and `tvFocusGroup` cover core Scores, Guide, and player surfaces.
- Shell navigation remains reachable on TV.
- Media keys and D-pad reveal/Back behavior are implemented in the player.
- TV playback full-screen only (pop-out removed and gated by isTelevision; Kotlin changed).

AVD/hardware dogfood for full-screen TV (pop-out removed); that does not make Android TV absent or phone-only. See `../docs/tv-surfaces.md`.

TV AVD build/install:

```bash
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
# Use a 1080p TV AVD and launch from the leanback row.
```

## Product implementation map

```text
android/app/src/main/java/com/samirpatel/sportsdash/
  core/iptv/           Xtream + M3U
  core/epg/            bulk XMLTV + automatic short-EPG gap fill
  core/player/         VlcPlayerController
  core/sports/         ESPN Scores
  core/notifications/  refresh-observed local alert helper
  ui/                  phone/TV Compose surfaces
```

- Engine: libVLC is shipping now, not future work.
- Scores: ESPN Live/Upcoming/Final with team favorites.
- Guide favorites: channels, separate from Scores team favorites.
- Notifications: alerts occur when existing app-driven score refreshes observe transitions; no WorkManager, alarm, scheduled start-soon, push, or parity with iOS is claimed. See `../docs/game-notifications.md`.

## License

libVLC Android is LGPL. See `../docs/LGPL-NOTICE.md`.

## CI (added for P0.5)

- `.github/workflows/android.yml` runs on push/PR: JDK21, `./gradlew :app:test` (JVM unit tests for pure logic) + `assembleDebug`.
- Tests cover league persistence migration, upcoming grouping, etc.
