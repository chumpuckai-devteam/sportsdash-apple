# 005 · Jumbotron — SPEC

Build from this file. `index.html` / `phone.png` are the reference render.

## 1. Tokens

Palette is **SportsColors as shipped**; no third palette. `sketches/themes/tokens.css` and
Android `Theme.kt` are behind SportsColors and should be brought to these values in this drop.

| Token | iOS `SportsColors` | Hex | Android `Theme.kt` | tokens.css | Use |
|---|---|---|---|---|---|
| void | `voidBlack` | `#070910` | `VoidBlack` → `0xFF070910` | `--void` → `#070910` | screen ground |
| panel | `panel` | `#0F131A` | `Panel` → `0xFF0F131A` | `--panel` | panel bottom of gradient, tab bar |
| panelElevated | `panelElevated` | `#171C24` | new `PanelElevated` | `--panel-2` | panel top of gradient |
| border | `border` | `#2A3340` | new `Border` | `--border` | 2pt panel border, toggle-off |
| gold | `gold` | `#FFB800` | `Gold` → `0xFFFFB800` | `--gold` | LED digits, WATCH, active tab, toggle-on |
| goldDim | `goldDim` | `#B8860B` | new | `--gold-dim` | reserved; trailing side uses gold @ 0.5 opacity, not goldDim |
| live | `live` | `#00E5A0` | `LiveMint` → `0xFF00E5A0` | `--mint` | live status, progress fill, "done" lamp |
| danger | `danger` | `#FF3B5C` | `Danger` → `0xFFFF3B5C` | `--danger` | alerts section tick, errors, blocked lamp |
| text | `text` | `#F2F4F7` | `TextPrimary` | `--ink` | team names, titles |
| textSecondary | `textSecondary` | `#B8C0CE` | new | — | records, secondary labels |
| muted | `muted` | `#8B96A8` | `Muted` → `0xFF8B96A8` | `--muted` | inactive tabs/filters, captions |

New in this drop (add to `SportsColors` / `Theme.kt` / tokens.css):

| Token | Value | Use |
|---|---|---|
| `ledGlow` | gold @ 0.80, blur 12 (`.shadow(color: gold.opacity(0.8), radius: 6)`) | behind every LED digit |
| `liveGlow` | live @ 0.75, blur 10 | behind live status text, progress bar edge |
| `panelGradient` | vertical, top `panelElevated` → bottom `panel` | every panel fill |
| `gridDot` | `#141B28`, 1pt dot on a 6pt grid | screen background (iOS `Canvas`/tiled image; Android `drawBehind`) |
| `digitBox` | fill `void`, 1pt `border` | box behind hero digits |
| team edge | `TeamTheme.accent(for:)` (ESPN hex or hashed fallback) | 5pt edge bars, hero bleed |

Hero bleed: horizontal gradient `away.opacity(0.55)` 0→34%, panel 34→66%, `home.opacity(0.60)` 66→100%, layered over `panelGradient`.

## 2. Type

Bundle three OFL fonts: **Bebas Neue** (display), **Orbitron Black 900** (digits), **Space Mono** 400/700 (body). Fallbacks: system condensed / `.system(design: .rounded).monospacedDigit()` / `.monospaced`.

| Role | Face | Size / weight | Tracking | Where |
|---|---|---|---|---|
| Screen title | Bebas | 40 | +0.04em | "SCORE**BOARD**", "CHANNEL **GUIDE**", "CONTROL **ROOM**" — second word gold |
| Section header | Bebas | 20 | +0.04em | league names, `textSecondary` |
| Team abbr (row) | Bebas | 22 | +0.04em | 60pt column |
| Team name (hero) | Bebas | 32 | +0.04em | |
| Filter / tab label | Bebas | 18 / 20 | +0.04em | |
| Settings row label | Bebas | 22 | +0.04em | |
| Hero digit | Orbitron 900 | 58 | tabular | `ledGlow` |
| Row digit | Orbitron 900 | 26 | tabular | 44pt column, `ledGlow` |
| Status LED | Orbitron 900 | 12 | — | `live` + `liveGlow`; upcoming/final use `muted`, no glow |
| Guide channel no. | Orbitron 900 | 13 | — | gold, 40pt column |
| Body / caption | Space Mono 400 | 11 / 10 / 9 | — | records, footers, program subtitles |
| Header clock / counters | Orbitron 900 | 16 / 10 | — | gold / live |

