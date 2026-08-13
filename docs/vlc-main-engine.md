# VLC main engine

Decision: VLC/libVLC is the shipping hard IPTV engine family on every platform. Apple uses MobileVLCKit/TVVLCKit; Android ships `libvlc-all` 3.6.x. KSPlayer/GPL dependencies are removed.

## Runtime architecture

| Stream/capability | Apple | Android |
|---|---|---|
| MPEG-TS, unknown, Xtream `/live/` | VLC | VLC |
| Clean HLS `.m3u8` | AVPlayer in Auto | VLC |
| Manual engine choice | VLC or AVPlayer | VLC only |
| One cross-engine fallback | Supported | Not supported/claimed |
| TV hard engine | TVVLCKit | libVLC |

Android's VLC-only route is intentional. “Same family later,” ExoPlayer, mpv, and another hard-engine migration are not current implementation claims.

## Apple packaging

```bash
cd ~/agency/sportsdash-apple
git checkout -- SportsDash.xcodeproj/project.pbxproj   # only if generated file is dirty
git pull origin main
rm -rf Pods ~/Library/Developer/Xcode/DerivedData/SportsDash-*
xcodegen generate
pod install
open SportsDash.xcworkspace
```

Open the workspace, not the bare project. `ENABLE_USER_SCRIPT_SANDBOXING=NO` is required for CocoaPods to embed the large VLC frameworks.

Apple settings:

- Auto: TS/unknown → VLC; clean HLS → AVPlayer.
- VLC: force MobileVLCKit/TVVLCKit.
- AVKit: force native Apple playback.
- Optional Apple fallback tries the other engine once.

## Android packaging

`android/app/build.gradle.kts` owns `org.videolan.android:libvlc-all`. Build with JDK 21:

```bash
cd ~/agency/sportsdash-apple/android
./gradlew :app:assembleDebug
```

Android does not expose a dual-engine preference. Do not describe VLC as future work there.

## License

VLCKit/libVLC are LGPL. See `docs/LGPL-NOTICE.md` and Settings → About. Keep upstream framework replacement/notice obligations intact and do not re-add GPL player code.

## Troubleshooting Apple embed

1. Confirm User Script Sandboxing is No for app and Pods targets.
2. Wipe DerivedData and run `pod deintegrate && pod install` if embed state is stale.
3. Regenerate with XcodeGen, then reopen `SportsDash.xcworkspace`.
4. Do not switch player engines as a packaging workaround.
