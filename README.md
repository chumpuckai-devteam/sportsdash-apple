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
| Fullscreen player (AVPlayer) | ✅ |
| LIVE jump, aspect prefs, stream list | ✅ |
| Live scores strip (sport groups, last played) | ✅ |
| Guide + short EPG (Xtream) | ✅ |
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

## Next enhancements

- KSPlayer/VLC fallback for hard TS streams  
- Deeper EPG / XMLTV  
- Apple TV focus polish  
- Android repo (Kotlin + Compose + ExoPlayer)

## License

Private / unpublished.
