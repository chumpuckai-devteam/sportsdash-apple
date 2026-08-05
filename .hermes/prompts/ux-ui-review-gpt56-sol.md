# SportsDash comprehensive UX/UI review (gpt-5.6-sol)

You are a senior product designer + mobile UX reviewer specializing in sports apps and live IPTV players (iOS SwiftUI + Android Compose).

## Mission
Produce a **comprehensive UX/UI review** of the SportsDash product as implemented in this repo, grounded in:
1. The **inspiration / sample analysis** Samir provided earlier (catalog below + on-disk notes).
2. The **shipped sketches and product choices** (A+D direction).
3. **Current code + docs** in `/opt/data/workspace/sportsdash-apple` (iOS `SportsDash/`, Android `android/`, `sketches/`, `docs/`).

**Deliverable (required):** write a single markdown report to:

```text
/opt/data/workspace/sportsdash-apple/docs/ux-ui-review-2026-08-gpt56-sol.md
```

Do real file reads. Do **not** invent file paths. Cite concrete screens/components (Swift/Kotlin file names) when critiquing.

When done, print only:
- Absolute path of the report
- 8–12 bullet executive summary

## Product identity (do not fight this)
- **SportsDash** = Guide-first IPTV + ESPN scores dashboard (not a cable clone, not a news app).
- Tabs: **Scores · Guide · Settings** only.
- Brand: **void black + gold + live mint**. Steal **structure** from references — **never** ESPN/CBS/NFL/NBA trademarks or 1:1 visual clones.
- Hard player: **VLC / libVLC** both platforms.
- Favorites: **teams only** (not favorite-games). Channel ★ separate in Guide.
- Android phone-first; TV shells deferred.
- Parity freeze: both platforms same baseline before net-new features.

## Canonical inspiration notes (READ THESE FIRST)
You **must** open and use:

1. `/opt/data/skills/software-development/sportsdash-continue-shipping/references/ui-inspiration-samples.md`  
   — Catalog of ESPN, CBS, NFL, Bleacher Report, NBA, Smarters, IPTVx, Chillio patterns; sketches A–D; **Samir pick A+D**.
2. `/opt/data/skills/software-development/sportsdash-continue-shipping/references/ios-android-parity-ad.md` (if present)
3. `/opt/data/skills/software-development/sportsdash-continue-shipping/references/ui-liquid-glass.md`
4. `/opt/data/skills/software-development/sportsdash-continue-shipping/references/scores-dashboard-chrome.md` (if present)
5. `/opt/data/skills/software-development/sportsdash-continue-shipping/references/android-player-ticker.md` (if present)
6. `/opt/data/workspace/sportsdash-apple/docs/dual-platform-parity.md`
7. `/opt/data/workspace/sportsdash-apple/docs/ui-liquid-glass.md`
8. Interactive sketches hub: `/opt/data/workspace/sportsdash-apple/sketches/index.html` and variants `001`–`004` (structure only).

### Sample → product mapping (from prior analysis)
| Source | Patterns we extracted | SportsDash mapping |
|--------|----------------------|--------------------|
| ESPN | Faves rail, My Games first, dense rows, Watch pill | Scores A |
| CBS | Date strip, collapse leagues, 2-up grid, fave tiles | Collapse kept; not pure B |
| NFL | Top multi-game ticker while watching | Player D |
| Bleacher Report | Following logo grid + edit | Fave rail / picker |
| NBA | Symmetric matchup, center status, stream under row | Partial (WATCH / logos) |
| Smarters / IPTVx / Chillio | Player chrome, mini-player+guide, options sheet | Live cut: Back, mute, rejoin, ticker, pop-out |

**Samir pick:** Scores **A** + Player **D** + logos + Sport→League→Team favorite picker. Subsequent dogfood tightened chrome density, full-bleed video, 3-mode ticker (Off/Fade/Pin), borderless scores list, gold WATCH, etc.

## Also inspect current UI surfaces (code)
Read enough of:
- iOS: `SportsDash/Features/Scores/ScoresView.swift`, `GameMatchupRow.swift`, `Features/Player/PlayerView.swift`, `LiveScoresStrip.swift`, `Features/Guide/GuideView.swift` (skim), Settings if needed
- Android: `ui/ScoresScreen.kt`, `ui/PlayerScreen.kt`, `ui/GuideScreen.kt` (skim), `ui/SportsDashRoot.kt`
- Recent product law in skill SKILL.md only if needed for pitfalls

Open kanban residual themes if useful (do not require live kanban tool): login-upgrade messaging, loose favorite matching (TB Bucs vs Rays), player ticker modes.

## Review dimensions (cover all)
For **Scores**, **Guide**, **Player**, **Settings**, and **cross-platform parity**:

1. **Information architecture** — hierarchy, My Games, filters, density vs space
2. **Visual hierarchy & brand** — void/gold/mint consistency; remove gray panels; borderless vs affordance
3. **Scores rows** — logos, stars (outside corners), WATCH vs LIVE, status line, tap targets
4. **Favorites** — rail, Sport→League→Team picker, exact-id matching risk (city collisions)
5. **Player chrome** — full-bleed video, control layout, ticker Off/Fade/Pin, stream picker on switch, landscape
6. **Guide/EPG** — hour timeline, categories menu, channel favorites, loading honesty
7. **Motion & chrome budget** — auto-fade, small screens, landscape
8. **Accessibility** — contrast, hit targets, VoiceOver/TalkBack labels
9. **Platform conventions** — iOS system back/nav; Android system bars + Back; no fake TV shells
10. **Trust & dogfood** — IPTV login retention messaging (uninstall vs upgrade), empty/error states
11. **Parity gaps** — where iOS and Android feel different in a user-harmful way
12. **Prioritized roadmap** — P0 / P1 / P2 with effort (S/M/L) and platform tags

## Report format (markdown)
```markdown
# SportsDash UX/UI Review — YYYY-MM-DD (gpt-5.6-sol)

## Executive summary
## Method & sources (list files read, including inspiration notes)
## What works (aligned with A+D + brand)
## Critical issues (P0)
## High-priority improvements (P1)
## Polish / later (P2)
## Screen-by-screen
### Scores
### Player
### Guide
### Settings
### Cross-platform parity
## Inspiration gap analysis (samples vs shipped)
## Recommended next 2-week design/engineering plan
## Open questions for Samir
```

Be specific, opinionated, and constructive. Prefer measurable UX outcomes over taste-only nits. No trademark cloning recommendations.

## Constraints
- Work only under `/opt/data/workspace/sportsdash-apple` for the deliverable file (you may read the skill references path above).
- Do not commit unless asked; **do** write the markdown file.
- Do not invent secrets, hosts, or credentials.
- If a file is missing, note it and continue.
