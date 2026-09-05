# SportsDash agent instructions

Durable work lives on GitHub issues and PRs. Chat, Herdr panes, and Hermes kanban are not the sprint log.

## Board

- Before coding: `gh issue list` then `gh issue view <n>` (or create an issue).
- Branch from `main`: `feat/<n>-short-name` or `fix/<n>-short-name`.
- Open a draft PR early with `Fixes #<n>` or `Refs #<n>`.
- End of session: PR or issue comment — shipped, blocked, next step.

```bash
gh issue list
gh pr status
```

GitHub account for this repo: `chumpuckai-devteam` (`gh` / `git`).

## Product constraints

- Monorepo: `SportsDash/` SwiftUI iOS+tvOS, `android/` Compose phone+TV.
- Engine: VLC / libVLC. Tabs: Scores · Guide · Settings.
- Cast, multiview, and remote push stay blocked unless an issue explicitly unblocks them.
- Do not start feature work while Apple CI is red on `main`.
- Mac dogfood: `xcodegen generate && pod install`, open `SportsDash.xcworkspace`.

## CLIs

Prefer Herdr + Pi. Spawn `claude`, `grok`, or `agy` only when needed. Keep user focus on Pi.
