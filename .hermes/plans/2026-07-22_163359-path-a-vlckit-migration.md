# SportsDash Path A — VLCKit migration plan

> **Approved:** Samir chose Path A (2026-07-22)

**Goal:** Replace GPL KSPlayer/FFmpegKit hard engine with **VLCKit 3.7** while keeping **AVPlayer** for clean HLS + system features (PiP/AirPlay path).

**Architecture:**
```
PlaybackController (ObservableObject)
├── Auto: .m3u8 → AV first; .ts / failure → VLC
├── VLC (MobileVLCKit / TVVLCKit) — hard IPTV
└── AVKit — native AVPlayerLayer
PlayerSurface switches drawable by activeEngine
```

**Integration:** CocoaPods (official VLC binaries) + XcodeGen project. Open `SportsDash.xcworkspace` after `pod install`.

**Out of scope:** Multiview, paid KSPlayer LGPL, Android.

## Tasks
1. Podfile + CI workspace build
2. Rewrite PlaybackController (VLC + AV)
3. PlayerSurface UIViewRepresentables
4. Prefs: Auto / VLC / AVKit (migrate ksPlayer → vlc)
5. Settings + README + LGPL notice
6. Remove KSPlayer SPM dependency

## Verify (on device)
- Clean HLS on AV
- TS / Xtream live on VLC
- Auto fallback when primary fails
- Engine chip in player chrome
- No FFmpegKit package warning
