# 005 · Jumbotron

**Status: approved-for-impl** (chosen 2026-09-02 from five directions; canvas kept at
https://claude.ai/code/artifact/ecb76593-deda-436e-8694-5ec8af6cc449, page "Directions A–E" is exploration only).

## Intent
Arena-scoreboard take on the existing brand: void navy ground, gold LED score digits with glow,
live mint status, riveted panels, and **color from the teams** (team-color edge bars on every
score row, team-color bleed behind the My Game board, channel-brand stripe on guide rows).
Structure is unchanged: Scores · Guide · Settings, favorites rail, My Games pin, gold WATCH.

## Screens in this drop
- Scores · phone
- Guide · phone (timeline "list" layout replaced by the Now-bar list shown here; card grid unchanged)
- Settings · phone (root hub only; sub-pages keep their current Form styling with new tokens)

Everything else (player, ticker, detail sheet, team picker, Apple TV, Android TV) is later.
No TV PNG in this drop; TV adaptation is called in SPEC only.

## Copy from the HTML
Layout, type scale (Bebas Neue display / Orbitron digits / Space Mono body), color, component
anatomy: panel, edge bars, LED digit box, WATCH (filled + outline), switchboard filter, lamp
setup card, square toggle, tab bar lamp.

## Ignore in the HTML
Fake data (teams, scores, channel numbers, provider name, dates), the 19:42 header clock,
the "2ND & 7 · BUF 34" down-and-distance line, the header "5 LIVE" counter, Google Fonts
`<link>` (bundle fonts), and anything blocked: cast, multiview, remote push, a Channels tab,
TV pop-out.

## Non-goals
Do not rebuild navigation, data flow, matching, or the player; this is a re-skin plus new row
anatomy on three existing screens.
