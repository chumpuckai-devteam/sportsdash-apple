# QA Report — Liquid Glass vs material fallback (M5 / Sprint UI)

**Task:** `t_dfff529d`  
**Date:** 2026-07-25  
**Tester:** Toad (qa-engineer)  
**Surface:** `sportsdash-apple` @ `main` `f4d26b4` (+ local dirty WIP not under test)  
**Environment:** Linux agent — **no Xcode / no iOS Simulator / no physical device**

---

## Verdict

| Gate | Result |
|------|--------|
| Static hierarchy vs PRD Sprint UI | **CONDITIONAL PASS** (see notes) |
| No full-screen glass over video/content | **PASS (static)** |
| Material fallback pre-iOS 26 (code path) | **PASS (static)** |
| Material fallback pre-iOS 26 (device) | **NOT RUN** |
| Liquid Glass on iOS 26+ (device) | **NOT RUN** |
| Build / CI (iOS 17 path, availability-gated glass) | **FAIL** |
| Release-ready / dogfood ship | **NO-GO** |

**Release gate: NO-GO** until (1) CI builds again on the shipping toolchain, and (2) Samir (or a Mac agent) completes the device checklist below.

---

## Specs used

- `docs/ui-liquid-glass.md`
- Sibling PRD: `/opt/data/workspace/sportsdash/PRODUCT_REQUIREMENTS.md` § Design system + § Acceptance criteria — UI / Liquid Glass (Sprint UI)
- Apple HIG materials / Liquid Glass (control layer only)

### PRD Sprint UI AC (static mapping)

| AC | Static evidence | Status |
|----|-----------------|--------|
| Tab bar uses modern `Tab` API on iOS 18+ | `RootTabView.mainTabs` — `Tab { }` under `#available(iOS 18.0, *)`, legacy `tabItem` else | PASS (static) |
| Filter chips / category menus use glass (or material fallback); content stays opaque | `SportsFilterChip` → `sportsGlass` (unselected); `SportsCategoryMenu` → `sportsGlass`; iOS scores league group → `sportsSoftSurface` / opaque panel, **not** glass | PASS (static) |
| Game cards / channel tiles readable; LIVE/WATCH clear | `SportsLiveBadge`, `SportsWatchBadge`, `GameMatchupRow`; content surfaces material/panel | PASS (static) — **device contrast not verified** |
| Settings inset grouped + AppLogo About | `SettingsView` `.sportsInsetGroupedList()` + `Image("AppLogo")` | PASS (static) |
| No full-screen glass wash over video or guide | Player: black canvas + `KSPlayerSurface`; chrome uses **control** `sportsGlass` + **opaque gradient scrims** only. Guide: glass only on settings circle control, not timeline cells | PASS (static) |
| Builds on iOS 17 path without hard glass dependency failures | CI `iOS build` on `macos-15` / **Xcode 16.4 / iPhoneSimulator 18.5 SDK** fails compiling `SportsColors.swift` | **FAIL** |

---

## Implementation map (call sites)

### Liquid Glass / control layer (`sportsGlass` → `glassEffect` iOS 26+, else `.ultraThinMaterial` + hairline)

| Location | Shape / role |
|----------|----------------|
| `Theme/SportsColors.swift` | `sportsGlass`, `sportsToolbarControl` (`.buttonStyle(.glass)` iOS 26+) |
| `Theme/SportsColors.swift` `SportsFilterChip` | Unselected chip capsule |
| `Theme/SportsCategoryMenu.swift` | Category menu label capsule (iOS) |
| `Features/Guide/GuideView.swift` | Guide settings ellipsis circle |
| `Features/Scores/GameDetailSheet.swift` | Dismiss `xmark` circle |
| `Features/Player/PlayerView.swift` | Banner, engine chip, play/pause, utility cluster, chrome icon buttons |

### Content / canvas (must not be Liquid Glass)

| API / pattern | Role |
|---------------|------|
| `sportsScreenBackground()` | Void black canvas — Scores, Settings |
| `sportsSoftSurface` | iOS scores league group fill (material + panel wash) |
| `GameScoreFocusRow` panel fill | Opaque elevated rows (esp. tvOS focus) |
| `sportsContentCard` | **Defined in Theme — zero call sites** (docs still claim game cards use it) |
| Player top/bottom chrome | `LinearGradient` scrims — not glass full-bleed |
| Settings rows | `SportsColors.panel` list row backgrounds |

### Fallback (pre-iOS 26)

```swift
// SportsColors.sportsGlass
#if os(iOS)
if #available(iOS 26.0, *) {
    self.glassEffect(in: shape)
} else {
    self.background(.ultraThinMaterial, in: shape)
        .overlay(shape.stroke(...))
}
#else
// tvOS: material only
#endif
```

Runtime branch is correct **if** the binary builds. Compile-time is not.

---

## Blocking bug — CI cannot compile glass APIs on Xcode 16.4

