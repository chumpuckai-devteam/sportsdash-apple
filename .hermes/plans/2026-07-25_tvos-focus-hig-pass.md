# tvOS focus & selection pass (S-TV.1)

**Status:** code complete on main — **Apple TV sim/device dogfood still required**  
**Board:** sportsdash · `t_0c034e64` mobile-engineer  
**Pattern:** full custom `SportsTVFocused` + `sportsTVFocusClean()` (no `.card` / no `@FocusState` hybrid on Buttons).

## Canonical pattern (one system)

```swift
Button { /* activate */ } label: {
  SportsTVFocused { focused in
    // gold fill / stroke / scale from `focused` only
  }
}
.sportsTVFocusClean() // .buttonStyle(.plain) + .focusEffectDisabled(true)
```

Helpers in `Theme/SportsColors.swift`:
- `SportsTVFocused` — `@Environment(\.isFocused)` bridge
- `sportsTVFocusClean()` — kill system white lift
- `SportsTVMetrics` — 66pt min, channel 88, score inset 56 / maxWidth 960
- `SportsTVIconButton` — circular toolbar chrome
- `SportsTVListRowLabel` — opaque sheet/list row chrome (selection ≠ focus)

**Never:** `.buttonStyle(.card)` under brand gold · `@FocusState` + `.focused($)` fighting Button focus  
**OK:** `@FocusState` only for `TextField` search chrome (category picker)

## Surfaces

| Surface | Focus chrome |
|---------|----------------|
| Guide channel name | Gold **fill** + dark type; scale 1.045; row ≥88pt; gutter 10; first row `prefersDefaultFocus` in `focusScope` |
| Guide category card / settings icon | Gold fill when focused; `focusSection` vs channel list; settings sheet uses `SportsTVListRowLabel` |
| Guide card grid play row | Gold fill + min 66pt |
| Scores game row | Gold **stroke** + panel lift; maxWidth 960; inset 56; minHeight 120; no nested star Button |
| Scores filters | **Selected** = gold fill; **focused** = ring/scale; HStack (no H-ScrollView); `focusSection` |
| Scores sport headers | Gold fill when focused |
| Scores refresh / dismiss | `SportsTVIconButton` |
| Game detail streams | `SportsTVListRowLabel` + inset; Close = `SportsTVIconButton` |
| Category picker rows | Gold fill when focused; void black canvas; searchable; Close = `SportsTVIconButton` |

## Navigation (tvOS)

- No Menu-only primary paths — sheet / fullScreenCover / in-content Button
- `focusSection` between Category ↔ channel list; filters ↔ score rows
- Guide: `focusScope` + first channel `prefersDefaultFocus`

## Acceptance criteria

- [x] Code: no `.card` / no hybrid white plate under custom gold (system lift disabled)
- [x] Guide channels ≥56–66pt (88pt rows); click activates play separately from focus move
- [x] Scores inset focus styling (stroke + scale margin)
- [x] Scores row focus distinct from filter selection chrome and sheet open (activate on click)
- [x] Filters + Category focusable without Menu
- [x] focusSection boundaries; preferred default focus on first Guide channel
- [x] ~66pt preferred hit targets via `SportsTVMetrics`
- [x] Skill ref documents final pattern
- [ ] **Device:** Apple TV sim/hardware — no white under gold screenshots
- [ ] **Device:** click-to-play Guide + click-to-open Scores; no edge clip / focus traps
- [ ] **Device:** Menu/Back restores focus to prior/default element

## Dogfood checklist (Samir / SportsDashTV)

1. Guide: swipe channels — gold only, no white plate; click plays  
2. Guide: Category card → list → Back restores near Category  
3. Guide settings ellipsis → sheet rows gold focus; Close works  
4. Scores: filters focus ≠ selected gold fill  
5. Scores: row focus stroke doesn’t clip; click opens detail  
6. Detail streams: gold focus; click plays; Close dismisses  
7. Cross Category ↔ list ↔ filters — no traps  

## Out of scope

- iOS redesign · player engine · Apple Sports 1:1 clone · superseded cards `t_ebb7ec84` / `t_1e22a51d`

## Links

- https://developer.apple.com/design/human-interface-guidelines/focus-and-selection  
- https://developer.apple.com/videos/play/wwdc2020/10042/  
- https://developer.apple.com/videos/play/wwdc2023/10162/  
- https://developer.apple.com/documentation/swiftui/view/focuseffectdisabled(_:)  
- https://developer.apple.com/documentation/swiftui/environmentvalues/isfocused  
