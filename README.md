# SportsDash

Native multi-platform IPTV + scores:

| Platform | Path | UI | Hard player |
|----------|------|-----|-------------|
| **iOS / tvOS** | repo root (`SportsDash/`) | SwiftUI | VLCKit (CocoaPods, LGPL) |
| **Android** | `android/` | Jetpack Compose | libVLC (`libvlc-all`, LGPL) |

Same product, same GitHub repo. Rename `sportsdash-apple` → `sportsdash` later if you want.

## iOS / Apple TV

```bash
cd sportsdash-apple
git pull origin main
# Quit Xcode
git checkout -- SportsDash.xcodeproj/project.pbxproj   # if dirty
xcodegen generate
pod install
open SportsDash.xcworkspace   # NOT .xcodeproj
```

Scheme **SportsDash** (iPhone) or **SportsDashTV**.  
Auto player: **TS → VLC · HLS → AVPlayer**.

Details: `docs/vlc-main-engine.md`

## Android

```bash
cd sportsdash-apple
git pull origin main
# Android Studio → Open → android/
```

Settings → add Xtream or M3U → Channels → play (libVLC).

Details: `android/README.md` · `docs/dual-platform.md`

## Docs

- `docs/dual-platform.md` — map
- `docs/vlc-main-engine.md` — Apple VLC
- `docs/LGPL-NOTICE.md`
- `docs/epg-auto-full-load.md` — iOS EPG (Android EPG next)