**Severity:** Critical (release / AC)  
**Category:** Functional / Build  
**Evidence:** GitHub Actions run  
https://github.com/chumpuckai-devteam/sportsdash-apple/actions/runs/30144090526  

```
SportsColors.swift:49:18: error: value of type 'Self' has no member 'glassEffect'
SportsColors.swift:114:31: error: reference to member 'glass' cannot be resolved without a contextual type
```

**Root cause:** `#available(iOS 26.0, *)` only gates **runtime**. The type checker still needs `glassEffect` / `ButtonStyle.glass` in the **SDK**. CI uses Xcode 16.4 + iOS 18.5 Simulator SDK — symbols absent → every main build since glass land is red (all sampled runs `failure`).

**Expected:** PRD: “Builds on iOS 17 SDK path without hard dependency failures (availability-gated glass).” Docs also say compile with an Xcode that knows `glassEffect`.

**Actual:** Main does not build on the project’s CI toolchain.

**Fix direction (for mobile-engineer — not applied here):**
1. Prefer SDK/compiler guards so older Xcode only sees the material path, e.g. wrap glass branches in a compile-time check tied to the iOS 26 SDK / Xcode that ships it; **or**
2. Bump CI to an Xcode that includes Liquid Glass APIs and keep runtime `#available`; **and**
3. Keep deployment target iOS 17 with material fallback.

---

## Medium findings (non-blocking for hierarchy, still track)

### M1 — `sportsContentCard` dead API / docs drift
- **Expected:** Docs + PRD content layer = `sportsContentCard` on game cards / channel tiles.
- **Actual:** Helper exists; **no call sites**. Scores use `sportsSoftSurface` + panel rows (still non-glass — hierarchy OK).
- **Risk:** Future contributors may reintroduce glass on content thinking `sportsContentCard` is live; docs lie.
- **Action:** Wire cards to `sportsContentCard` **or** update docs/PRD to `sportsSoftSurface` / panel tokens.

### M2 — Player residual glass now partially shipped
- Sprint plan listed “Player chrome glass” as follow-up; `PlayerView` already uses `sportsGlass` on floating controls with gradient scrims.
- Hierarchy looks correct statically; still needs **device** check over live video (legibility, stacking, no wash).

### M3 — Dirty worktree unrelated to this gate
- Uncommitted: `SportsAPI.swift`, `ScoresView.swift` (sport collapse / multi-day ESPN).
- **Not** included in this verdict; do not mix into a “glass QA pass” commit.

---

## Device dogfood checklist (required — Samir / Mac)

Cannot execute from this Linux agent. Run Debug build from device after CI/compile is fixed.

### A. iOS 26+ (Liquid Glass path)

1. Cold launch → splash → Scores.  
2. **Tabs:** system tab bar shows Liquid Glass chrome (not a custom full-width glass slab).  
3. **Scores:** unselected filter chips look glassy; selected = gold fill.  
4. League groups = soft material/opaque — **not** the same glass as chips.  
5. Open game detail → dismiss control glass; sheet background void/opaque.  
6. **Guide:** category menu glass; timeline/list cells **not** glass-washed.  
7. **Player:** play a stream; floating controls glass; **video remains clear** (no full-screen glass overlay). Toggle chrome hide/show.  
8. **Settings:** inset grouped, AppLogo About, void behind list.

### B. Pre-iOS 26 (material fallback) — iOS 17 or 18 device/sim

1. Same flows as A.  
2. Chips/menus/toolbar use **ultraThinMaterial + hairline**, not missing backgrounds.  
3. No runtime crash on glass APIs.  
4. Player controls still legible over video via material + scrim.

### C. Capture

- Screenshots: Scores chips, one game group, Guide, Player chrome over live frame, Settings About.  
- Note OS version + build SHA.  
- Comment results on kanban `t_dfff529d` to unblock final AC.

---

## What was committed already

Glass design system already on `main` (not produced by this QA run):

- `d670d26` feat(ui): Liquid Glass design system…  
- `b1eebf4` polish(ui): content cards use standard materials…  
- Later: scores polish, player chrome glass controls, tvOS focus series  

**No new commit from this QA run** — failing CI + no device evidence; committing a “pass” would be dishonest. Dirty local Scores/API WIP left untouched.

---

## Follow-ups spawned

1. **mobile-engineer:** Fix compile-time glass gating / CI Xcode so `main` builds (Critical).  
2. **qa-engineer or Samir:** Device checklist A/B after green build.  
3. Optional: docs drift `sportsContentCard` vs `sportsSoftSurface`.

---

## Summary for board

Static audit: control-layer glass + opaque/material content + no full-screen video glass **matches HIG intent**.  
**Cannot pass M5 device AC** from this host.  
**CI Critical fail** on `glassEffect` / `.glass` under Xcode 16.4 blocks “committed healthy main” and pre-26 build AC.  
**NO-GO** for release dogfood until compile fixed + device checklist signed off.
