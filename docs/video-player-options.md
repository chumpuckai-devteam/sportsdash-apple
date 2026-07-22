# SportsDash Apple — Video Player Decision Brief

**Date:** 2026-07-22  
**Status:** Decision brief (no implementation)  
**Scope:** Live IPTV playback on **iOS 17+** and **tvOS 17+** (shared SwiftUI app)  
**Repo context:** `SportsDash` already ships a hybrid **KSPlayer (FFmpeg/KSMEPlayer) primary + AVPlayer (KSAVPlayer) fallback**, with Settings engine picker, LIVE jump, aspect prefs, PiP hooks, and custom chrome (`PlaybackController`, `KSPlayerSurface`, `PlayerView`).

---

## 1. Problem statement

SportsDash plays **provider IPTV** (Xtream Codes / M3U), not only polished OTT HLS:

| Stream reality | Why it hurts players |
|----------------|----------------------|
| HLS `.m3u8` that is clean, multi-bitrate, Apple-friendly | AVPlayer thrives |
| HLS that is non-spec (bad EXT-X tags, rolling windows, odd codecs) | AVPlayer fails or stalls; FFmpeg/VLC often recover |
| MPEG-TS over HTTP (`.ts`, raw TS, infinite live TS) | AVPlayer support is weak/inconsistent; demuxers matter |
| Custom headers / UA / referrers | Need header injection on the player stack |
| Live edge, reconnect, mid-stream codec changes | Needs aggressive live buffering + retry policy |

**Current stack pain (as reported / observed in project):**

