# SportsDash Apple architecture

## Goals

- Native performance and platform features (AVPlayer PiP / AirPlay path).
- One shared SwiftUI codebase for **iPhone** and **Apple TV**.
- Hard IPTV engine without GPL App Store risk (**VLCKit**, Path A).

## Modules (logical)

| Area | Responsibility |
|------|----------------|
| **App** | Lifecycle, `AppModel`, tabs |
| **Core/Models** | `Game`, `SportLeague`, IPTV types, `MovieRating` |
| **Core/Services** | ESPN, playlist loaders, EPG, movie ratings |
| **Core/Matching** | Stream ranking |
| **Features/** | UI per surface |
| **Features/Player** | `PlaybackController` (VLC + AV), surfaces, chrome |
| **Theme** | Brand colors |

## Player plan (Path A — current)

```
PlaybackController
├── Auto router (URL + prefs)
├── VLCKit (MobileVLCKit / TVVLCKit) — hard TS / messy HLS
└── AVPlayer + AVPlayerLayer — clean HLS
PlayerSurface switches drawable by activeEngine
```

1. **Primary hard engine:** VLCKit via CocoaPods.  
2. **System engine:** AVFoundation AVPlayer.  
3. **Protocol shape:** keep chrome on `PlaybackController`; engines are swappable.

KSPlayer / FFmpegKit removed (GPL + SPM friction). See `docs/video-player-options.md`.

## Scoreboard organization

```
Sport section (Soccer, Baseball, …)
  └── League shelf (Premier League, MLB, …)
        └── Horizontal game cards
```

## Android port later

Repo: `sportsdash-android` (Kotlin + Compose + Media3).  
Reuse product rules (matching, shelves, player UX)—not Swift code.

## Flutter prototype

https://github.com/chumpuckai-devteam/sportsdash  

Use for matching edge cases, EPG notes, and UX reference only.
