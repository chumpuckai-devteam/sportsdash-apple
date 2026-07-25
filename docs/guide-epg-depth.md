# Guide / EPG depth — categories, movie detection, performance

**Kanban:** `t_9aace370`  
**Date:** 2026-07-25

## What shipped

### 1. P0 movie-flag signals actually reach the UI
`DiskXMLTVParser` already captured `<category>`, but `EpgService.mapXmltv` rebuilt `EpgProgram` **without** `categories` (or `description`). That silently zeroed P0 movie flags after every bulk XMLTV load.

**Fix:** `EpgProgram.remapped(toChannelKey:)` preserves categories/description when mapping XMLTV channel ids → app channel ids.

### 2. Richer category surface
| Surface | Behavior |
|--------|----------|
| `EpgProgram.categories` | Passed through cache/UI |
| `categoryChipLabel` / `XmltvCategory` | Normalized display label; prefers movie-ish category |
| Guide card (grid) | Category chip under NOW title |
| Guide timeline | Compact chip when cell width > 96pt |
| Guide settings | **Movies now** filter (XMLTV category + detection signals) |

### 3. Movie detection quality
`MovieFlagSignals` + `MovieDetection.signals(...)` priority:

1. Hard no — sports/news channel or title
2. **P0 hard yes** — XMLTV category movie/film/cinema/feature (+ ES/DE tokens)
3. Hard no — non-movie category (series, episode, sport, news, …) without movie token
4. Movie channel name/group hints
5. Title year / `Movie:` prefix
6. Soft entertainment/hollywood/VOD groups
7. Multi-word title heuristic **only when categories are absent** (IPTV reality)

### 4. Performance
| Change | Why |
|--------|-----|
| Preserve categories in map (no extra parse) | Enables correct gating → fewer bogus OMDb hits |
| Cached `DateFormatter` on program time labels | Avoid per-cell formatter alloc on timeline scroll |
| `guideRows.reserveCapacity` + lazy lists unchanged | Category switch stays instant; movies filter is O(visible group) |
| Ratings prefetch still capped at 16 + store dedupe | Unchanged budget |
| Soft groups trimmed (dropped redundant hollywood* dupes) | Slightly fewer false soft matches |

No full-file XML load regressions — still disk download + SAX parse + window/limit caps.

## Sample XMLTV cases (manual / logic check)

```xml
<programme start="20260725180000 +0000" stop="20260725200000 +0000" channel="hbo.us">
  <title>Inception</title>
  <category>Movie</category>
  <category>Drama</category>
</programme>

<programme start="20260725190000 +0000" stop="20260725220000 +0000" channel="espn.us">
  <title>Monday Night Football</title>
  <category>Sports</category>
</programme>

<programme start="20260725193000 +0000" stop="20260725201500 +0000" channel="nbc.us">
  <title>Some Drama Show</title>
  <category>Series</category>
</programme>

<programme start="20260725200000 +0000" stop="20260725220000 +0000" channel="us.general">
  <title>The Dark Knight HD</title>
  <!-- no category — year/title heuristics only -->
</programme>
```

| Case | Expected |
|------|----------|
| Inception + Movie | `categorySaysMovie`, chip **MOVIE**, ratings allowed |
| MNF + Sports | not movie; no ratings |
| Series drama | not movie even if multi-word title |
| Dark Knight, no category | movie via multi-word / cleanup when channel not sports |

Run logic mirror (Linux host, no Xcode):

```bash
python3 scripts/verify_epg_movie_detection.py
```

## Device verification (Samir)

1. `git pull` → `xcodegen generate` → Clean → Run.
2. Reload EPG once so cache is rewritten **with** categories (old disk cache may lack them until refresh).
3. Open a Movies / HBO-style group — NOW row should show category chip when feed has `<category>`.
4. Guide ⋯ → **Movies now** — list narrows to movie-like now-playing.
5. Confirm sports groups still hide rating chips.
6. Settings → Test ratings (Inception) still OK.

## Out of scope (per card)
- Implementing new remote “movie flag” APIs beyond XMLTV categories
- DVR / live-tune changes
