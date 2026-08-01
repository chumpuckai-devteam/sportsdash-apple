# SportsDash Android

Compose + **libVLC** (`org.videolan.android:libvlc-all`) dogfood app.  
Same repo as iOS/tvOS (`sportsdash-apple`). Shared product law: **TS → VLC**, Xtream/M3U, LGPL.

## JDK / Gradle note

Gradle **8.9** needs a JVM **≤ 22**. Android Studio’s default is sometimes **JDK 25** → import fails.

**Fix:** in the dialog click **Use JVM 21** (or 17).

Or: **Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK → 21** (or 17).

Project is pinned to **Java 17** toolchain in `app/build.gradle.kts`.

```bash
# On a machine with Android Studio (Mac/Windows/Linux)
cd sportsdash-apple   # or ~/agency/sportsdash-apple
git pull origin main

# Open the android folder (not the iOS xcodeproj)
# Android Studio → Open → select android/
```

Or from CLI (JDK 17+ + Android SDK):

```bash
cd android
# First time: Android Studio will generate gradlew; or:
# gradle wrapper
./gradlew :app:assembleDebug
./gradlew :app:installDebug
```

## First dogfood

1. Run **app** on emulator or device  
2. **Settings** → Xtream: host + user + password → Save  
3. **Channels** → pick a live stream → VLC player overlay  

## Layout

```
android/
  app/src/main/java/com/samirpatel/sportsdash/
    core/iptv/     Xtream + M3U
    core/player/   VlcPlayerController
    core/model/    Channel, StreamContainer
    ui/            Compose screens
  app/build.gradle.kts   libvlc-all:3.6.0
```

## Not in v1 (coming)

- Full Guide / EPG (`xmltv.php`)  
- ESPN scores  
- Android TV leanback  
- Soft ExoPlayer path for clean HLS (optional; VLC handles HLS too)

## License

libVLC Android — LGPL. See `../docs/LGPL-NOTICE.md`.
