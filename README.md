# SportsDash (Apple)

Native **SwiftUI** app for **iOS** and **Apple TV (tvOS)**.

## Open / run

VLC uses **official VideoLAN MobileVLCKit / TVVLCKit binaries** via SPM  
([vlckit-spm](https://github.com/tylerjonesio/vlckit-spm) — same frameworks as CocoaPods, no pod rsync).

```bash
cd sportsdash-apple
git pull origin main

# Quit Xcode first
rm -rf Pods/ *.xcworkspace Podfile.lock   # remove old CocoaPods leftovers if present
rm -rf ~/Library/Developer/Xcode/DerivedData/SportsDash-*

brew install xcodegen   # once
xcodegen generate
open SportsDash.xcodeproj
```

In Xcode:
1. Wait for **package resolve** (VLC binary is large — first download can take several minutes)
2. If stuck: **File → Packages → Reset Package Caches**, then resolve again
3. Scheme **SportsDash** → your iPhone → **Clean Build Folder** (⇧⌘K) → Run

**Do not** open an old `SportsDash.xcworkspace` from CocoaPods — use **`.xcodeproj`** after `xcodegen generate`.

## Video engines (Path A)

| Setting | Behavior |
|---------|----------|
| **Auto** | HLS → AVKit first; TS / hard IPTV → VLC first |
| **VLC** | Official libVLC (MobileVLCKit) |
| **AVKit** | Native AVPlayer |

## Why not CocoaPods right now?

Xcode’s User Script Sandbox was blocking CocoaPods’ `rsync` copy of `MobileVLCKit.framework` on this machine. SPM links the same VLC binaries without that script.

## License

Private app code. VLCKit: LGPL (VideoLAN) — see `docs/LGPL-NOTICE.md`.
