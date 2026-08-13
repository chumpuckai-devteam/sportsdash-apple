# Dual-platform map (iOS / tvOS / Android)

This is the compact current map. `docs/dual-platform-parity.md` owns detailed parity status.

| Area | Apple | Android |
|---|---|---|
| Source | `SportsDash/` shared by iOS/tvOS | `android/` shared by phone/TV |
| UI | SwiftUI | Jetpack Compose |
| Hard player | MobileVLCKit / TVVLCKit | libVLC 3.6.x |
| System/soft player | AVPlayer for clean HLS | None; VLC-only is intentional |
| IPTV | `IptvService` | `IptvRepository` |
| EPG | Bulk XMLTV plus automatic short-EPG gap fill | Bulk XMLTV plus automatic short-EPG gap fill |
| Scores | ESPN Live / Upcoming / Final | ESPN Live / Upcoming / Final |
| Scores favorites | Teams, league-scoped ESPN IDs | Teams, league-scoped ESPN IDs |
| Guide favorites | Channels | Channels |
| Phone pop-out | iPhone/iPad floating player | Android phone floating bar |
| TV playback | Full-screen cover; no pop-out | Full-screen player; pop-out removed on Android TV (gated by isTelevision) |
| Game alerts | Scheduled start-soon plus foreground-poll-observed alerts | App-refresh-observed alerts; no scheduler/push |
| Package ID | `com.samirpatel.sportsdash.ios` / `.tvos` | `com.samirpatel.sportsdash` |

## Dogfood

- iPhone/Apple TV: `xcodegen generate && pod install`, then open `SportsDash.xcworkspace` and choose `SportsDash` or `SportsDashTV`.
- Android phone/TV: open `android/` in Android Studio with Gradle JDK 21, then Run; the same APK advertises phone and leanback entry points.

The repository name may be simplified later, but Android is already production code in this monorepo. Do not create a separate Android repository.
