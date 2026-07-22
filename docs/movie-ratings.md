# Movie Ratings Provider Brief

**Status:** Sprint 1 research (S1.1)  
**Scope:** Free-tier-friendly critic/audience-style scores for EPG now-playing IPTV movies  
**Out of scope:** Swift implementation details, Android, marketplace  

---

## Recommendation

| Role | Provider | Why |
|------|----------|-----|
| **Primary** | **OMDb API** (https://www.omdbapi.com/) | Free key with **1,000 requests/day**; title(+year) lookup; returns a `Ratings[]` array that often includes **Rotten Tomatoes %**, IMDb, and Metacritic in one call. Best fit for RT-style **Critic** chips. |
| **Fallback** | **TMDB API v3** (https://developer.themoviedb.org/) | Free developer key (non-commercial with attribution); strong `search/movie` + year filter; `vote_average` (0–10 community) maps cleanly to an **Audience**-style 0–100 score. Higher practical throughput than OMDb. No official RT Tomatometer. |

**Do not use as Sprint 1 primaries:** unofficial RapidAPI “Rotten Tomatoes” scrapers (ToS/fragility), Watchmode (streaming-availability focus; free tier not needed for scores-only), MDBList (list-builder/supporter product — extra dependency for little Sprint 1 gain).

### Hybrid call order (recommended)

1. Gate on movie detection (category / channel heuristics) — never hit APIs for live sports.  
2. Normalize EPG title + optional year.  
3. **If OMDb key present:** `GET https://www.omdbapi.com/?apikey=…&t={title}&type=movie&y={year?}`.  
4. **Else / on OMDb miss:** TMDB `GET /3/search/movie?query=…&year=…&include_adult=false` → take **only** a high-confidence single match → map `vote_average * 10` → audience.  
5. Optional later upgrade (not required for S1): TMDB search → `imdb_id` via movie details → OMDb `i=tt…` for tighter ID match.

This matches the product goal (RT-style critic when available) while keeping a free, reliable audience fallback.

---

## Provider comparison (facts)

### OMDb (primary)

| Item | Detail |
|------|--------|
| Auth | Query param `apikey` (key emailed after free signup at `/apikey.aspx`) |
| Free tier | **FREE — 1,000 requests/day** (Patreon tiers for higher limits / poster API) |
| Endpoints | By title `t` + optional year `y` + `type=movie`; by IMDb id `i=tt…`; search `s` (list, no ratings) |
| Scores | `Ratings[]`: e.g. `{"Source":"Rotten Tomatoes","Value":"87%"}`, IMDb `8.8/10`, Metacritic `74/100`; also top-level `imdbRating`, `Metascore` |
| HTTPS | Supported (`https://www.omdbapi.com/`) |
| Content license | Site states content under **CC BY-NC 4.0** (non-commercial). Confirm before any paid/commercial App Store monetization. |
| Sources | https://www.omdbapi.com/ , https://www.omdbapi.com/apikey.aspx , swagger at `/swagger.json` |

**Verified response shape (Inception, public demo):** includes `Ratings` with Internet Movie Database, Rotten Tomatoes, Metacritic.

**Gaps:** Daily hard cap is tight if Guide prefetches many channels without cache. OMDb title match is “most popular match” for `t=` — year helps but confidence rules still required. Does **not** reliably expose separate RT **Audience Score** — typically Tomatometer (critics) only in `Ratings`.

### TMDB (fallback)

| Item | Detail |
|------|--------|
| Auth | `api_key` query **or** `Authorization: Bearer <API Read Access Token>` |
| Free tier | Free for **non-commercial** use with attribution; commercial → contact sales@themoviedb.org |
| Rate limits | Legacy 40/10s removed (2019); soft upper bound ~**40 req/s**; honor HTTP **429** |
| Search | `GET /3/search/movie?query=&year=&include_adult=false` |
| Scores | `vote_average` (0–10), `vote_count` — community, **not** RT/Metacritic |
| IDs | Movie details include `imdb_id` for crosswalk to OMDb |
| Attribution | Required: TMDB logo + notice *“This product uses the TMDB API but is not endorsed or certified by TMDB.”* in About/Credits |
| Sources | https://developer.themoviedb.org/docs/faq.md , rate-limiting.md , search-and-query-for-details.md |

**Gaps:** No critic Tomatometer. Commercial shipping may need a paid TMDB agreement. Must not brand TMDB votes as “Rotten Tomatoes.”

---

## Auth / key storage (no secrets in git)

**Facts in repo today**

- `.gitignore` already excludes `.env`, `Secrets.xcconfig`.  
- `KeychainStore` (`SportsDash/Core/Services/KeychainStore.swift`) already stores IPTV passwords under service `com.samirpatel.sportsdash`.

**Recommendation**

| Key | Runtime storage | Dev override | Never |
|-----|-----------------|--------------|--------|
| OMDb | Keychain account `omdb_api_key` | Env `OMDB_API_KEY` (local/Xcode scheme only) | Commit key, Info.plist, source literals |
| TMDB | Keychain account `tmdb_api_key` (v3 api_key) **or** `tmdb_read_token` (Bearer) | Env `TMDB_API_KEY` / `TMDB_READ_ACCESS_TOKEN` | Same |

**Patterns**

1. **Production / device:** user or build pipeline writes keys into Keychain (Settings debug field, or one-time xcconfig → Keychain on first launch — xcconfig stays gitignored).  
2. **CI / sim:** scheme environment variables only; not checked in.  
3. **Optional `Secrets.xcconfig` (gitignored):**  
   `OMDB_API_KEY = …` / `TMDB_API_KEY = …` referenced from a checked-in `Secrets.xcconfig.example` with empty placeholders.  
4. Missing keys ⇒ **fail closed** (hide chips); never toast raw API errors.

Security-dev (S1.5) should confirm Keychain accessibility (`AfterFirstUnlock` is fine for background refresh) and that no key lands in crash logs/analytics.

---

## Title (+year) match strategy and confidence

### 1. Pre-filter (do not call APIs)

Treat as movie candidate only if **any** of:

- XMLTV/EPG categories contain `movie` / `film` / `cinema`  
- Channel group/name hints movie networks (HBO, Starz, Cinema, TCM, …) **and** not sports  
- Title has clear film markers (`Movie:`, `Film:`, trailing `(YYYY)`) **and** not sports keywords  

**Hard no:** sports/news/weather categories; sports channel groups (ESPN, NFL, NBA, …); empty program title.

### 2. Normalize before lookup

From raw EPG title:

1. Trim whitespace.  
2. Strip leading `Movie:` / `Film:` / `Cinema:` / `Mov:` (case-insensitive).  
3. Extract trailing `(YYYY)` → year; remove from title.  
4. Strip broadcast noise tokens when isolated: `HD`, `FHD`, `UHD`, `4K`, `HDR`, `LIVE`, `Premiere`, `[EN]`, language tags.  
5. Collapse internal whitespace.  
6. Cache key: `lowercased(title)|year` or `lowercased(title)` if no year.

Keep the **original** EPG string for on-screen title; provider title is internal only unless product later allows swap.

### 3. Confidence rules

| Situation | Action |
|-----------|--------|
| OMDb `Response=True`, `Type=movie`, year present and matches ±0 (or EPG year absent) | **High** — show scores if any usable |
| OMDb hit, EPG year present, provider year differs by **1** (awards/region) | **Medium** — show only if normalized titles equal (case-fold, ignore punctuation) |
| OMDb hit, year differs by **>1** | **Reject** |
| OMDb `Response=False` / error | Try TMDB if keyed |
| TMDB results empty | Miss → negative cache |
| TMDB **exactly one** result after year filter | **High** if year matches or both missing |
| TMDB multiple results, year provided, filter to one | **High** |
| TMDB multiple results, **no** year | **Reject** (do not pick popularity winner) |
| TMDB top result title fuzzy-ratio low vs query (e.g. Levenshtein / token sort < ~0.85) | **Reject** |
| Scores all missing / unparseable | Hide UI (match without scores is still a miss for product) |

**Score mapping**

| Source field | UI field | Mapping |
|--------------|----------|---------|
| OMDb `Ratings[Source=Rotten Tomatoes].Value` (`87%`) | `criticScore` 0–100 | Parse integer percent |
| OMDb IMDb (`8.8/10` or `imdbRating`) | `audienceScore` 0–100 | `round(x * 10)`, clamp 0–100 |
| OMDb Metacritic (optional secondary) | not shown in S1 chips | Keep available for later |
| TMDB `vote_average` | `audienceScore` only | `round(vote_average * 10)`; require `vote_average > 0` and prefer `vote_count >= 20` when present |

UI labels: always generic **Critic** / **Audience** (see Legal). Footnote/source string can be `OMDb` or `TMDB` for debug builds only.

---

## Rate limits and caching TTL

### Limits

| Provider | Practical budget | Client policy |
|----------|------------------|---------------|
| OMDb free | **1,000 / day** | Aggressive cache; **no** Guide-wide prefetch of entire playlist; lookup **visible now-playing + current player** only; coalesce in-flight requests per cache key |
| TMDB | ~40 / s soft | Still cache; backoff on **429** with jitter; no tight poll loops |

At 1k OMDb/day, uncached unique titles ≈ 1k/day. With a 7-day positive TTL and typical movie channel churn, one household stays well under the cap.

### Suggested TTLs

| Cache class | TTL | Notes |
|-------------|-----|-------|
| Positive hit (has critic and/or audience) | **7 days** | Scores change slowly; disk + memory |
| Negative miss (no match / low confidence / no scores) | **24 hours** | Avoid hammering OMDb on bad EPG titles |
| Transport failure / 429 / 5xx | **15–60 minutes** soft backoff | Do not write long negative cache; retry later |
| In-memory only in-flight dedupe | request lifetime | One network call per key |

**Storage:** app Caches directory JSON (or equivalent), keyed by normalized `title|year`. Not UserDefaults for bulk blobs. Never block playback on disk I/O — load cache asynchronously.

**Stale-while-revalidate (optional):** if cached positive hit is within TTL, show immediately; optional background refresh near expiry is YAGNI for S1.

---

## Legal / branding

### “Rotten Tomatoes” branding

- **Rotten Tomatoes**, Tomatometer, certified-fresh icons, and related marks are Fandango/RT trademarks.  
- OMDb may **relay** a numeric RT percentage in JSON; that is **not** a license to use RT logos, names, or trade dress in the app UI.  
- **Default UI copy:** labels **Critic** and **Audience** (or “Critics” / “Viewers”). Do **not** show “Rotten Tomatoes”, “RT”, tomato icons, or popcorn icons unless a separate RT/Fandango license is obtained.  
- Optional Settings/About footnote: “Scores provided via OMDb / TMDB” without implying RT endorsement.

### OMDb

- Content marked **CC BY-NC 4.0** on omdbapi.com — treat free tier as **non-commercial / personal** until license clarified for a commercial App Store binary.  
- Not affiliated with IMDb.

### TMDB

- Free developer use requires attribution (logo + endorsement disclaimer in About).  
- Commercial primary purpose → contact TMDB sales.  
- Do not imply TMDB endorsement; do not present `vote_average` as an official critic score.

### General

- Ratings are informational overlays only; no claim of affiliation with studios or review orgs.  
- Fail closed on ambiguity — wrong score on a live game is worse than no chip.

---

## Implementation notes for downstream (non-binding)

Expected Core shapes (already sketched in working tree; this brief does not require them):

- `MovieRating`: `criticScore?`, `audienceScore?`, `source`, `cacheKey`, `fetchedAt`  
- `MovieRatingsService`: non-blocking actor; Keychain keys; OMDb then TMDB; 7d/24h caches  
- UI: Guide + Player chips; hide when `!hasAnyScore`

No Android scope. No server proxy required for S1 (keys on device); a future backend proxy could hide keys and share cache across users if commercial/ToS needs change.

---

## Decision log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Primary provider | OMDb | Only free mainstream API that regularly returns RT **%** + IMDb in one title/year call |
| Fallback | TMDB | Better search, high limits, audience-style score, IMDb id crosswalk |
| Branding | Generic Critic/Audience | No RT trademark license |
| Cache | 7d hit / 24h miss | Fits 1k/day OMDb budget for IPTV now-playing |
| Secrets | Keychain + gitignored xcconfig/env | Matches existing IPTV password pattern |

**Open items for humans**

1. Confirm App Store distribution remains compatible with OMDb CC BY-NC (or obtain commercial permission / drop OMDb if monetized).  
2. If commercial TMDB is required later, budget for TMDB API for Business.  
3. Product-analyst AC freeze below remains the QA contract; provider swap must still satisfy it.

---

## Product acceptance criteria (QA contract)

Frozen behavior for PRD §5 / Sprint 1 stories S1.2–S1.6. Provider-neutral; compatible with the OMDb→TMDB stack above.

### 1. Movie eligibility

- Given EPG/guide metadata explicitly identifies the now-playing program as a movie/film, and a non-empty title is available, the app may request ratings for that title.
- Given metadata explicitly identifies the now-playing program as live sports, a game, news, series, episode, paid programming, or another non-movie category, the app must not show movie-rating UI.
- Given a channel belongs to a sports/live-event group and the current program is not explicitly movie/film metadata, the app must treat it as non-movie for ratings purposes.
- Given no category metadata is available, the app may use conservative movie-title heuristics only when the title is clearly film-like; heuristics must not force ratings onto live games or generic channel names.
- Given only a channel name is available and no now-playing program title exists, the app must not request or show movie ratings.

### 2. Title and year matching

- Given a movie title and release year are available from EPG/guide metadata, the lookup must use both title and year when the provider supports year filtering.
- Given a movie title is available but the year is missing, the lookup may search by title alone but must require a confident single match before exposing ratings.
- Given provider search returns multiple plausible matches for the same title and no year is available, the app must hide the rating UI rather than guessing.
- Given the EPG title includes common broadcast suffixes such as `HD`, `4K`, `Live`, `Premiere`, language tags, or parenthetical channel annotations, matching may normalize those tokens before lookup.
- Given normalization changes a title, the original visible now-playing title in the Guide/Player must not be replaced by the provider title unless a later UX spec explicitly allows it.

### 3. No match, low confidence, and missing scores

- Given the provider returns no movie match, the app must show no rating chip, placeholder, loading failure text, or fake score.
- Given the provider match confidence is below the implementation threshold, the app must show no rating UI.
- Given a confident movie match exists but no critic/audience/equivalent score is available, the app must show no rating UI unless a future spec defines an alternate "unrated" treatment.
- Given a ratings request fails, times out, is rate-limited, or returns malformed data, playback and now-playing UI must remain usable and ratings must stay hidden.
- Given a stale cached rating exists and the network refresh fails, the app may show the cached rating only if it is within the accepted cache TTL; otherwise hide the UI.

### 4. Surfaces and visibility

- Given a current Guide row/card represents a channel whose now-playing program is a confidently matched movie with usable ratings, the Guide now-playing surface must show at least one recognizable quality score chip.
- Given the user is watching a channel whose now-playing program is a confidently matched movie with usable ratings, the Player chrome or info overlay must show the same rating information when controls/info are visible.
- Given the same movie appears in both Guide and Player, the displayed scores and labels must be consistent across both surfaces.
- Given a program changes from movie to non-movie, no-match, or low-confidence state, both Guide and Player surfaces must remove the rating UI on the next now-playing update.
- Given ratings are still loading, the Guide and Player must not reserve distracting empty space or show spinner-only rating chrome unless a future UX spec explicitly requests loading states.

### 5. Rating labels and legal-safe presentation

- Given the app has licensed Rotten Tomatoes or equivalent brand assets, it may use the licensed labels/icons allowed by that agreement.
- Given no Rotten Tomatoes license is configured, the app must use generic labels such as `Critic` and/or `Audience` rather than Rotten Tomatoes branding.
- Given only one score type is available, the app may show that single score if its label makes the source/type clear.
- Given both critic and audience/equivalent scores are available, the app should show both when space permits; truncation must preserve clarity over decoration.

### 6. Non-blocking playback and performance

- Given the user opens or switches to a stream, playback startup must not wait for any movie-rating network call.
- Given a ratings lookup is in flight, player controls, fullscreen transitions, guide scrolling, and channel switching must remain responsive.
- Given a ratings lookup completes after the user changes channel/program, the result must not appear on the wrong channel or stale now-playing item.
- Given repeated visits to the same recently seen title, the app should use cache according to the chosen TTL to avoid unnecessary provider calls.
- Given provider rate limits or missing API credentials, the app must fail closed by hiding ratings, not by interrupting playback or surfacing raw errors to viewers.

### 7. Dark UI contrast and layout

- Given ratings are displayed on the dark SportsDash/broadcast UI, text, icons, and chip backgrounds must meet readable contrast in both Guide and Player contexts.
- Given the Player overlay appears over varied video content, the rating chip must remain legible through an overlay, scrim, material background, or other contrast treatment.
- Given long titles, small screen widths, tvOS focus scaling, or dynamic type, rating chips must not overlap the now-playing title, score overlays, or core playback controls.
- Given the rating UI is hidden for any reason, the layout must collapse cleanly without leaving blank placeholders.

### 8. QA edge-case matrix

| Case | Input/state | Expected result |
| --- | --- | --- |
| Movie with title + year + confident scores | EPG category `movie`, title `Example Film`, year `1999` | Guide and Player show labeled score chip(s). |
| Movie with title, missing year, single confident provider result | EPG category `movie`, title only | Guide and Player show labeled score chip(s). |
| Movie with title, missing year, multiple plausible matches | Provider returns several close title matches | Ratings hidden on all surfaces. |
| Movie with no provider match | Provider returns empty result | Ratings hidden on all surfaces. |
| Movie with confident match but no scores | Provider has metadata but no rating values | Ratings hidden on all surfaces. |
| Live sports program | Category/team/game metadata indicates sports | No ratings request is required; no rating UI appears. |
| Non-movie entertainment/news/series | Category indicates non-movie | No rating UI appears. |
| Channel-only metadata | No now-playing title | No rating UI appears. |
| Ratings request slow or failed | Network timeout/error/rate limit | Playback starts normally; ratings hidden. |
| Channel switched before lookup completes | Result returns for previous program | Result is discarded or ignored; not shown on new channel. |
| Dark video/background | Player overlay over bright/dark content | Rating text/chip remains readable. |

### Out of scope for the frozen product AC

- Production SwiftUI implementation details beyond behavioral requirements.
- Marketplace, checkout, account billing, or non-SportsDash commerce surfaces.

---

## Sources (accessed 2026-07-22)

- OMDb API home, key page, swagger, legal: https://www.omdbapi.com/  
- TMDB FAQ, getting started, rate limiting, search guide, movie details: https://developer.themoviedb.org/  
- TMDB attribution/terms notes via FAQ + site terms  
- Live OMDb sample payload for `i=tt1375666` (Inception) confirming `Ratings[]` RT/IMDb/Metacritic  
- Repo: `docs/ARCHITECTURE.md`, `.gitignore`, `KeychainStore.swift`, Sprint plan `.hermes/plans/2026-07-22_154258-sportsdash-agile-board-and-sprint1.md`
