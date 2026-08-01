# SportsDash UI — Liquid Glass & modern SwiftUI

## Intent
Modernize chrome to match Apple’s iOS 26 design language while remaining usable on iOS 17–18.

## Hierarchy (HIG)
Liquid Glass is for **controls and navigation** floating above content — not for lists, video, or full-screen fills.

| Token / API | Use |
|-------------|-----|
| `sportsGlass(in:)` | Chips, menu labels, circular toolbar controls |
| `sportsContentCard` | Game cards, channel tiles — **opaque elevated panels** (not Liquid Glass) |
| `sportsScreenBackground()` | Void canvas |
| `Tab { }` (iOS 18+) | System tab bar → Liquid Glass on iOS 26 |
| `.buttonStyle(.glass)` | When available via `sportsToolbarControl()` |
| Native `Menu` | Categories, guide layout |

### Content cards vs Liquid Glass

Apple HIG ([Materials](https://developer.apple.com/design/human-interface-guidelines/materials)):

- **Liquid Glass** = functional layer for **controls/navigation** floating above content (tab bar, toolbars).  
- **Don’t** put Liquid Glass on content cards — hierarchy gets muddy and contrast suffers.  
- **Do** keep content cards **opaque elevated panels** (brand `panel` / `panelElevated`) so scores stay readable over void canvas and live video.

SportsDash game cards use `sportsContentCard`: solid elevated fill + hairline edge + soft shadow. LIVE / current cards get a light mint stroke only — no thick box border, no glass wash.

## Apple docs
- https://developer.apple.com/documentation/technologyoverviews/liquid-glass  
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass  
- https://developer.apple.com/design/human-interface-guidelines/materials  
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)  
- https://developer.apple.com/documentation/swiftui/tab  

## Implementation map
| File | Role |
|------|------|
| `Theme/SportsColors.swift` | Tokens + glass/content helpers + chips/menus |
| `App/RootTabView.swift` | `Tab` API + splash |
| `Features/Scores/*` | Filter chips, game cards, snappy shelves |
| `Features/Channels/ChannelsView.swift` | Category menu + tiles |
| `Features/Guide/GuideView.swift` | Category + settings menus |
| `Features/Settings/SettingsView.swift` | Grouped list + About logo |
| `Features/Player/PlayerView.swift` | Fullscreen floating control chrome (`sportsGlass` buttons/capsules); gradient scrims only over video |
| `Features/Player/FloatingPlayerView.swift` | Mini-player transport / close / expand glass controls |
| `Features/Player/LiveScoresStrip.swift` | Opaque content cards (`sportsContentCard`); no glass wash |

## Fallback
On OS &lt; 26, glass calls use `.ultraThinMaterial` + hairline border via `sportsGlassMaterialFallback`.

**Compile vs runtime**
- Runtime: `#available(iOS 26.0, *)` chooses glass vs material when the binary was built with an iOS 26+ SDK.
- Compile: `glassEffect` / `.buttonStyle(.glass)` are wrapped in `#if compiler(>=6.2)` (Xcode 26+ / Swift 6.2+) so **Xcode 16.4 / iOS 18.5 SDK still typechecks** — older toolchains only see the material path.
- CI (`.github/workflows/ios.yml`) selects Xcode 26.x on `macos-15` when present so main builds exercise the glass symbols.

## Do not
- Apply glass to guide timeline cells or the video surface  
- Stack multiple glass layers on top of each other  
- Drop `Assets.xcassets` from XcodeGen sources again  

## Scores dashboard (Apple Sports–inspired, not a clone)

Reference UX cues only — no Apple Sports assets/trademarks:

| Cue | SportsDash approach |
|-----|---------------------|
| Vertical league list | Grouped soft surface + hairline dividers (no bordered cards) |
| Big scores / team marks | `GameMatchupRow` + `TeamMarkView` (logo or monogram) |
| Detail sheet bottom-up | System `.sheet` + large detent |
| Team color wash on detail | `TeamTheme.heroGradient` from stable hash of team id (not scraped brand kits) |
| IPTV identity | Gold **WATCH** on matched streams |

HIG still applies: Liquid Glass on chrome; content uses materials/soft surfaces.
