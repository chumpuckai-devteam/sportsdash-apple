# QA Report — Liquid Glass device dogfood (M5 / Sprint UI)

**Task:** `t_588d5db1` (follow-up after Guide CI; prior `t_6be96648` / parent AC `t_dfff529d`)  
**Date:** 2026-07-25  
**Tester:** Toad (qa-engineer)  
**Surface:** `sportsdash-apple` @ `main` `8bda9db`  
**Environment:** Linux agent (`ecda6c91d85d`) — **no Xcode / no iOS Simulator / no physical device**

---

## Verdict

| Gate | Result |
|------|--------|
| Device iOS 26+ Liquid Glass path | **NOT RUN** (no device) |
| Device pre-iOS 26 material fallback | **NOT RUN** (no device) |
| Static hierarchy re-audit | **PASS (static)** @ `8bda9db` |
| Main CI / shippable iOS binary | **PASS** — Guide fix + iOS build green |
| Screenshots / OS versions | **N/A** |
| Release-ready M5 dogfood | **NO-GO** |

**Release gate: NO-GO for device AC.**  
Compile + Guide blockers from the prior attempt are **cleared**. This host still cannot exercise real glass/material surfaces, so M5 device sign-off remains open for Samir / a Mac agent.

---

## Build SHA & CI evidence

| Ref | Note |
|-----|------|
| `388fd79` | Glass compile-gate + CI Xcode 26 select — green ([run 30162186510](https://github.com/chumpuckai-devteam/sportsdash-apple/actions/runs/30162186510)) |
| `01b4df0` | Gate restored after tvOS clobber — **red** GuideView mid-arg `#if` ([run 30162418958](https://github.com/chumpuckai-devteam/sportsdash-apple/actions/runs/30162418958)) |
| `6934ecf` | Guide mid-arg `#if` first fix — **green** ([run 30162564826](https://github.com/chumpuckai-devteam/sportsdash-apple/actions/runs/30162564826)) |
| `8bda9db` **HEAD under test** | optional `focusNamespace` always on `GuideTimelineRow` — **iOS build success** ([run 30162616780](https://github.com/chumpuckai-devteam/sportsdash-apple/actions/runs/30162616780)) |

Parent handoff `t_5cc721cf`: GuideTimelineRow takes `focusNamespace: Namespace.ID? = nil` always; grid always passes `guideFocusNS`; tvOS-only consumption via `GuideDefaultFocusModifier`.

---

## PRD Sprint UI AC — device dogfood matrix

| AC | Static (code @ `8bda9db`) | Device iOS 26+ | Device iOS 17/18 |
|----|---------------------------|----------------|------------------|
| Tab bar modern `Tab` API → system Liquid Glass on 26 | PASS — `RootTabView.mainTabs` `Tab { }` under iOS 18+ | **NOT RUN** | **NOT RUN** (legacy `tabItem` pre-18) |
| Filter chips / category menus glass or material; content opaque | PASS — chips `sportsGlass`; menus `sportsGlass`; scores groups `sportsSoftSurface`; live strip `sportsContentCard` | **NOT RUN** | **NOT RUN** |
| Game cards / channel tiles readable; LIVE/WATCH clear | PASS (static badges + panels) — contrast unverified | **NOT RUN** | **NOT RUN** |
| Settings inset grouped + AppLogo About | PASS — `.sportsInsetGroupedList()` + `Image("AppLogo")` | **NOT RUN** | **NOT RUN** |
| No full-screen glass over video or guide | PASS — player: black + surface + control `sportsGlass` + gradient scrims; guide rows panel/void; glass only settings circle | **NOT RUN** | **NOT RUN** |
| Builds iOS 17 path without hard glass dependency | PASS — `#if compiler(>=6.2)` + material fallback; **CI green** | **NOT RUN** (binary exists in CI artifacts only) | same |

---

## Implementation map (reconfirmed @ `8bda9db`)

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
| `sportsContentCard` | LiveScoresStrip tiles (call site present) |
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

### B1 — No device/simulator on QA host (this task) — **OPEN**

**Severity:** Critical (process)  
**Category:** Capability  
Cannot capture OS version, screenshots, or PASS/FAIL for glass vs material appearance. Device checklist remains mandatory for Samir / Mac agent on green SHA `8bda9db` (or later main).

### B2 — Main iOS build broken: GuideView argument `#if` — **CLOSED**

**Fixed:** `6934ecf` / `8bda9db`  
**CI:** [run 30162616780](https://github.com/chumpuckai-devteam/sportsdash-apple/actions/runs/30162616780) success  
**Verification:** `GuideTimelineRow` declares `focusNamespace: Namespace.ID? = nil`; call site passes `guideFocusNS` with no mid-list `#if`.

### B3 — tvOS focus merge clobbered glass compile gate — **CLOSED** earlier

**Fixed on:** `01b4df0` (and retained through HEAD)

---

## Device checklist (still required — Samir / Mac)

Run Debug install on **`8bda9db` or newer green main**. Record **OS version + build SHA + screenshots**.

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

- Confirmed parent Guide CI fix on `main` @ `8bda9db` with live Actions success.  
- Re-audited static glass hierarchy (controls vs content) — still PASS intent.  
- Confirmed Linux host still has zero iOS surface capability.  
- Updated this report for post-green state.

**Did not**

- Run Simulator or device.  
- Capture screenshots or OS versions.  
- Mark M5 / Sprint UI device AC done.  
- Invent PASS for appearance ACs.

---

## Follow-ups

1. **Samir / Mac QA:** Execute device checklist A/B on green SHA `8bda9db+`; comment PASS/FAIL + screenshots on `t_dfff529d` / `t_588d5db1`.  
2. Optional: keep `SportsColors` glass gate in review checklist when touching tvOS focus.

---

## Board summary

Device dogfood **cannot pass** from Linux QA host.  
Static glass hierarchy still matches HIG intent.  
`main` @ `8bda9db` **iOS CI green** — Guide mid-arg `#if` closed.  
**NO-GO** for M5 release dogfood until real device/sim evidence (screenshots + OS versions + per-AC PASS/FAIL).
