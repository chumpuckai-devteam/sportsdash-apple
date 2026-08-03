# Dual-platform parity matrix (baseline freeze)

**Repo:** `sportsdash-apple` · **Board:** `sportsdash` · **Updated:** 2026-08 parity sprint  
**Law:** Ship Android + iOS to the **same product story** before net-new features.

## Shared baseline (both platforms)

| Area | Behavior |
|------|----------|
| Nav | Scores · Guide · Settings |
| Hard player | VLC / libVLC, TS-first |
| Scores | ESPN Live / Upcoming / Final / **★ Faves** (favorite teams) |
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
| S-PARITY.A1 | Android favorite teams + ★ Faves | **shipped** |
| S-PARITY.A2 | Scores filter Live/Upcoming/Final/FAVES | **shipped** |
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
| S-PARITY.C1 | Movies Now + rating chips | **Movies Now filter shipped**; OMDb/TMDB chips **still iOS-only** |
| S-PARITY.C2 | iOS channel favorites | **still open** (Android has them) |
| S-PARITY.C3 | AirPlay / Cast | **blocked** Apple AV / Android Cast later |
| S-PARITY.C4 | TV (tvOS / Android TV) | **blocked** separate track |

## Intentional remaining deltas

1. **Movie ratings chips (OMDb/TMDB)** — iOS only until keys + List pitfalls ported to Compose.  
2. **iOS channel favorites** — Android long-press model not yet on GuideView.  
3. **Dual engine Auto (HLS→AV)** — Android VLC-only; fine for IPTV dogfood.  
4. **Liquid Glass / splash polish** — Apple chrome only.  
5. **tvOS focus vs Android TV** — not phone baseline.

## Dogfood AC (baseline green)

- [ ] Load Xtream; 2nd launch paints cached channels quickly  
- [ ] Long-press Scores game → star home/away team → ★ Faves filter works  
- [ ] Favorite-team games sort first under Live  
- [ ] Guide: Hour/Grid, Movies filter, category ☰, channel ★ favorites  
- [ ] Play → pop-out mini bar over tabs → expand → close  
- [ ] Clean names ON strips HD/4K noise  
- [ ] EPG full download once; titles on timeline  

## New features rule

Do **not** start Cast, multiview, push, or TV work until Wave C intentional deltas are accepted or closed.
