# SportsDash Agile Board + Sprint 1 Implementation Plan

> **For Hermes:** Tech Lead orchestrates role profiles via kanban board `sportsdash`. Do not parent-link ship stories to long-lived epics. Seed residual with `--triage` / block; unblock only the active sprint (≤5 cards).

**Goal:** Stand up an Agile kanban for SportsDash (Apple primary), backlog from PRD + roadmap, then ship Sprint 1: **movie ratings (RT-style) for now-playing IPTV movies**.

**Architecture:** Native SwiftUI app in `/opt/data/workspace/sportsdash-apple`. Scores via ESPN public APIs; IPTV via M3U/Xtream; EPG via XMLTV. Movie ratings = new Core service (non-blocking) + UI chips on Guide and Player. Multiview intentionally removed (can return later). Flutter `sportsdash` repo is PRD/reference only.

**Tech Stack:** SwiftUI, KSPlayer, Keychain, Foundation networking; movie metadata API TBD (TMDB preferred free path + OMDb optional).

---

## Current product state (baseline)

| Area | Status |
|------|--------|
| Scores shelves / filters / favorites | ✅ Shipped |
| ESPN multi-league + 45s refresh | ✅ |
| M3U / Xtream + Keychain | ✅ |
| Channels by group | ✅ |
| Game→stream matching | ✅ |
| Fullscreen player (KS/AV), LIVE, aspect, captions | ✅ |
| Floating pop-out + system PiP | ✅ |
| Guide timeline + card grid | ✅ |
| Multiview multi-stream | ❌ Removed on purpose (`e16dd39`) |
| Movie ratings (PRD §5) | ⬜ Sprint 1 |
| Deeper EPG polish | ⬜ Later |
| Notifications (game start/goals) | ⬜ Later |
| Casting polish | ⬜ Later (AirPlay already allowed) |
| Apple TV focus polish | ⬜ Later |
| Android port | ⬜ Parked |

## Agile process (this board)

1. **Backlog** — triage or blocked; not ready.
2. **Sprint planning** — Tech Lead unblocks 3–5 shippable stories only.
3. **Roles** — product-analyst / researcher briefs; mobile-engineer UI; backend-dev N/A (no server — use mobile + researcher for API); security-dev reviews secrets/API keys; qa-engineer acceptance; devops only if CI/signing.
4. **Definition of Done** — code on `main`, acceptance criteria met, card `complete`/`archive` with SHA, no leftover ready duplicates.
5. **Flood control** — `kanban.auto_decompose=false` while loading; never bulk-unblock.

## Program epics (trackers only — do NOT parent-link all children)

| Epic | Priority | Notes |
|------|----------|-------|
| P0 Movie ratings now-playing | 10 | PRD §5 — Sprint 1 |
| P1 Player polish (notifications, casting UX) | 30 | After ratings |
| P2 Guide / EPG depth | 40 | XMLTV enrichment |
| P3 Apple TV focus | 50 | tvOS remote |
| P4 Android foundation | 90 | New repo later |
| P5 Multiview return (optional) | 95 | Explicitly deferred |

## Sprint 1 stories (ship now)

### S1.1 Researcher: ratings provider brief
**Assignee:** researcher  
**Objective:** Recommend movie ratings source (TMDB / OMDb / other) with license notes, free tier limits, and mapping from EPG title(+year) → scores.  
**Output:** Comment on board + short doc under `docs/movie-ratings.md`.  
**Acceptance:** Clear primary recommendation + fallback; no API key committed.

### S1.2 Product: acceptance criteria freeze
**Assignee:** product-analyst  
**Objective:** Turn PRD §5 into concrete AC + edge cases (sports vs movie, ambiguous titles, missing year).  
**Output:** Update `docs/movie-ratings.md` AC section (or PRD cross-link).  
**Acceptance:** Checklist usable by QA.

### S1.3 Mobile: MovieRatingsService + cache
**Assignee:** mobile-engineer  
**Objective:** Implement non-blocking lookup + disk/memory cache in Core.  
**Files (expected):**
- Create: `SportsDash/Core/Services/MovieRatingsService.swift`
- Create: `SportsDash/Core/Models/MovieRating.swift`
- Modify: `AppModel.swift` (optional shared cache access)
**Acceptance:** Lookup by title/year; returns nil on miss; never throws into UI path; TTL cache.

### S1.4 Mobile: Guide + Player ratings UI
**Assignee:** mobile-engineer  
**Objective:** Show RT-style chip when now-playing is a movie with a confident match.  
**Files:**
- Modify: `Features/Guide/GuideView.swift`
- Modify: `Features/Player/PlayerView.swift`
- Theme: `Theme/SportsColors.swift` if needed  
**Acceptance:** Hidden for sports/non-movie/no-match; readable on dark UI; playback not blocked.

### S1.5 Security: API key / Keychain pattern
**Assignee:** security-dev  
**Objective:** Review how API keys are stored (Keychain vs Info.plist); no secrets in git.  
**Acceptance:** Documented pattern; redact if any leak found.

### S1.6 QA: acceptance pass
**Assignee:** qa-engineer  
**Objective:** Verify PRD acceptance criteria against implementation (code review + logic tests if no device).  
**Acceptance:** Written pass/fail on each AC.

## Later backlog (seed blocked/triage — do not unblock in Sprint 1)

- Notifications for game start / score events  
- Deeper EPG categories / movie detection from XMLTV `category`  
- Apple TV focus engine polish  
- Casting UI polish  
- Multiview reintroduction (parked)  
- Android repo bootstrap  

## Risks

- No physical iOS build agent here — ship Swift code + compile-check if toolchain available; Samir dogfoods on device.  
- EPG often lacks clean “movie” flags — need heuristic + category when present.  
- API keys: never commit; use Keychain or xcconfig gitignored.  
- KSPlayer GPL remains App Store shipping risk (existing).

## Open defaults (Tech Lead)

- **Provider:** TMDB search + details first; OMDb optional if key present. RT branding only if legally ok — otherwise “Critic/Audience” labels with scores.  
- **Movie detection:** XMLTV category contains movie/film OR title heuristics; never force ratings on live sports groups.  
- **Sprint size:** S1.1–S1.6 only for first dispatch wave; S1.3+S1.4 may be Tech Lead + mobile if parallel workers fight the same files — prefer sequential mobile slices.

---

## Execution order after board seed

1. Researcher + product-analyst in parallel (brief).  
2. Mobile service then UI.  
3. Security review on key handling.  
4. QA gate.  
5. Tech Lead commit/push + archive cards.
