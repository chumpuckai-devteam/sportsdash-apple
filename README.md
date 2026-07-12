# SportsDash (Apple)

Native **SwiftUI** app for **iOS** and **Apple TV (tvOS)**.

This is the production Apple codebase. The Flutter prototype remains available for reference:

- Flutter: https://github.com/chumpuckai-devteam/sportsdash  
- Android (Kotlin/Compose) will be a separate repo later.

## Stack

| Layer | Choice |
|--------|--------|
| Language | Swift 5 |
| UI | SwiftUI (shared iOS + tvOS sources) |
| Scores | ESPN public scoreboards (`URLSession`) |
| IPTV | M3U + Xtream (v1 loaders) |
| Matching | Port of Flutter `MatchingService` (v1) |
| Player | `AVPlayer` placeholder → KSPlayer/VLC fallback planned |

## Requirements

- macOS with **Xcode 16+** (project uses iOS 17 / tvOS 17 deployment)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the project if needed

## Open in Xcode

```bash
cd sportsdash-apple
xcodegen generate   # if .xcodeproj missing or after Project.yml edits
open SportsDash.xcodeproj
```

1. Select the **SportsDash** scheme (iPhone) or **SportsDashTV** (Apple TV).
2. **Signing & Capabilities** → choose your Team.
3. Change bundle IDs if needed (`com.sportsdash.ios` / `com.sportsdash.tvos`).
4. Run on a **physical iPhone** for IPTV audio reliability (Simulator is limited).

### CLI run

```bash
xcodebuild -scheme SportsDash -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# Or open Xcode and Run (⌘R)
```

## Project layout

```
SportsDash/
  App/                 # Entry + tab shell + AppModel
  Core/
    Models/            # Game, SportLeague, IPTV types
    Services/          # SportsAPI, IptvService
    Matching/          # MatchingService
  Features/
    Scores/            # Sport → league shelves
    Channels/
    Guide/             # Placeholder
    Settings/
    Player/            # AVPlayer placeholder
  Theme/
```

## Roadmap

1. ✅ Project scaffold + scores API + tab shell  
2. ⬜ Keychain IPTV persistence  
3. ⬜ Full player (LIVE jump, aspect, decoder options, live scores strip)  
4. ⬜ Guide / EPG  
5. ⬜ Apple TV focus polish  
6. ⬜ Android port (separate repo)

## Architecture notes

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

Private / unpublished.
