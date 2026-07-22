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
| Fullscreen player (**KSPlayer** FFmpeg + AVPlayer) | ✅ |
| Engine picker (Auto / FFmpeg / AVPlayer) | ✅ |
| LIVE jump, aspect prefs, hardware decode | ✅ |
| Live scores strip (sport/league collapse) | ✅ |
| Guide timeline + card grid | ✅ |
| 45s scores refresh | ✅ |

## Open / run

```bash
cd sportsdash-apple
xcodegen generate   # after Project.yml changes
open SportsDash.xcodeproj
```

1. **Signing** → your Team + unique bundle id (e.g. `com.samirpatel.sportsdash.ios`)
2. Physical **iPhone** for IPTV (best)
3. Settings → Xtream/M3U → **Save & Load**
4. Scores → card → **Choose a stream** → play

## Layout

```
SportsDash/
  App/           AppModel, tabs
  Core/          Models, ESPN, IPTV, EPG, Matching, Storage, Keychain
  Features/      Scores, Channels, Guide, Settings, Player
  Theme/
```

## Video engines

Playback uses **[KSPlayer](https://github.com/kingslay/KSPlayer)** (FFmpeg via FFmpegKit + optional AVPlayer):

| Setting | Behavior |
|---------|----------|
| **Auto (default)** | FFmpeg first, AVPlayer fallback |
| **FFmpeg (KSPlayer)** | Best for messy IPTV / TS |
| **AVPlayer (native)** | Apple only — clean HLS |

Configure under **Settings → Player**. On playback error, the player offers a one-tap engine switch.

> **Note:** KSPlayer’s public package is **GPL**. Shipping a closed App Store binary may require a commercial/LGPL arrangement with the KSPlayer author — see their README.

First `xcodebuild` resolves large binary packages (FFmpegKit). If Metal shaders fail to compile, install the toolchain once:

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Next enhancements

- Deeper EPG / XMLTV  
- **Movie ratings (RT-style)** — ✅ Sprint 1: OMDb/TMDB + Guide/Player chips (see `docs/movie-ratings.md`); needs API key in Settings  
- Apple TV focus polish  
- Android repo (Kotlin + Compose + ExoPlayer)

## License

Private / unpublished. Depends on GPL components (KSPlayer) when linked.