Dynamic Type: display and digits scale with `.title` metrics, capped at AX1; body scales at default, capped at AX1.

## 3. Spacing, radii, hit targets

- Screen horizontal inset **12pt**. Section gap **12–14pt**. Row gap inside a league **6pt**.
- Radius **0** on panels, buttons, toggles, tab lamp. `SportsMetrics.cardRadius` (16) stays for sheets and the player only.
- Panel border **2pt** `border` plus inset 1pt `void` hairline. Hero panel border `live @ 0.45`; favorites category button `gold @ 0.5`.
- Rivets: 6pt circle in `border` with inset highlight, four corners, hero panel only.
- Team edge bars **5pt**, full row height (`away` left, `home` right).
- Filter switchboard: 38pt tall, 6pt gaps, LIVE / UPCOMING / FINAL flex-equal, fixed 66pt favorites cell holding 16pt team squares (top favorite gets a 1pt gold border).
- Score row **58pt**; guide row **62pt** + 2pt divider; settings row **50pt** (secondary rows 40pt).
- Hero panel padding 10 / 14 / 12 / 14. Digit columns `1fr 84pt 1fr`.
- WATCH filled: 36pt, pad 14, gold fill, `void` text, `ledGlow`. WATCH outline: 30pt visual, pad 8, 2pt gold border, gold text.
- Toggle: 52×26 box, 2pt border; knob 22×18 inset 2pt; on = gold + glow, off = `border`.
- Tab bar 80pt including 14pt safe-area pad, 2pt top border, 28×4 lamp above each label; active gold + glow.
- **Every tappable ≥ 44pt**: rows, filters, WATCH outline via `contentShape` 44pt, toggles 52×44.

## 4. Component inventory

| Component | Live | Upcoming | Final | Unmatched (no stream) |
|---|---|---|---|---|
| **Score row** (edge bars · abbr · LED · status · LED · abbr · WATCH) | digits gold; leader full, trailer 0.5 opacity; status `live` LED (`67'`, `Q4 3:12`, `▲ 7`) + caption (`2ND HALF`, `2 OUT`) | digits `–` in `muted`; status = start time in `muted` LED | digits gold, loser 0.5; status `FINAL` `muted` | same, **no WATCH**; row right padding closes to 12pt |
| **My Game hero** (first pinned favorite game) | hero bleed, digit boxes, mint `● LIVE · Q4`, clock LED, streams caption, filled WATCH | bleed; digits `–`; clock cell shows start time; filled WATCH if a stream is matched | bleed; `FINAL`; no button | caption `NO STREAM MATCHED`, no button |
| **League header** | 4×16pt league-color tick + Bebas 20 + right `N LIVE` mint LED | `N UPCOMING` muted | `N FINAL` muted | — |
| **Filter switchboard** | selected cell gold fill + glow, `void` text; others panel + muted | same | same | — |
| **Favorites cell** | 16pt team-color squares (max 3, then `+N` Bebas 12); tap opens `FavoriteTeamPickerView` | | | |
| **Guide row** (brand stripe · ch no. · name · progress bar) | bar fill `live` gradient 0.10→0.30, 2pt `live` right edge + glow, `LIVE` 8pt Orbitron right-aligned | bar `gold` gradient 0.08→0.22 at width 0 (not started), no badge | — | channel without a playable URL is not listed |
| **Guide Now-bar** | `NOW · N LIVE` mint fill chip + hour chips (`border` outline) | | | |
| **Settings row** | 28pt icon cell (1pt border) · Bebas 22 · value caption · chevron or toggle | | | |
| **Setup lamp card** | lamps: done = `live` + glow, pending = gold + glow, blocked = `danger`; right `SETUP n/3` + gold filled CTA | | | |
| **Ticker** (player, unchanged this drop) | keep current pills; adopt gold LED digits only | | | |

