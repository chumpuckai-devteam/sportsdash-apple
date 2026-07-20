# SportsDash Apple architecture

## Goals

- Native performance and platform players (AVPlayer / KSPlayer later).
- One shared SwiftUI codebase for **iPhone** and **Apple TV**.
- Keep product parity with Flutter prototype without depending on it at runtime.

## Modules (logical)

| Area | Responsibility |
|------|----------------|
| **App** | Lifecycle, `AppModel`, tabs |
| **Core/Models** | `Game`, `SportLeague`, IPTV types |
| **Core/Services** | ESPN, playlist loaders, EPG |
| **Core/Matching** | Stream ranking (port from Flutter) |
| **Features/** | UI per surface |
| **Theme** | Brand colors |
| **Future: Movie ratings** | Resolve now-playing EPG movie title → external ratings (RT-style critic/audience); cache; never block playback |

Future: extract **SportsDashCore** SPM package shared by iOS/tvOS if targets diverge.

## Scoreboard organization

```
Sport section (Soccer, Baseball, …)
  └── League shelf (Premier League, MLB, …)
        └── Horizontal game cards
```

## Player plan

1. **Now:** `AVPlayer` via `VideoPlayer` for simple HLS.  
2. **Next:** Native player chrome — LIVE edge, aspect, scores strip.  
3. **Hard streams:** KSPlayer or VLCKit fallback behind a protocol `StreamPlaying`.

## Android port later

Repo: `sportsdash-android` (Kotlin + Compose + Media3).  
Reuse this doc’s product rules (matching, shelves, player UX)—not Swift code.

## Flutter prototype

https://github.com/chumpuckai-devteam/sportsdash  

Use for matching edge cases, EPG notes, and UX reference only.
