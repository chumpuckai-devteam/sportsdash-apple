# QA Report — Liquid Glass device dogfood (M5 / Sprint UI)

**Task:** `t_6be96648` (child of `t_dfff529d`, `t_8385cedb`)  
**Date:** 2026-07-25  
**Tester:** Toad (qa-engineer)  
**Surface:** `sportsdash-apple` @ `main` `01b4df0`  
**Environment:** Linux agent (`ecda6c91d85d`) — **no Xcode / no iOS Simulator / no physical device**

---

## Verdict

| Gate | Result |
|------|--------|
| Device iOS 26+ Liquid Glass path | **NOT RUN** (no device) |
| Device pre-iOS 26 material fallback | **NOT RUN** (no device) |
| Static hierarchy re-audit (post compile-gate restore) | **PASS (static)** |
| Main CI / shippable binary | **FAIL** (GuideView syntax) |
| Screenshots / OS versions | **N/A** |
| Release-ready M5 dogfood | **NO-GO** |

**Release gate: NO-GO.** Compile-gate for glass is restored on `01b4df0`, but `main` still does not produce a green iOS binary (Guide timeline `#if` argument), and this host cannot exercise real glass/material surfaces.

---

## Build SHA & CI evidence

| Ref | Note |
|-----|------|
| `388fd79` | Glass compile-gate + CI Xcode 26 select — **CI green** ([run 30162186510](https://github.com/chumpuckai-devteam/sportsdash-apple/actions/runs/30162186510)) |
| `47148be` | tvOS S-TV.1 focus pass — **clobbered** glass `#if compiler(>=6.2)` gate in `SportsColors.swift` |
| `cd67bf6` | docs only — **CI red** GuideView `#if os(tvOS)` inside `GuideTimelineRow(` args ([run 30162253474](https://github.com/chumpuckai-devteam/sportsdash-apple/actions/runs/30162253474)) |
| `01b4df0` **HEAD under test** | `fix(ui): restore Liquid Glass compile gate after tvOS focus merge` — gate present again; CI in flight / expected red until GuideView fixed |

CI log (cd67bf6, Xcode 26.3 / iPhoneSimulator 26.2 SDK):

```
GuideView.swift:711:29: error: expected ')' in expression list
#if os(tvOS)
GuideView.swift:712:29: error: expected expression
, focusNamespace: guideFocusNS
```

Root cause: Swift does not allow `#if` between call arguments. tvOS focus wiring broke **iOS** compile even though the flag is tvOS-only.

---

## PRD Sprint UI AC — device dogfood matrix

| AC | Static (code) | Device iOS 26+ | Device iOS 17/18 |
|----|---------------|----------------|------------------|
| Tab bar modern `Tab` API → system Liquid Glass on 26 | PASS — `RootTabView.mainTabs` `Tab { }` under iOS 18+ | **NOT RUN** | **NOT RUN** (legacy `tabItem` pre-18) |
| Filter chips / category menus glass or material; content opaque | PASS — chips `sportsGlass`; menus `sportsGlass`; scores groups `sportsSoftSurface`; live strip `sportsContentCard` | **NOT RUN** | **NOT RUN** |
| Game cards / channel tiles readable; LIVE/WATCH clear | PASS (static badges + panels) — contrast unverified | **NOT RUN** | **NOT RUN** |
| Settings inset grouped + AppLogo About | PASS — `.sportsInsetGroupedList()` + `Image("AppLogo")` | **NOT RUN** | **NOT RUN** |
| No full-screen glass over video or guide | PASS — player: black + `KSPlayerSurface` + control `sportsGlass` + gradient scrims; guide rows panel/void, glass only on settings circle | **NOT RUN** | **NOT RUN** |
| Builds iOS 17 path without hard glass dependency | PASS path in source (`#if compiler(>=6.2)` + material fallback) | **blocked by GuideView CI fail on main** | same |

---

## Implementation map (reconfirmed @ `01b4df0`)

### Control layer — `sportsGlass` / toolbar glass

| Site | Role |
|------|------|
| `Theme/SportsColors.swift` | `sportsGlass` + `sportsGlassMaterialFallback`; `sportsToolbarControl` `.buttonStyle(.glass)` under `compiler(>=6.2)` + `#available(iOS 26.0, *)` |
| `SportsFilterChip` | Unselected iOS chip capsule glass |
| `SportsCategoryMenu` | Category menu label capsule |
| `GuideView` | Settings ellipsis circle only |
| `GameDetailSheet` | Dismiss `xmark` circle |
| `PlayerView` / `FloatingPlayerView` | Floating transport / utility controls |

### Content / canvas — must stay non-Liquid-Glass

| Pattern | Role |
|---------|------|
| `sportsScreenBackground()` | Void canvas (Scores, Settings) |
| `sportsSoftSurface` | Scores league groups / detail panels |
| `sportsContentCard` | **LiveScoresStrip** tiles (call site present) |
| Player scrims | `LinearGradient` only — not full-bleed glass |
| Guide timeline | `SportsColors.panel` / void — not glass cells |

### Fallback contract

```swift
#if os(iOS)
#if compiler(>=6.2)
if #available(iOS 26.0, *) {
    self.glassEffect(in: shape)
} else {
    self.sportsGlassMaterialFallback(in: shape)
}
#else
self.sportsGlassMaterialFallback(in: shape)
#endif
#else
self.sportsGlassMaterialFallback(in: shape)
#endif
```

---

## Blocking issues for M5 device sign-off

### B1 — No device/simulator on QA host (this task)

**Severity:** Critical (process)  
**Category:** Capability  
Cannot capture OS version, screenshots, or PASS/FAIL for glass vs material appearance. Device checklist remains mandatory for Samir / Mac agent after green build.

### B2 — Main iOS build broken: GuideView argument `#if`

**Severity:** Critical (build)  
**Category:** Functional / Build  
**File:** `SportsDash/Features/Guide/GuideView.swift` ~702–714  

**Expected:** iOS target compiles on CI (Xcode 26.3 path).  
**Actual:** `#if os(tvOS)` injected mid-argument-list → parse errors on iOS.  

**Fix direction (mobile-engineer):** split call sites or pass optional `focusNamespace: Namespace.ID? = nil` without mid-list `#if`; keep tvOS focus behavior.

### B3 — Regression class: tvOS focus merge clobbered glass compile gate

**Severity:** High (process)  
**Fixed on:** `01b4df0`  
**Lesson:** `SportsColors.swift` is shared chrome — tvOS edits must preserve `compiler(>=6.2)` glass branches.

---

## Device checklist (still required — Samir / Mac)

Run Debug install **after** B2 is green. Record **OS version + build SHA + screenshots**.

### A. iOS 26+ (Liquid Glass)

1. Cold launch → splash → Scores.  
2. Tab bar = **system** Liquid Glass (not custom full-width glass slab).  
3. Unselected filter chips glassy; selected = gold fill.  
4. League groups soft material/opaque — not chip glass.  
5. Game detail dismiss control glass; sheet void/opaque.  
6. Guide: category/settings chrome glass; **timeline cells not glass-washed**.  
7. Player: stream playing; floating controls glass; **video clear**; chrome hide/show.  
8. Settings: inset grouped, AppLogo About, void behind list.

### B. Pre-iOS 26 (17 or 18)

1. Same flows.  
2. Chips/menus/toolbar = **ultraThinMaterial + hairline**, not missing chrome.  
3. No crash on glass symbols.  
4. Player controls legible over video (material + scrim).

### C. Capture set

Scores chips · one league group · Guide · Player over live frame · Settings About.

---

## What this run did / did not do

**Did**

- Re-audited hierarchy after parent compile fix + gate restore.  
- Verified CI history: only `388fd79` green in recent glass window; HEAD blocked by GuideView.  
- Confirmed glass call sites remain control-layer; content uses material/panel.  
- Documented residual device checklist.

**Did not**

- Run Simulator or device.  
- Capture screenshots.  
- Mark M5 / Sprint UI AC done.  
- Implement GuideView fix (out of scope — mobile-engineer).

---

## Follow-ups

1. **mobile-engineer:** Fix `GuideView` mid-argument `#if` so iOS CI is green again.  
2. **Samir / Mac QA:** Execute device checklist A/B on green SHA; comment PASS/FAIL on `t_dfff529d` / this card.  
3. Optional: keep `SportsColors` glass gate in review checklist when touching tvOS focus.

---

## Board summary

Device dogfood **cannot pass** from Linux QA host.  
Static glass hierarchy still matches HIG intent.  
`main` @ `01b4df0` has glass compile-gate restored but **iOS build still red** on GuideView tvOS `#if` syntax.  
**NO-GO** for M5 release dogfood until green binary + real device/sim evidence.
