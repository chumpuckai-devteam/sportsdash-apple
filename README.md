# SportsDash (Apple)

Native **SwiftUI** app for **iOS** and **Apple TV (tvOS)**.

Flutter prototype (reference only): https://github.com/chumpuckai-devteam/sportsdash

## Features

| Area | Status |
|------|--------|
| Scores by **sport → league** shelves | ✅ |
| LIVE / UPCOMING / FAVES / ALL filters | ✅ |
| Favorite teams | ✅ |
| ESPN scoreboards (multi-league) | ✅ |
| Select leagues in Settings | ✅ |
| Xtream + M3U load (Keychain password) | ✅ |
| Channel browser by provider group | ✅ |
| Stream matching (teams / groups / broadcasts) | ✅ |
| Game detail → choose stream | ✅ |
| Fullscreen player (**official VLCKit** + **AVKit**) | ✅ Path A |
| Engine picker (Auto / VLC / AVKit) | ✅ |
| LIVE jump, aspect prefs | ✅ |
| Live scores strip | ✅ |
| Guide timeline + card grid | ✅ |
| Movie ratings (OMDb/TMDB) | ✅ |

## Open / run (CocoaPods + XcodeGen)

VLC uses **official VideoLAN pods** (`MobileVLCKit` / `TVVLCKit`) — not third-party SPM wrappers.

```bash
cd sportsdash-apple
git pull origin main

# tools (once)
brew install xcodegen cocoapods

# regenerate project + install official VLCKit
xcodegen generate
pod install          # first time is a large download

# ALWAYS open the workspace (pods live here)
open SportsDash.xcworkspace
```

In Xcode:
1. Scheme **SportsDash** → your **iPhone**
2. Signing → your Team
3. **Product → Clean Build Folder** (⇧⌘K) once after pull
4. Run (⌘R)

### Common mistakes
| Mistake | Result |
|---------|--------|
| Open `SportsDash.xcodeproj` instead of `.xcworkspace` | `No such module 'MobileVLCKit'` |
| Skip `pod install` | Same module error |
| Skip `xcodegen generate` after Project.yml changes | Stale project / old packages |
| Still see **FFmpegKit** | Stale DerivedData — delete `~/Library/Developer/Xcode/DerivedData/SportsDash-*` |

## Video engines (Path A)

| Setting | Behavior |
|---------|----------|
| **Auto (default)** | Clean `.m3u8` → AVKit first; TS / hard IPTV → VLC first; swap on failure |
| **VLC** | Official **MobileVLCKit** / **TVVLCKit** (libVLC, LGPL) |
| **AVKit** | Native AVPlayer — clean HLS, system routes |

KSPlayer / FFmpegKit / third-party VLC SPM wrappers are **not** used.

LGPL notes: `docs/LGPL-NOTICE.md` · research: `docs/video-player-options.md`

## Layout

```
SportsDash/
  App/           AppModel, tabs
  Core/          Models, ESPN, IPTV, EPG, Matching, Storage, Keychain
  Features/      Scores, Channels, Guide, Settings, Player
  Theme/
Podfile          MobileVLCKit (iOS) + TVVLCKit (tvOS)
Project.yml      XcodeGen (no SPM player deps)
```

## License

Private app code. Third-party: VLCKit LGPL (VideoLAN).
