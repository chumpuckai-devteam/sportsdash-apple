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
| Fullscreen player (**VLC** + **AVKit**) | ✅ Path A |
| Engine picker (Auto / VLC / AVKit) | ✅ |
| LIVE jump, aspect prefs | ✅ |
| Live scores strip | ✅ |
| Guide timeline + card grid | ✅ |
| Movie ratings (OMDb/TMDB) | ✅ |

## Open / run

```bash
cd sportsdash-apple
git pull origin main
brew install xcodegen          # once
xcodegen generate              # REQUIRED after pull — refreshes packages
open SportsDash.xcodeproj
```

In Xcode:
1. Wait for **package resolve** (VLCKit SPM is a large binary — first time can take several minutes)
2. Signing → your Team
3. Run on your **iPhone**

If you still see `No such module 'MobileVLCKit'` or old **FFmpegKit** warnings:
- You opened a stale project. Run `xcodegen generate` again, then **File → Packages → Reset Package Caches**, then resolve.
- Delete DerivedData for SportsDash if needed.

## Video engines (Path A)

| Setting | Behavior |
|---------|----------|
| **Auto (default)** | Clean `.m3u8` → AVKit first; TS / hard IPTV → VLC first; swap on failure |
| **VLC** | libVLC via [vlckit-spm](https://github.com/tylerjonesio/vlckit-spm) (LGPL) |
| **AVKit** | Native AVPlayer — clean HLS, system routes |

**KSPlayer / FFmpegKit removed** (GPL + package friction).

LGPL notes: `docs/LGPL-NOTICE.md` · decision brief: `docs/video-player-options.md`

## License

Private app code. Third-party: VLCKit LGPL (VideoLAN).
