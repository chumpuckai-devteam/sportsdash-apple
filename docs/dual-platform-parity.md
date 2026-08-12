# Dual-platform parity matrix (baseline freeze)

**Repo:** `sportsdash-apple` · **Board:** `sportsdash` · **Updated:** 2026-08 parity sprint  
**Law:** Ship Android + iOS to the **same product story** before net-new features.

## Shared baseline (both platforms)

| Area | Behavior |
|------|----------|
| Nav | Scores · Guide · Settings |
| Hard player | VLC / libVLC, TS-first |
| Scores | ESPN Live / Upcoming / Final (both); favorite **teams** pin first via **league-scoped ESPN ids** (`nfl:27`) |
| Watch from Scores | Tap game → match channels → play |
| Guide | Hour timeline + Grid; provider category order; EPG download-once |
| Guide favorites | Star **channels** (Android long-press; iOS optional follow-up) |
| Movies Now | Filter movie-like now-playing (both when enabled) |
| Player | Back, mute, pause, rejoin, ticker toggle, **pop-out mini player** |
| Settings | Playlist Xtream/M3U, leagues, reload EPG, clean names, About LGPL |
| Brand | Void + gold / live mint |

## Wave status

### Wave A — must (shipped this sprint)
| ID | Item | Status |
|----|------|--------|
| S-PARITY.A1 | Android favorite teams + pin-first | **shipped** (★ Faves filter removed — FAV.3 teams-only) |
| S-PARITY.A2 | Scores filter Live/Upcoming/Final | **shipped** (no separate Faves chip) |
| S-PARITY.A3 | Guide timeline checklist | **shipped** (doc + dogfood AC) |
| S-PARITY.A4 | This matrix doc | **shipped** |

### Wave B — should (shipped this sprint)
| ID | Item | Status |
|----|------|--------|
| S-PARITY.B1 | Android floating mini-player | **shipped** (pop-out bar) |
| S-PARITY.B2 | Channel name cleanup | **shipped** (toggle + display) |
| S-PARITY.B3 | Channel list disk cache | **shipped** |
| S-PARITY.B4 | Settings core prefs | **shipped** (clean names) |

### Wave C — later / partial
| ID | Item | Status |
|----|------|--------|
| S-PARITY.C1 | Movies Now + rating chips | **Movies Now + OMDb/TMDB chips shipped** (keys in Settings) |
| S-PARITY.C2 | iOS channel favorites | **shipped** (context menu / long-press + ★ Favorites group) |
| S-PARITY.C3 | AirPlay / Cast | **blocked** Apple AV / Android Cast later |
| S-PARITY.C4 | TV (tvOS / Android TV) | **blocked** separate track |

## Intentional remaining deltas

1. **Dual engine Auto (HLS→AV)** — Android VLC-only; fine for IPTV dogfood.  
2. **Liquid Glass / splash polish** — Apple chrome only.  
3. **tvOS focus vs Android TV** — not phone baseline.

## Dogfood AC (baseline green)

- [ ] Load Xtream; 2nd launch paints cached channels quickly  
- [ ] **Android update:** install new APK **over** existing app (no uninstall) → Xtream host/user still in Settings; blank password = kept (see `docs/android-login-persist.md`)  
- [ ] Long-press Scores game → star home/away team → those games pin first under Live/Upcoming  
- [ ] Favorite-team games sort first under Live (no separate ★ Faves filter)  
- [ ] Guide: Hour/Grid, Movies filter, category ☰, channel ★ favorites  
- [ ] Play → pop-out mini bar over tabs → expand → close  
- [ ] Clean names ON strips HD/4K noise  
- [ ] EPG full download once; titles on timeline  

## New features rule

Do **not** start Cast, multiview, push, or TV work until Wave C intentional deltas are accepted or closed.
