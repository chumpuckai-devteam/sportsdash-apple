# S-PLAYER.1 Spike — MPVKit LGPL + Auto TS/HLS router

**Date:** 2026-08-01  
**SHA:** (see git after push)  
**Kanban:** `t_85a46eea`

## What shipped

### 1. Auto stream-type router (product default)
`StreamContainer.detect(url)` classifies playback URLs:

| Detection | Primary engine |
|-----------|----------------|
| **HLS** (`.m3u8`, hls tokens) | **AVPlayer** (`KSAVPlayer`) |
| **TS** (`.ts`, `/live/` without m3u8, format=ts) | **KSPlayer FFmpeg** (`KSMEPlayer`) |
| Unknown | KS (IPTV-safe default) |

Settings → **Auto · TS→KS · HLS→AV · Default**

Fallback still tries the other KS backend when enabled. Candidate URL matrix (TS↔m3u8) unchanged.

### 2. MPVKit LGPL spike (opt-in)
- SPM: `https://github.com/mpvkit/MPVKit.git` product **`MPVKit` only** (never `MPVKit-GPL`)
- `MPVPlayerController` + Metal host + `PlayerSurface` switch
- Settings: **MPV (libmpv) · Spike**
- HLS still forced to AV even if MPV selected (matches your request)
- MPV failure → fall back to KS/AV when fallback on

### 3. Chrome
Player badge shows `Auto/TS`, `Auto/HLS`, `KS`, `AV`, or `MPV`.

## Dogfood

```bash
git pull origin main
xcodegen generate   # resolves MPVKit binaries — first time is large/slow
```

1. Settings → Video player → **Auto** (default after migration v3)
2. Play a **TS** live channel → badge `Auto/TS` → expect KS
3. Play an **m3u8** → badge `Auto/HLS` → expect AV
4. Optional: pick **MPV · Spike** on a TS channel

## Go / no-go (after your device pass)

| Path | Go if… | No-go if… |
|------|--------|-----------|
| **Keep Auto + KS/AV** | TS and HLS both play; badges match | Detection wrong for your panel URLs — send one redacted URL shape |
| **Promote MPV hard** | MPV spike stable ≥2 min TS; tvOS builds; size OK | Link/MoltenVK crash; binary too heavy; tvOS fail |
| **Buy KS LGPL** | You want store ship without engine rewrite | — |
| **VLC Path A** | MPV packaging fails twice | — |

## Package status (2026-08 build fix)

**MPVKit SPM was removed from `Project.yml`** after Mac Xcode reported:

- Missing package product `KSPlayer`
- Missing package product `MPVKit`

Adding MPVKit to the package graph broke resolution for the whole project. **Auto TS→KS / HLS→AV still ships on KSPlayer only.**

MPV source (`MPVPlayerController`) remains behind `#if canImport(Libmpv)` and is not linked until a future packaging pass.

### Recover green build
```bash
cd ~/agency/sportsdash-apple
# Quit Xcode
git checkout -- SportsDash.xcodeproj/project.pbxproj
git pull origin main
rm -rf ~/Library/Developer/Xcode/DerivedData/SportsDash-*
xcodegen generate
open SportsDash.xcodeproj
# File → Packages → Reset Package Caches (if needed)
# File → Packages → Resolve Package Versions
```
Clean Build Folder → Run.