Brand stripe color: channel group → color map (sports red, movies purple, news blue, default `border`); no per-channel logo colors fetched.

## 5. States

| State | Scores | Guide | Settings |
|---|---|---|---|
| Loading (first) | switchboard shown; 3 skeleton panels in `panelGradient` with `border` shimmer, no LED | Now-bar + 6 skeleton rows | rows render; status values `…` in muted LED |
| Refreshing | header `●` blinks at 1 Hz | `▼ HH:MM` marker updates | — |
| Empty (filter) | one panel: Bebas 22 `emptyTitle`, Space Mono 11 `emptySubtitle`, outline gold CTA (`UPCOMING ▸` or `LEAGUES ▸`) | `NO CHANNELS IN THIS CATEGORY` panel + `CHOOSE CATEGORY` outline CTA | — |
| Error | panel with `danger` tick, `SCORES UNAVAILABLE` + error text, outline `RETRY` | `EPG UNAVAILABLE` + `RELOAD EPG` | Xtream status LED in `danger`: `EXPIRED` / `OFFLINE` |
| No playlist | `SetupChecklistCard` restyled as the lamp card at top | full-screen lamp card `LOAD A PLAYLIST FIRST` + gold CTA to Settings | lamp card at top (as rendered) |
| No favorites | no hero panel; favorites cell shows `★ PICK` gold outline | `★ FAVORITES` falls back to first populated group (existing rule) | `FAVORITES` lamp gold pending |
| Partial scores warning | one-line strip under the switchboard: `danger` tick + Space Mono 10 text, no panel | — | — |

## 6. Platform deltas

| Surface | Do | Don't |
|---|---|---|
| Phone iOS | all of the above; `gridDot` ground; Liquid Glass only on floating player controls and sheets | no glass or material on panels, rows, or tab bar (opaque `panelGradient`); no rounded corners on panels |
| Phone Android | same tokens via `Theme.kt`; `drawBehind` grid; bundled fonts in `res/font`; edge bars via `drawWithContent`; system nav bar colored `panel` | no Material3 elevation shadows; ripple gold @ 0.2 only |
| Apple TV / Android TV | keep Netflix rails (`ScoresTVRail`); restyle cards to panel + edge bars + LED digits at 44; focus = 3pt gold border + `ledGlow`, `focusScale` 1.045; guide keeps 88pt rows and adds brand stripe | no phone Now-bar list, no pop-out, no switchboard (keep tvOS chips), no 2pt hairlines (3pt minimum at 1080p) |

## 7. Motion

Switchboard selection crossfade 150 ms ease-out. Refresh `●` blink 1 Hz. LED glow is static, no pulse. TV focus uses existing `SportsTVFocusMotion`.

## 8. Acceptance (check on device)

- [ ] Scores: rows 58pt; digits Orbitron 26 gold with glow; trailing side 50% opacity; 5pt team-color edge bars both sides.
- [ ] Scores: first pinned favorite game renders as the hero with both team colors bleeding in; with no favorites, no hero and `★ PICK` in the favorites cell.
- [ ] Scores: unmatched games show no WATCH; matched rows show outline WATCH, hero shows filled WATCH; both hit ≥ 44pt.
- [ ] Scores: switchboard selected cell gold, others panel; switch animates 150 ms.
- [ ] Guide: rows 62pt with brand stripe and gold channel number; progress width = elapsed fraction of the current program; live rows mint with `LIVE`, not-started rows gold at width 0.
- [ ] Guide: `NOW · N LIVE` count equals the number of rows carrying `LIVE`.
- [ ] Settings: lamp states match `SetupChecklist` (done mint, pending gold, blocked red); toggles 52×26 with gold glow when on.
- [ ] All three: tab bar 80pt with lamp above the active label; no glass on content; grid ground visible on OLED without banding.
- [ ] Fonts bundled and licensed in `Info.plist` / `res/font`; no runtime font fetch.
- [ ] VoiceOver / TalkBack: rows read "Away, score, status, Home, score, Watch"; contrast gold on void ≥ 7:1, mint on void ≥ 9:1, muted on void ≥ 4.5:1.
