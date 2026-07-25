# tvOS focus & selection pass (later)

**Status:** implemented on main `47148be` — **device dogfood review required**  
**Board:** sportsdash · `t_0c034e64` mobile-engineer  
**Pattern:** full custom `SportsTVFocused` + `sportsTVFocusClean()` (no `.card` / no `@FocusState` hybrid).

## Problem (dogfood)

| Surface | Issue |
|---------|--------|
| Guide channel cells | System **white** focus plate behind/around **gold** custom fill; hard to read |
| Scores rows | `.buttonStyle(.card)` **scale** clips edges; white plume |
| Filters / menus | Early: Menu dead under Siri Remote; plain chips in H-ScrollView not focusable |
| Category picker | Needed opaque fullScreenCover list, not translucent toolbar Menu |

Partial mitigations on `main`: `sportsTVFocusClean()`, gold fill/stroke, Category fullScreenCover, inset score cards, icon-only Refresh. **Still not HIG-quality.**

## Apple guidance (official)

### HIG — [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)

- Focus shows **what interaction targets**; on tvOS, **focusing ≠ activating** — click/select is a **separate** gesture.
- **Design for multiple focus states** (up to five on tvOS). Focused items often **increase scale** — supply sharp assets and **don’t let larger focused items crowd** neighbors (padding/margins).
- Full-screen content: gestures affect content, not focus chrome.
- Prefer **focus model** over free-form pointer for menus/grids.

### HIG — Accessibility (control size)

- tvOS recommended control size **66×66 pt** (min **56×56**). Channel cells and chips should meet this.

### SwiftUI / WWDC

| Source | Takeaway |
|--------|----------|
| [Build SwiftUI apps for tvOS (WWDC20)](https://developer.apple.com/videos/play/wwdc2020/10042/) | `@Environment(\.isFocused)` even on non-focusable children; `prefersDefaultFocus` |
| [SwiftUI cookbook for focus (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10162/) | tvOS default for **Button/NavigationLink** = **lift hover effect**; text+image cells suit **lift**; artwork grids can use **`.hoverEffect(.highlight)`** (tvOS 17+). **`focusSection()`** for adjacent groups (filters ↔ list). |
| Forums / `focusEffectDisabled` | Custom focus is possible; **Button still often paints system material**; order of `.focusable` / `.focused` / `.focusEffectDisabled` matters; pure disable is imperfect on some OS versions. |

### Materials (related)

- [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials): Liquid Glass = **control layer**; content uses **standard materials**. Focus chrome is control/selection, not full-screen glass wash.

## Recommended product approach (when unblocked)

1. **Canonical pattern per control type**
   - **Primary actions** (play channel, open game): `Button` / `NavigationLink` with **intentional** hover effect — prefer **system lift** *or* fully custom via `@Environment(\.isFocused)` on label, not half-disabled Button + gold fight.
   - **If custom gold brand focus:** build **label-driven** chrome from `isFocused`; disable system effect only when verified on **tvOS 17–18 simulator + device**; clipShape matching focus shape; **never** full-bleed white behind gold.
   - **Avoid** full-width `.buttonStyle(.card)` on list rows (scale + white + edge clip).

2. **Guide list**
   - Channel column: focusable row meeting **≥56–66pt** height; clear focused vs unfocused (scale *or* gold stroke/fill — pick one system, document).
   - Program strip: decide focus model — channel-only select vs program cells (`focusSection` between name column and strip).
   - Preferred focus on appear: first channel or last-played.

3. **Scores**
   - Inset cards (already ~maxWidth 980); focus = **gold stroke + slight scale** with **padding so scale doesn’t clip**.
   - Filters: keep HStack + `focusSection()`; selected filter distinct from focus (selection ≠ focus per HIG).

4. **Chrome**
   - No Menu-only TV controls; keep sheet / fullScreenCover / NavigationLink lists.
   - Toolbar: icon-only actions with `accessibilityLabel`.

5. **Verify**
   - Simulator + hardware: swipe paths, click-to-play, Menu back restores focus.
   - No focus traps (filters ↔ list ↔ category card).
   - Screenshot AC: no white plate under gold.

## Out of scope for that card

- iOS-only chrome
- Player engine / KSPlayer thrash
- Cloning Apple Sports 1:1 layout

## Code touchpoints

- `GuideView.swift` — `GuideTimelineRow` channel cell
- `ScoresView.swift` / `GameScoreFocusRow`
- `Theme/SportsColors.swift` — `sportsTVFocusClean()`
- `SportsCategoryMenu.swift` / picker screen
- `references/tvos-focus-and-apis.md` (skill)

## Links

- https://developer.apple.com/design/human-interface-guidelines/focus-and-selection  
- https://developer.apple.com/videos/play/wwdc2020/10042/  
- https://developer.apple.com/videos/play/wwdc2023/10162/  
- https://developer.apple.com/documentation/swiftui/view/focuseffectdisabled(_:)  
- https://developer.apple.com/documentation/swiftui/environmentvalues/isfocused  
