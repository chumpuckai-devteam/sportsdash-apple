# SportsDash (Apple)

Native **SwiftUI** app for **iOS** and **Apple TV (tvOS)**.

Flutter prototype (reference only): https://github.com/chumpuckai-devteam/sportsdash

## Features (ported from Flutter)

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
| Fullscreen player (**VLC** + **AVKit**) | ✅ Path A |
| Engine picker (Auto / VLC / AVKit) | ✅ |
| LIVE jump, aspect prefs | ✅ |
| Live scores strip (sport/league collapse) | ✅ |
| Guide timeline + card grid | ✅ |
| 45s scores refresh | ✅ |
| Movie ratings (OMDb/TMDB) for now-playing films | ✅ |

## Open / run

```bash
cd sportsdash-apple
brew install xcodegen cocoapods   # once
xcodegen generate
pod install                      # pulls MobileVLCKit / TVVLCKit (large download)
open SportsDash.xcworkspace      # ← workspace, not .xcodeproj
```

1. **Signing** → your Team + unique bundle id (e.g. `com.samirpatel.sportsdash.ios`)
2. Physical **iPhone** for IPTV (best)
3. Settings → Xtream/M3U → **Save & Load**
4. Scores → card → **Choose a stream** → play

> Always open **`SportsDash.xcworkspace`** after `pod install`. Opening the bare `.xcodeproj` will miss VLC.

## Layout

```
SportsDash/
  App/           AppModel, tabs
  Core/          Models, ESPN, IPTV, EPG, Matching, Storage, Keychain
  Features/      Scores, Channels, Guide, Settings, Player
  Theme/
Podfile          MobileVLCKit (iOS) + TVVLCKit (tvOS)
```

## Video engines (Path A)

| Setting | Behavior |
|---------|----------|
| **Auto (default)** | Clean `.m3u8` → AVKit first; TS / hard IPTV → VLC first; swap on failure |
| **VLC (libVLC)** | Best for messy IPTV / MPEG-TS |
| **AVKit (native)** | Clean HLS; best system PiP / AirPlay story |

Configure under **Settings → Video player**. On error, retry with VLC or AVKit.

**License:** VLCKit is **LGPLv2.1+**. SportsDash app code stays private; ship VLC as a **dynamic framework** (CocoaPods `use_frameworks!`) and keep attribution — see `docs/LGPL-NOTICE.md` and [video-player-options.md](docs/video-player-options.md).

KSPlayer / FFmpegKit (**GPL**) have been **removed**.

## Next enhancements

- Deeper EPG / XMLTV  
- Apple TV focus polish  
- Android repo (Kotlin + Compose + ExoPlayer)  
- Multiview (deferred)

## License

Private / unpublished app code. Third-party: VLCKit LGPL; ESPN public scoreboards (unofficial).
