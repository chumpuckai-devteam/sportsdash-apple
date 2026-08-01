# VLC main engine cutover (iOS / tvOS)

**Date:** 2026-08  
**Decision:** libVLC is the **main hard engine** (MobileVLCKit + TVVLCKit). Same family later on Android.  
**Soft path:** native AVPlayer for clean HLS.

## Architecture

| Stream | Engine |
|--------|--------|
| MPEG-TS / unknown / Xtream `/live/` | **VLC** |
| HLS `.m3u8` | **AVPlayer** |
| Fallback (once) | Other engine |

KSPlayer (GPL) **removed** from the package graph.

## Packaging (CocoaPods — official)

```bash
# Quit Xcode
cd ~/agency/sportsdash-apple
git checkout -- SportsDash.xcodeproj/project.pbxproj   # if dirty
git pull origin main
rm -rf Pods ~/Library/Developer/Xcode/DerivedData/SportsDash-*
xcodegen generate
pod install
open SportsDash.xcworkspace   # NOT the .xcodeproj
```

**Critical:** open **`SportsDash.xcworkspace`**.

Project sets `ENABLE_USER_SCRIPT_SANDBOXING = NO` so CocoaPods can embed the large VLC frameworks (previous Path A failure mode).

First `pod install` downloads large binaries — be patient.

## Settings

- **Auto · TS→VLC · HLS→AV · Default**
- **VLC (libVLC) · Main**
- **AVKit (Native)**

## License

LGPL — see `docs/LGPL-NOTICE.md`. Dynamic frameworks via CocoaPods. Attribution in Settings → About.

## Android later

Use libVLC / VLC Android as the hard engine so product behavior matches iOS/tvOS.

## If pod install / embed fails again

1. Confirm Build Setting **User Script Sandboxing = No** on SportsDash + Pods targets  
2. Wipe DerivedData + `pod deintegrate && pod install`  
3. Do **not** re-add KSPlayer without Samir asking  
