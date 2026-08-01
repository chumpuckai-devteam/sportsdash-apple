# Joint review: NuvioMobile player stack vs SportsDash IPTV

**Date:** 2026-08-01  
**Sources:** [NuvioMedia/NuvioMobile](https://github.com/NuvioMedia/NuvioMobile) (`cmp-rewrite`, local clone), submodule [NuvioMedia/MPVKit](https://github.com/NuvioMedia/MPVKit) @ `d5cf091`, SportsDash `docs/video-player-options.md` + `PlaybackController`  
**Roles:** backend-dev (stream formats / URL matrix) · mobile-engineer (iOS/tvOS integration) · tech lead (product decision)

---

## 1. What Nuvio actually uses

Nuvio is a **Kotlin Multiplatform / Compose** media hub (Stremio addons), **not** a SwiftUI IPTV app. Playback is split by platform:

| Platform | Primary hard engine | Soft / system engine | Notes |
|----------|--------------------|----------------------|--------|
| **iOS** | **libmpv** via custom **MPVKit** + `MPVPlayerBridge.swift` | Not first-class (mpv is *the* path) | Metal/Vulkan (`gpu-next` + MoltenVK), VT hwdec |
| **Android** | **Media3 ExoPlayer** first | **libmpv** fallback on Exo failure | Explicit dual-engine router |

### iOS path (relevant to SportsDash)

- Native bridge: `iosApp/iosApp/Player/MPVPlayerBridge.swift`
- Engine: `mpv_create` → `vo=gpu-next`, `gpu-api=vulkan`, `gpu-context=moltenvk`, `hwdec=videotoolbox`
- Headers: `http-header-fields` for request headers
- State: load/play/pause/seek, cache (`demuxer-cache-time`, `paused-for-cache`), tracks, subs
- Package: SPM `MPVKit` with **LGPL** product (`MPVKit`) and separate **GPL** product (`MPVKit-GPL`) binary xcframeworks (FFmpeg 8.x class)

### Android path (context only)

- `PlayerEngine.android.kt`: ExoPlayer → on error switch to Libmpv
- Same *idea* as SportsDash hybrid (soft then hard)

### What Nuvio is **not**

- Not an Xtream/M3U sports EPG client  
- Not SwiftUI-first; Compose + thin UIKit bridge  
- App itself is **GPL-3.0** (repo LICENSE) — **cannot copy their app code into closed SportsDash**  
- MPVKit binaries/patterns can still **inform** a clean-room SportsDash integration under **LGPL MPVKit** product rules

---

## 2. Backend-dev: stream formats (IPTV reality)

Most Xtream/M3U live sports stacks look like:

| Format | Typical URL shape | AVPlayer | FFmpeg/mpv/VLC |
|--------|-------------------|----------|----------------|
| **MPEG-TS over HTTP** | `…/live/user/pass/id` or `.ts` | Weak | Strong |
| **HLS wrapping TS segments** | `.m3u8` of `.ts` parts | Good if Apple-ish | Strong |
| Messy HLS | rolling windows, bad tags | Fails often | Strong |
| Headers / UA | VLC-like UA common | Limited | First-class |

SportsDash already prefers **TS** (`preferredLiveFormat = .ts`) and builds candidate URLs in `IptvService.playbackURLCandidates`. Backend recommendation stands:

1. Keep **TS-first** for live when provider supports it.  
2. Always offer **m3u8** candidates as fallback.  
3. Inject **User-Agent** + optional headers at the engine layer (Nuvio’s `http-header-fields` pattern).  
4. Hard engine must demux **mpegts** and tolerate infinite live streams (no fixed duration).  
5. Do not depend on provider “fixing” streams to AVPlayer-clean HLS.

**Backend does not need a new server** for player choice — only stable URL matrix + optional stream probe later.

---

## 3. Mobile-engineer: engine comparison for SportsDash

| Engine | TS/IPTV | iOS+tvOS | License (closed app) | SwiftUI fit | Effort vs today |
|--------|---------|----------|----------------------|-------------|-----------------|
| **KSPlayer/FFmpeg (current)** | Excellent | Yes | **GPL public** → App Store risk | Already integrated | — |
| **AVPlayer** | Weak on raw TS | Best | Safe | Best PiP/AirPlay | Keep as soft path |
| **VLCKit 3.7** | Excellent (TS reference) | MobileVLCKit + TVVLCKit | **LGPL** (dynamic FW duties) | Medium (UIView) | M — Path A was parked |
| **MPVKit LGPL (Nuvio-class)** | Excellent (FFmpeg demux) | Yes (SPM iOS/tvOS) | **LGPL** build if not `-GPL` product | Medium–High (C API + Metal) | L — new hard path |
| Copy Nuvio app code | N/A | N/A | **GPL-3.0 app** — do not | N/A | Forbidden for closed binary |

### Lessons worth stealing from Nuvio (patterns, not code)

1. **Hard engine = libmpv/FFmpeg** for anything AVPlayer rejects.  
2. **Protocol/bridge** between UI chrome and engine (`NuvioPlayerBridge` ↔ our `PlaybackController` / future `StreamPlaying`).  
3. **Header injection** for IPTV CDNs.  
4. **Cache/buffer observables** for spinner UX (`paused-for-cache`).  
5. Android-style **auto fallback** Exo→mpv maps to our AV→hard policy.

### Risks of adopting MPVKit as SportsDash primary

| Risk | Detail |
|------|--------|
| Integration size | New Metal/Vulkan surface, audio session, PiP/AirPlay weaker than AV |
| tvOS dogfood | MPVKit claims tvOS; SportsDashTV must be proven on device |
| Binary weight | Same class as FFmpegKit/KSPlayer — no free lunch |
| Maintainer signal | Upstream mpvkit README historically “learning” posture; Nuvio forks/pins their own branch — we’d own breakage |
| GPL footgun | Must depend on **`MPVKit` LGPL product only**, never `MPVKit-GPL` |
| VLC Path A history | Team already parked VLC packaging once; mpv is a second hard-engine project |

---

## 4. Joint recommendation

### Do **not**

- Port Nuvio’s KMP/Compose player wholesale.  
- Ship public **KSPlayer GPL** into a closed App Store build without LGPL deal.  
- Go **AVPlayer-only** while `preferredLiveFormat = .ts`.

### Do (ordered)

| Priority | Action | Owner |
|----------|--------|--------|
| **P0** | Keep hybrid architecture: **AVPlayer (clean HLS) + hard engine (TS/messy)** behind one controller | mobile |
| **P1** | **Spike MPVKit LGPL** on iOS (one live TS + one m3u8) with SportsDash chrome; measure start time, CPU, TS stability vs KSPlayer | mobile |
| **P1** | Parallel: re-evaluate **VLCKit Path A** only if MPV spike fails packaging/tvOS — LGPL, proven IPTV | mobile |
| **P1** | Or buy **KSPlayer LGPL** if Samir wants minimal code churn | product |
| **P2** | Formalize `StreamPlaying` protocol + auto-router (TS → hard first; clean m3u8 → AV first) | mobile |
| **P2** | Backend: document URL candidate order + UA; optional HEAD/probe later | backend |
| **P3** | Android Media3+mpv (Nuvio pattern) when `sportsdash-android` starts | android |

### Product default (target)

```text
if preferredFormat == TS OR url looks like raw TS:
    HardEngine first (mpv LGPL or VLC LGPL or KSPlayer-LGPL)
    fallback → AVPlayer once
else:
    AVPlayer first
    on fail/no-frame N seconds → HardEngine
```

Keep Settings override (already exists).

---

## 5. Why Nuvio still matters

Nuvio is strong evidence that a **2026 production media app** bets on:

- **libmpv + FFmpeg** as the portable hard path  
- **System player** where it wins (Exo/AV)  
- **Explicit fallback**, not one engine forever  

For SportsDash IPTV (TS-heavy), that validates **hard demuxer required**. The choice is **which LGPL-safe hard engine**, not whether we need one.

---

## 6. Spike acceptance (if Samir says go)

1. Play Xtream **TS** live ≥ 2 min, no audio desync black screen.  
2. Play **m3u8** candidate.  
3. Header/UA injection works on Xtream-class hosts.  
4. iPhone + Apple TV simulator/device builds.  
5. License audit: link only LGPL MPVKit (or VLCKit dynamic), attribution in Settings.  
6. No GPL Nuvio app source copied.

---

## 7. References

- https://github.com/NuvioMedia/NuvioMobile  
- https://github.com/NuvioMedia/MPVKit  
- https://github.com/mpvkit/MPVKit (upstream binaries)  
- SportsDash `docs/video-player-options.md`, `docs/LGPL-NOTICE.md`  
- In-tree Nuvio paths: `iosApp/iosApp/Player/MPVPlayerBridge.swift`, `composeApp/.../PlayerEngine.android.kt`
