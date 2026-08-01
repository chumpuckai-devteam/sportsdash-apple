# EPG review — US Movies “No EPG data” (2026-08)

## Frontend findings
- Guide fabricated a fake programme titled **“No EPG data”**, so empty listings looked like real cards.
- Channel column (~120pt) truncated names (“Showtim…”).
- No per-category coverage meter.

## Backend findings
- Bulk XMLTV only keeps programmes whose `channel=` id is in `interestKeys` (from `epg_channel_id` / `tvg-id`).
- Many Xtream movie streams have **empty** `epg_channel_id` → programmes never enter the map.
- Full reload returned after bulk **without** short-EPG gap fill when `fillMissingWithShortEpg` was false.
- Category gap-fill only requested **24** channels of short EPG.

## Fixes shipped
1. After bulk, always short-EPG gap-fill (cap 60 full / 100 category).
2. When >50% of a set lacks EPG ids and set ≤500 channels, parse XMLTV without interest filter so slug/name map can attach.
3. Slug + name fuzzy map (`showtime.us` ↔ “Showtime HD”).
4. Category gap-fill prefix **80**.
5. UI: muted empty row text; wider channel col; “Guide X/Y in this category” + **Fill missing**.

## Device steps
1. Pull · xcodegen · Run  
2. Settings → Reload EPG (force) once to rebuild cache  
3. Guide → US Movies → wait / tap **Fill missing**  
4. Confirm more titles than “No guide for this channel”
