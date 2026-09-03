# 006 · Jumbotron TV

**Status: approved-for-impl** (2026-09-03). Directions for Grok to build Apple TV + Android TV
with behavioural and visual **parity to the phone Jumbotron** that shipped on `ui/005-jumbotron`.
`SPEC.md` is the build file; `index.html` is the reference render. Phone lock is
`sketches/005-jumbotron/` — read it first; this drop only adds the 10-foot adaptation.

## Intent
Same product on the couch: the 005 palette, LED digits, team edge bars, brand stripe and WATCH
rule, applied to the TV surfaces that already exist (Netflix-style Scores rails with My Games
first, 88pt Guide timeline rows, Settings hub) — not the phone's dense chrome scaled up. Same
three tabs, same favorites model, same EPG pipeline and the same speed laws this branch just
landed (streaming XMLTV parse, `EpgStore`, throttled publishes, negative short-EPG cache, honoured
playlist refresh), plus the two things a TV needs that a phone does not: in-session guide refresh
on a process that stays open for days, and a first rail paint that never waits on EPG.

## Screens in this drop
- Scores · Apple TV (frame 1) and Android TV (frame 4, shell delta)
- Guide · Apple TV (frame 2); Android TV differs only by the shell and keeps its existing TV timeline/grid rows
- Settings · Apple TV (frame 3); Android TV adds the ALERTS panel and uses the bottom tab bar

Player chrome is type-only (SPEC §8). Category picker, favorite-team picker, stream picker and
sub-settings keep their current structure with 006 tokens.

## Copy from the HTML
Card/rail anatomy (edge bars, logo + abbr, LED status, digit boxes, caption + WATCH), hero card,
chip row, guide channel cell (stripe · LED no. · name), program blocks and now marker, settings
two-column hub, lamp card, Android bottom tab bar with lamp, focus ring (3pt gold + glow + 1.045),
3pt hairlines, 12pt grid ground, 60pt safe inset.

## Ignore in the HTML
Fake data (teams, scores, channel numbers, provider, dates, the 19:42 clock, the 5 LIVE counter),
Google Fonts `<link>` (fonts are already bundled on both stacks), the tvOS tab strip at the top of
frames 1–3 (it stands in for the **system** tvOS `TabView`, which Grok must keep — tint it gold, do
not replace it), the unicode glyphs used as icons (use the existing SF Symbols / vector icons), and
anything blocked: cast, multiview, remote push, a Channels tab, TV pop-out.

## tv.png
Not rendered: this workspace has no browser/rasteriser (no Chromium, Playwright or wkhtmltoimage).
Open `index.html` in a browser at 100 % — each frame is exactly 1920×1080 — and screenshot the
first frame if a freeze-frame is wanted in the folder.

## Non-goals
No new navigation, data flow, matching or player work. No phone changes — 005 screenshots must be
pixel-identical after this drop. No further god-object splits beyond the Android `EpgUiState`
that SPEC §7 requires for TV invalidation.