1. **FFmpegKit SPM friction** — binary modules emit Xcode/SPM warnings around prohibited flags (e.g. `-D_THREAD_SAFE`, `-Wl,-framework,Cocoa` style packaging issues) and Xcode 16 CI friction.
2. **GPL licensing risk** — public [KSPlayer](https://github.com/kingslay/KSPlayer) is **GPL-3.0**. Shipping a **closed App Store binary** while linking GPL player code is not a safe default; author documents a **paid LGPL** path.
3. **Heavy package** — FFmpeg (+ optional libass/mpv bits via kingslay/FFmpegKit) dominates binary size and cold resolve/link time.
4. Product still needs **robust messy-stream playback** (primary SportsDash differentiator vs a plain AVPlayer demo).

**Non-goals for this brief:** implementing a new engine, multiview, DRM/FairPlay studio OTT, or Android Media3 (separate repo).

---

## 2. Decision criteria (weighted for SportsDash)

| Criterion | Weight | Notes |
|-----------|--------|--------|
| Live IPTV / TS / messy HLS robustness | Critical | Xtream/M3U is the product |
| App Store closed-binary license safety | Critical | Private app; cannot casually ship GPL |
| iOS 17+ **and** tvOS 17+ | Critical | One shared codebase |
| SwiftUI integration / keep custom chrome | High | Already built UHF-style UI on top of engine |
| PiP, AirPlay, background audio | High (iOS) | Sports second-screen habits |
| Binary size / cold start / CI pain | Medium-High | FFmpegKit already hurts |
| Maintenance health 2025–2026 | Medium-High | Avoid abandoned iOS ports |
| Migration cost from current KSPlayer hybrid | Medium | Prefer M or S over greenfield rewrite |

---

## 3. Current SportsDash baseline

**Facts (repo):**

- `Project.yml` depends on SPM `https://github.com/kingslay/KSPlayer.git` (`branch: main`) for **iOS + tvOS** targets.
- `PlaybackController` configures `KSOptions.firstPlayerType` / `secondPlayerType` between `KSMEPlayer` (FFmpeg) and `KSAVPlayer` (AVPlayer).
- Prefs: Auto / FFmpeg / AVPlayer, preferred live format TS vs M3U8, UA defaulting to a VLC-like string, hardware decode, fallback toggle.
- README already warns: *KSPlayer public package is GPL; commercial/LGPL may be required for closed App Store binary.*
- ARCHITECTURE.md still says “KSPlayer or VLCKit fallback behind a protocol `StreamPlaying`” — the **protocol abstraction is the right long-term shape**; implementation today is KSPlayer-centric rather than a thin multi-backend protocol.

**Implication:** Architecture (multi-engine + auto fallback) is correct. The open question is **which hard engine** is legally and operationally sustainable.

---

## 4. Option comparison

### 4.1 AVPlayer / AVKit (native)

| Dimension | Assessment |
|-----------|------------|
| **IPTV / HLS / TS robustness** | **Excellent** on clean HLS (Apple’s reference path). **Poor–fair** on raw MPEG-TS, broken playlists, exotic codecs, and many Xtream “live” URLs that are not Apple HLS. Not sufficient alone for SportsDash’s hard streams. |
| **iOS + tvOS** | First-class both platforms (AVKit / AVPlayerViewController / `VideoPlayer` / custom `AVPlayerLayer`). |
| **SwiftUI effort** | **Low.** `VideoPlayer`, or `UIViewControllerRepresentable` for full chrome control. You already wrap AV path via KSPlayer’s `KSAVPlayer`. |
| **License / App Store** | Apple SDK. **No GPL/LGPL copyleft.** Safest legal baseline. |
| **Binary size / cold start** | **Best-in-class** (~0 app delta). Fastest start. |
| **PiP / AirPlay / background** | **Best-in-class** on iOS (AVPictureInPictureController, route sharing, `audio` background mode). tvOS AirPlay receiver story is platform-native. |
| **Maintenance 2025–2026** | Apple-maintained indefinitely. |
| **Pros** | Zero license drama; smallest app; best system integration; ideal default for clean `.m3u8`. |
| **Cons** | Will fail a meaningful % of IPTV sources; limited demux/codec surface; less control over low-level live buffer than FFmpeg/VLC. |
| **vs SportsDash** | Must remain **one engine in a hybrid**, never the only engine. |

**Sources:** Apple AVFoundation/AVKit; industry IPTV practice (UHF-class apps do not ship AVPlayer-only).

---

### 4.2 KSPlayer + FFmpegKit (current)

| Dimension | Assessment |
|-----------|------------|
| **IPTV / HLS / TS robustness** | **Excellent.** FFmpeg demux/decode path (`KSMEPlayer`) is purpose-built for messy live; Annex-B / live hardware decode called out in upstream feature matrix. Same family of stack used by multiple App Store IPTV apps listed by upstream (UHF, APTV, Smart IPTV, Snappier, etc.). |
| **iOS + tvOS** | Official: iOS 13+, tvOS 13+, macOS, visionOS. Matches SportsDash deployment targets. |
| **SwiftUI effort** | **Low (already done).** `KSVideoPlayer` + Coordinator; Metal shaders; track selection API already wired in `PlaybackController`. |
| **License / App Store** | **Public default = GPL-3.0** → linking into a closed binary is a **compliance problem** (copyleft). Upstream offers **paid LGPL** (personal: monthly donation floor **$15/dev**, revenue-share style **3–15%** of App Store income, prepaid 6 months; enterprise custom; requires in-app attribution that kernel is KSPlayer; source delivered via private repos, not redistributable). Author states GPL OK for TestFlight until store ship. **FFmpeg itself** is LGPL or GPL depending on build flags — kingslay builds are tied to their packaging. |
| **Binary size / cold start** | **Heavy.** Large xcframework graph (libav*, gnutls, dav1d, optional ass/mpv/placebo, etc.). Slow SPM resolve; first `xcodebuild` painful; Metal toolchain footgun noted in README. |
| **PiP / AirPlay / background** | PiP supported upstream (including subtitle-in-PiP on LGPL matrix). AirPlay via AV path / options (SportsDash already passes `.allowAirPlay` in places). Background audio via app `UIBackgroundModes=audio` + session config — works but FFmpeg path is more work than pure AVPlayer. |
| **Maintenance 2025–2026** | **Active** (commits through 2026-07; stars ~1.6k). Single-maintainer risk; commercial IPTV dependency concentration. |
| **Pros** | Best fit to *current code*; strongest “works like UHF” story; Swift-native API; hybrid AV fallback built-in. |
| **Cons** | GPL landmine if you ship closed without LGPL deal; FFmpegKit SPM/Xcode friction; binary bloat; ongoing fee if LGPL; vendor lock to one author for legal path. |
| **vs SportsDash** | Technically great; **legally incomplete for App Store** without LGPL purchase or open-sourcing SportsDash. |

**Sources:** [KSPlayer README](https://github.com/kingslay/KSPlayer) (license table, app list, platforms); [KSPlayer #731 LGPL scheme](https://github.com/kingslay/KSPlayer/issues/731); [kingslay/FFmpegKit](https://github.com/kingslay/FFmpegKit) Package.swift (heavy binary product set); arthenica/ffmpeg-kit retired → FFmpegKitNext (context only; SportsDash uses kingslay fork via KSPlayer).

---

### 4.3 MobileVLCKit / TVVLCKit (libVLC)

| Dimension | Assessment |
|-----------|------------|
| **IPTV / HLS / TS robustness** | **Excellent — reference-class** for “weird servers, raw TS, odd containers.” libVLC exists specifically for media AVFoundation will not touch. Widely used in IPTV clients historically. |
| **iOS + tvOS** | **Yes, but split artifacts:** `MobileVLCKit` (iOS) + `TVVLCKit` (tvOS) + `VLCKit` (macOS). Requirements historically iOS 8.4+ / tvOS 10.2+. **CocoaPods / Carthage binary** are first-class; **SPM is community-only** (several small `MobileVLCKit-SPM` wrappers — not VideoLAN-official). |
| **SwiftUI effort** | **Medium.** ObjC API (`VLCMediaPlayer`, drawable `UIView`). Need `UIViewRepresentable` / tvOS focus-friendly chrome. You keep SportsDash chrome; you do **not** get KSPlayer’s SwiftUI player for free. |
| **License / App Store** | **LGPLv2.1 (or later).** Proprietary apps **may** ship it **if LGPL obligations are met**, typically: distribute libVLC as a **replaceable dynamic framework**, publish any **modifications** to VLCKit/libVLC, and inform users of LGPL rights / offer corresponding source. **Does not force open-sourcing SportsDash app code** the way GPL does. Consult counsel for final App Store packaging (static vs dynamic link). VideoLAN FAQ states this explicitly. |
| **Binary size / cold start** | **Heavy** (order-of-magnitude tens of MB per platform slice; often cited ~30–60MB class depending on slice/thinning). Cold start heavier than AVPlayer; comparable ballpark to FFmpegKit-class stacks. |
| **PiP / AirPlay / background** | **Weaker than AVPlayer.** PiP is not a first-class “free” AVKit feature; apps often implement custom mini-player (SportsDash already has floating mini player) or bridge carefully. AirPlay external playback is limited vs AVPlayer. Background audio possible with session config but more manual. |
| **Maintenance 2025–2026** | **Healthy.** CocoaPods shows **MobileVLCKit / TVVLCKit 3.7.x** releases into **2026-02** (e.g. 3.7.3). VLC-iOS app remains actively developed. VLC 4.x pods still alpha historically — plan on **3.7 stable** unless you intentionally track 4.x. |
| **Pros** | LGPL without per-seat royalty to a single indie author; legendary format tolerance; official tvOS pod; independent of KSPlayer GPL; clears FFmpegKit SPM warning class by not using that package. |
| **Cons** | Integration rewrite of hard path; dual pod/SPM awkwardness with pure XcodeGen+SPM workflow; PiP/AirPlay regressions vs AV-first; ObjC bridging; large binary remains. |
| **vs SportsDash** | Best **open LGPL hard-engine** candidate if you will not buy KSPlayer LGPL. |

**Sources:** [VLCKit README](https://code.videolan.org/videolan/VLCKit) (LGPL, pods, use-cases); CocoaPods version history MobileVLCKit/TVVLCKit 3.7.3 (2026-02); VideoLAN LGPL FAQ in README.

---

### 4.4 Strong alternatives

#### A) MPVKit / libmpv wrappers (`mpvkit/MPVKit`)

| Dimension | Assessment |
|-----------|------------|
| Robustness | Strong (mpv + FFmpeg 8.x). Good live/TS potential. |
| Platforms | iOS, macOS, tvOS, visionOS SPM binaries. |
| License | **LGPL-3.0** default builds; **GPL** if `enable-gpl` / `-GPL` binaries (e.g. samba). |
| SwiftUI | Medium–High effort (C API / thin Swift layers; not a full IPTV player UI). |
| Maintenance | Pushed 2026-07, but README warns: *“only suitable for learning libmpv and will not be maintained too frequently.”* |
| Size | Heavy (FFmpeg-class). |
| **Verdict** | Interesting **experiment / spike**, **not** production primary for SportsDash in 2026 without a dedicated maintainer commitment. |

#### B) IJKPlayer (bilibili/ijkplayer and ports)

| Dimension | Assessment |
|-----------|------------|
| Robustness | Historically good on mobile; FFmpeg n3.4-era upstream. |
| Platforms | iOS ports exist; ecosystem skews **Android**. |
| License | **GPL-2.0** (upstream) — same closed-binary problem class as KSPlayer GPL. |
| Maintenance | Stars huge historically; **iOS momentum is stale** relative to KSPlayer/VLC (last notable upstream activity much quieter; not a modern Apple-first bet). |
| **Verdict** | **Do not choose** for new SportsDash work. |

#### C) GStreamer

| Dimension | Assessment |
|-----------|------------|
| Robustness | Excellent pipelines; industrial media framework. |
| Platforms | Official **iOS/tvOS xcframework** docs (min iOS 12+ in current docs). |
| License | **LGPL** core (plugin license matrix must be audited per plugin). |
| SwiftUI | **High effort** (C API, pipeline design, audio session, video sink). |
| Size | Very large if “batteries included.” |
| **Verdict** | Overkill unless you need complex graph processing (transcode, multi-branch). Not the shortest path to “play Xtream live.” |

#### D) Commercial OTT SDKs (Bitmovin, THEOplayer, JW, etc.)

| Dimension | Assessment |
|-----------|------------|
| Robustness | Outstanding for **spec HLS/DASH + DRM + analytics**. |
| IPTV messy TS / Xtream | **Usually the wrong tool** — optimized for packager-controlled OTT, not shady M3U panels. |
| License | Commercial proprietary; App Store fine; **costly**. |
| tvOS | Often supported; verify SKU. |
| **Verdict** | Only if SportsDash pivots to licensed OTT/rights-managed content. **Not recommended** for current Xtream/M3U live sports panel use case. |

#### E) “Build our own FFmpeg” / bare FFmpegKitNext

Possible but you re-own demux, sync, Metal/CVPixelBuffer render, audio tap, track selection, live edge — i.e. rewrite KSPlayer. **Effort L–XL.** Only makes sense with full-time media engineers.

---

## 5. Side-by-side matrix

| | AVPlayer | KSPlayer+FFmpeg (GPL public) | KSPlayer LGPL (paid) | VLCKit 3.7 | MPVKit | GStreamer | Commercial OTT |
|--|----------|------------------------------|----------------------|------------|--------|-----------|----------------|
| Messy IPTV/TS | Weak | Excellent | Excellent | Excellent | Strong | Excellent | Weak–Fair |
| Clean HLS | Excellent | Excellent | Excellent | Excellent | Strong | Strong | Excellent |
| iOS 17 | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| tvOS 17 | Yes | Yes | Yes | Yes (TVVLCKit) | Yes | Yes | Often |
| SwiftUI effort | Low | Low (done) | Low (done) | Medium | Med–High | High | Low–Med |
| Closed App Store | Safe | **Unsafe** | Safe* | Safe* (LGPL duties) | Safe* (LGPL build) | Safe* | Safe |
| Ongoing $ | $0 | $0 (legal risk) | $$/mo or enterprise | $0 (+ counsel time) | $0 | $0 | $$$ |
| Binary weight | Tiny | Heavy | Heavy | Heavy | Heavy | Heavier | Medium |
| PiP/AirPlay | Best | Good | Good | Fair | Fair | Fair | Good |
| Maint. 2026 | Apple | Active (single) | Active (single) | Active (org) | Weak promise | Org | Vendor |
| Migrate from today | S (already there) | — | **S** | **M** | L | L | M–L |

\*LGPL still has packaging/attribution/source obligations — cheaper than GPL infection, not “zero process.”

---

## 6. Architecture recommendation (independent of vendor)

Keep (or formalize) a **multi-engine** design:

```text
StreamPlaying (protocol)
├── AVPlayerEngine     // default for clean HLS / system features
├── HardEngine         // VLCKit OR KSPlayer-LGPL (FFmpeg)
└── AutoRouter         // try preferred → on error/timeout swap once
```

**Auto policy (suggested product behavior):**

1. If URL looks like Apple-friendly HLS (`.m3u8`, no forced TS pref) → **AVPlayer first**.
2. If preferred format is **TS**, or AVPlayer errors/no-frame within N seconds → **Hard engine**.
3. User override in Settings remains (you already have this UX — keep it).
4. One-tap “Try other engine” on error (already partially present).

This preserves SportsDash chrome (scores strip, EPG, ratings chips, LIVE jump) regardless of decoder underneath.

---

## 7. RECOMMENDATION

### Primary pick for production

**Hybrid: AVPlayer (system) + hard IPTV engine, with Auto router.**

Choose the hard engine based on business constraint:

| Path | Hard engine | When to take it |
|------|-------------|-----------------|
| **Path A — Recommended default** | **VLCKit 3.7** (`MobileVLCKit` + `TVVLCKit`) | You want App Store-safe **LGPL without ongoing royalty** to KSPlayer; willing to spend a **Medium** migration; accept CocoaPods/binary integration beside XcodeGen. |
| **Path B — Lowest code churn** | **KSPlayer paid LGPL** + keep `KSAVPlayer` | You want to **ship soon** with current UX/quality; OK with **$15+/dev/mo** (or enterprise deal) + in-app KSPlayer attribution; accept continued FFmpeg binary weight (SPM warnings may remain — budget CI time). |

**Default recommendation for SportsDash product direction:** **Path A (AVPlayer + VLCKit)** as the **production** target stack.

**Rationale (short):**

1. Live IPTV **requires** a non-AVFoundation demuxer — AVPlayer alone is a non-starter.
2. Public **KSPlayer GPL** is not an acceptable long-term App Store posture for a closed app.
3. **VLCKit LGPL** is the industry-standard way to get libVLC robustness without GPL-infecting app code, with **official tvOS** binaries and 2026 releases.
4. Keeping **AVPlayer in front** preserves PiP/AirPlay/background quality of life and shrinks “always-on FFmpeg” cost for the many streams that *are* clean HLS.
5. Path B is rational if speed-to-store > dependency independence — many IPTV apps on KSPlayer’s own list validate that commercial path.

### Fallback engine

| Role | Engine |
|------|--------|
| System / clean HLS / PiP-first | **AVPlayer** |
| Hard / TS / recovery | **VLCKit** (Path A) or **KSPlayer LGPL FFmpeg** (Path B) |
| Do not use as prod fallback | IJKPlayer, unmaintained mpv demos, GPL KSPlayer without license |

### Migration effort

| Move | Effort | Notes |
|------|--------|--------|
| Stay on public GPL KSPlayer hybrid (status quo) | **S** (already done) | **Not App Store safe** long-term |
| Buy KSPlayer LGPL, keep code | **S** | Swap package source to private LGPL repos; legal/process work dominates |
| Introduce `StreamPlaying` + AVPlayer-native path without KSPlayer wrapper | **S–M** | Good cleanup even if hard engine stays |
| Replace FFmpeg hard path with VLCKit (Path A) | **M** | New representable player, options mapping (UA/headers), error bridge, tvOS pod, drop KSPlayer import surface |
| Full custom FFmpeg render stack | **L–XL** | Avoid |

### Drop FFmpegKit now or keep hybrid?

| Phase | Action |
|-------|--------|
| **Now (dev / internal / TestFlight only)** | **Keep hybrid** if it unblocks dogfooding. Upstream explicitly allows GPL during TestFlight. Do **not** treat this as store-ready. |
| **Before App Store submission** | **Drop public GPL KSPlayer/FFmpegKit** unless Path B (paid LGPL) is signed. |
| **Production Path A** | **Remove** KSPlayer + kingslay FFmpegKit entirely; hybrid becomes **AVPlayer + VLCKit**. |
| **Production Path B** | **Keep** FFmpeg hybrid under **LGPL-licensed** KSPlayer packages; still prefer AVPlayer-first Auto to reduce CPU/size pain where possible. |

**Explicit:** Do not “drop FFmpeg tomorrow” if you have no hard engine replacement ready — playback quality will regress on TS. Drop it as part of a **planned cutover** to VLCKit or paid KSPlayer LGPL.

### Should we switch to VLC?

**Yes — as the production hard-stream engine (Path A), not as the only player.**

| Question | Answer |
|----------|--------|
| Switch to VLC as **sole** engine for all streams? | **No.** Keep AVPlayer for clean HLS + system features. |
| Switch to VLC as **replacement for KSPlayer/FFmpeg** hard path? | **Yes**, if you will not purchase KSPlayer LGPL. |
| Switch immediately this week with no protocol layer? | **No.** Spike VLCKit on 10–20 real Xtream/TS URLs (iOS + tvOS), then migrate behind `StreamPlaying`. |
| Is VLC legally “free of homework”? | **No.** LGPL dynamic-link + attribution + offer source for VLC bits — still far better than GPL app infection. |

---

## 8. Suggested decision & next steps (planning only)

**Decision to ratify:**

1. **Production architecture:** multi-engine Auto (AVPlayer ↔ hard).
2. **Hard engine:** **VLCKit 3.7** (Path A), unless leadership prefers **KSPlayer LGPL** for schedule (Path B).
3. **Public GPL KSPlayer:** allowed only for pre-store builds; **block** App Store submit on GPL linkage.
4. **Do not** invest in IJKPlayer / GStreamer / commercial OTT for current IPTV scope.
5. Optional spike (time-box 1–2 days): MPVKit LGPL **only** if VLCKit fails a must-play stream class — not the main line.

**Acceptance criteria for a future implementation (when approved):**

- [ ] Same SwiftUI chrome works on iOS + tvOS with engine swap invisible to UI except debug chip.
- [ ] Auto: clean HLS plays on AVPlayer; forced TS / known-bad HLS plays on hard engine.
- [ ] Manual engine picker retained.
- [ ] License artifact: NOTICE + settings attribution + (LGPL) framework linkage documented.
- [ ] App size delta measured (thinned IPA/IPA tvOS).
- [ ] PiP + background audio verified on iOS AV path; documented limitations on VLC path.
- [ ] CI builds without FFmpegKit prohibited-flag failures on Xcode 16+.
- [ ] Legal checklist signed off before App Store.

**Spike checklist (Path A):**

1. Integrate `MobileVLCKit` (iOS) + `TVVLCKit` (tvOS) via CocoaPods or official binary (document XcodeGen coexistence).
2. Play: clean HLS, broken HLS, HTTP TS, Xtream live with custom UA/headers.
3. Measure: start latency, stall recovery, thermal, binary size vs current KSPlayer build.
4. Prototype `UIViewRepresentable` drawable + pause/seek/live edge.
5. Go/no-go vs Path B cost.

---

## 9. Facts vs recommendations

### Facts

- SportsDash currently links SPM KSPlayer (GPL public) with FFmpeg + AVPlayer fallback.
- KSPlayer upstream is actively maintained in 2026 and lists multiple shipping IPTV apps; LGPL is paid.
- VLCKit is LGPLv2.1, actively releasing 3.7.x in 2026, with separate tvOS pod.
- AVPlayer is best system citizen but weak on many IPTV TS/non-spec streams.
- arthenica FFmpegKit classic is retired; SportsDash’s path is via **kingslay/FFmpegKit** through KSPlayer (not a reason alone to panic, but SPM/binary friction is real).
- MPVKit exists as LGPL SPM binaries but self-describes as lightly maintained.

### Recommendations

- Do **not** ship App Store build on **public GPL KSPlayer**.
- Prefer **AVPlayer + VLCKit** hybrid for production independence and license clarity.
- Prefer **KSPlayer LGPL** only if schedule/quality retention outweighs royalty and single-vendor lock.
- Keep hybrid Auto forever; never AV-only; never VLC-only if you care about PiP/AirPlay polish.
- Formalize `StreamPlaying` before adding a third backend.

---

## 10. One-page executive answer

| Item | Answer |
|------|--------|
| **Primary production pick** | Hybrid **AVPlayer + VLCKit 3.7** (Auto router) |
| **Alt production pick** | Hybrid **KSPlayer LGPL + AVPlayer** (if paying) |
| **Fallback engine** | AVPlayer ↔ hard engine (mutual), user override |
| **Migration effort** | Path A **M** / Path B **S** |
| **Drop FFmpegKit now?** | Not cold-turkey; drop at cutover to VLC **or** replace with paid KSPlayer LGPL before store |
| **Switch to VLC?** | **Yes as hard engine**; **No as sole engine** |

---

*Prepared for SportsDash Apple engineering. Not legal advice — confirm LGPL packaging and any KSPlayer commercial terms with counsel before App Store submission.*
