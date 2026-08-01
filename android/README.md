# SportsDash Android

Compose + **libVLC** (`org.videolan.android:libvlc-all`) dogfood app.  
Same repo as iOS/tvOS (`sportsdash-apple`). Shared product law: **TS → VLC**, Xtream/M3U, LGPL.

## JDK / Gradle note

1. **Gradle JDK = 21** (JetBrains Runtime) in Studio:  
   **Settings → Build Tools → Gradle → Gradle JDK → 21**
2. We do **not** pin `jvmToolchain(17)` (that requires a separate JDK 17 install and breaks with only JBR 21).
3. App still compiles to **Java 17 bytecode** via `compileOptions` / `jvmTarget = "17"`.

If you see `Cannot find a Java installation matching languageVersion=17` → `git pull` and Sync again.

Ignore “New Minor Gradle Version” for now.

## Open & run

```bash
cd sportsdash-apple   # or ~/agency/sportsdash-apple
git pull origin main

# Android Studio → Open → select android/
```

1. Sync Gradle  
2. Start Pixel emulator  
3. Run **app**  
4. Settings → Xtream → Save → Channels → play  

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

## License

libVLC Android — LGPL. See `../docs/LGPL-NOTICE.md`.
