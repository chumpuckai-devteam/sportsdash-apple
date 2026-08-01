# Dual-platform map (iOS / tvOS / Android)

| | Apple | Android |
|--|--------|---------|
| Path | repo root (`SportsDash/`, XcodeGen, CocoaPods) | `android/` |
| UI | SwiftUI | Jetpack Compose |
| Hard player | MobileVLCKit / TVVLCKit | `libvlc-all` 3.6.x |
| Soft player | AVPlayer (HLS) | (VLC for now; Exo optional later) |
| IPTV | `IptvService` | `IptvRepository` |
| EPG | bulk xmltv.php + short | TBD |
| Scores | ESPN | TBD |
| Package id | `com.samirpatel.sportsdash.ios` / `.tvos` | `com.samirpatel.sportsdash` |

## Dogfood

- **iPhone:** `xcodegen` → `pod install` → open **`.xcworkspace`**  
- **Android:** Android Studio → open **`android/`** → Run  

## Repo rename (later)

When Android is real, rename `sportsdash-apple` → `sportsdash`. No rush.
