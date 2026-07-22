# SportsDash (Apple)

Native **SwiftUI** app for **iOS** and **Apple TV (tvOS)**.

## Open / run

```bash
cd sportsdash-apple
git pull origin main

# Quit Xcode first
rm -rf Pods SportsDash.xcworkspace Podfile.lock
rm -rf ~/Library/Developer/Xcode/DerivedData/SportsDash-*

brew install xcodegen   # once
xcodegen generate
open SportsDash.xcodeproj
```

In Xcode:
1. Wait for **KSPlayer** package resolve (large FFmpeg binaries — first time can take a while)
2. **File → Packages → Resolve Package Versions** if needed
3. Scheme **SportsDash** → your iPhone → Clean (⇧⌘K) → Run

## Video player (current)

| Setting | Engine |
|---------|--------|
| **KSPlayer (Metal)** default | FFmpeg via KSPlayer — best for live IPTV |
| **AVKit** | Native AVPlayer |
| Fallback | On by default |

> **Note:** Path A (official VLCKit) is **parked**. CocoaPods hit Xcode sandbox `rsync` failures; SPM wrappers failed module resolve on device builds. We restored the last **known-good KSPlayer** stack so you can dogfood. VLC will be re-spiked separately.

KSPlayer public package is **GPL** — OK for TestFlight/dogfood; App Store may need their paid LGPL deal (see KSPlayer README).

## Features

Scores, Xtream/M3U, Guide, floating player, movie ratings (OMDb/TMDB), ESPN start-time fix for Upcoming.

## Docs

- `docs/movie-ratings.md`
- `docs/video-player-options.md` (VLC research — parked)
- `docs/LGPL-NOTICE.md`
