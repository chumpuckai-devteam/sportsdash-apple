# SportsDash UI — Liquid Glass & modern SwiftUI

## Intent
Modernize chrome to match Apple’s iOS 26 design language while remaining usable on iOS 17–18.

## Hierarchy (HIG)
Liquid Glass is for **controls and navigation** floating above content — not for lists, video, or full-screen fills.

| Token / API | Use |
|-------------|-----|
| `sportsGlass(in:)` | Chips, menu labels, circular toolbar controls |
| `sportsContentCard` | Game cards, channel tiles (opaque) |
| `sportsScreenBackground()` | Void canvas |
| `Tab { }` (iOS 18+) | System tab bar → Liquid Glass on iOS 26 |
| `.buttonStyle(.glass)` | When available via `sportsToolbarControl()` |
| Native `Menu` | Categories, guide layout |

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

## Fallback
On OS &lt; 26, glass calls use `.ultraThinMaterial` + hairline border. Compile with a current Xcode that knows `glassEffect` (iOS 26 SDK); runtime availability gates execution.

## Do not
- Apply glass to guide timeline cells or the video surface  
- Stack multiple glass layers on top of each other  
- Drop `Assets.xcassets` from XcodeGen sources again  
