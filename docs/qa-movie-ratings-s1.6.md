# S1.6 QA — movie ratings acceptance pass

**Date:** 2026-07-22  
**Method:** Static/logic review against `docs/movie-ratings.md` + code paths  
**HEAD baseline:** post-S1.5 patches  

## Acceptance criteria

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Rating on Guide row for matched now-playing movies | **PASS** | `GuideView` → `MovieRatingLoader` with title + categories + channel group/name |
| 2 | Rating on Player overlay for matched now-playing | **PASS** | `PlayerView.bottomInfoChrome` → `MovieRatingLoader` |
| 3 | Fetch non-blocking | **PASS** | `.task` async load; service is actor; no await on main layout path |
| 4 | Hidden when not a movie | **PASS** | `MovieDetection.isMovieCandidate` gate; loader returns without fetch |
| 5 | Hidden when no match / no key | **PASS** | Service returns nil; badge only renders if `rating != nil` |
| 6 | Cache TTL; no thrash refetch | **PASS** | Memory + disk cache 7d; negative cache 24h |
| 7 | Labels Critic/Audience (not RT trademark) | **PASS** | `MovieRatingBadge` chips |
| 8 | Keys in Keychain only | **PASS** | See S1.5 |
| 9 | Sports not scored | **PASS** | Sports keywords/groups hard-no in `MovieDetection` |
| 10 | KSPlayer default (product note) | **PASS** | Prefs default + migration v2 |

## Bugs fixed during QA

| Issue | Fix |
|-------|-----|
| Loader computed `hint` then always passed `isMovieHint: true` | Pass `hint` through (belt-and-suspenders with guard) |

## Device dogfood (Samir)

Not blocked on this static pass. Manual check:

1. Settings → General → save free OMDb key  
2. Guide movie channel now-playing → Critic/Audience chips  
3. Open player → same chips  
4. Sports channel → no chips  

## Verdict

**PASS** for Sprint 1 movie ratings. Ready to close S1 epic trackers.
