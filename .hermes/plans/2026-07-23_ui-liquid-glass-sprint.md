# SportsDash Liquid Glass UI — Sprint plan

> **For Hermes:** implement remaining residual tasks task-by-task; UI-first (player/perf later).

**Goal:** Ship modern Apple navigation chrome (Liquid Glass where available) + clearer content cards across Scores, Channels, Guide, Settings.

**Architecture:** Shared design tokens in `SportsColors.swift`; glass only on control layer; opaque content cards; iOS 18 `Tab` API.

**Tech:** SwiftUI, iOS 17 deployment, iOS 26 glass APIs availability-gated.

## Done in first ship (this commit)
- Design system helpers + chips/menus  
- RootTab `Tab` API  
- Scores filters/cards  
- Channels cards + category menu  
- Guide menus glass  
- Settings About logo + grouped list  
- PRD + `docs/ui-liquid-glass.md`  

## Follow-ups (kanban)
1. ~~Player chrome: glass floating controls (pause/PiP/close) without covering video with full-screen glass~~ shipped S-UI.5  
2. Guide card rows: content-card styling pass (still opaque)  
3. Sheet presentations: consistent detents + material  
4. QA dogfood checklist on device (iOS 26 glass vs material fallback)  

## Verify
```bash
git pull && xcodegen generate && open SportsDash.xcodeproj
# Run on iPhone — Scores chips, category menus, tabs, Settings logo
```
