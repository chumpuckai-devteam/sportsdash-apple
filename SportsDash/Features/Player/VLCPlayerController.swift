import AVFoundation
import Combine
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
import MobileVLCKit
#elseif os(tvOS)
import TVVLCKit
#endif

/// Hard IPTV engine — libVLC via MobileVLCKit / TVVLCKit (LGPL).
@MainActor
final class VLCPlayerController: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isPlaying = false
    @Published private(set) var hasRenderedFrame = false
    @Published var error: String?

    #if canImport(UIKit)
    /// Drawable host for VLC (UIView).
    let drawableView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        return v
    }()
    #endif

    #if os(iOS) || os(tvOS)
    private var player: VLCMediaPlayer?
    private var media: VLCMedia?
    #endif
    private var loadGeneration = 0
    private var userAgent = "VLC/3.0.21 LibVLC/3.0.21"
    private var hardwareDecode = true
    private var bufferMs: Int = 3000

    func configure(userAgent: String, bufferSeconds: Double, hardwareDecode: Bool) {
        let ua = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userAgent = ua.isEmpty ? "VLC/3.0.21 LibVLC/3.0.21" : ua
        self.hardwareDecode = hardwareDecode
        self.bufferMs = PlayerPrefs.vlcCachingMs(bufferSeconds)
    }

    func start(url: String) {
        #if os(iOS) || os(tvOS)
        error = nil
        isLoading = true
        isBuffering = true
        isPlaying = false
        hasRenderedFrame = false
        loadGeneration += 1
        let gen = loadGeneration

        stopPlayerOnly()

        guard let mediaURL = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") else {
            error = "Invalid stream URL"
            isLoading = false
            isBuffering = false
            return
        }

        let p = VLCMediaPlayer()
        p.delegate = self
        #if canImport(UIKit)
        p.drawable = drawableView
        #endif

        let m = VLCMedia(url: mediaURL)
        // Network / IPTV-friendly options -- functional via pure PlayerPrefs.vlcCachingMs (P0)
        let cache = bufferMs
        m.addOption(":network-caching=\(cache)")
        m.addOption(":live-caching=\(cache)")
        m.addOption(":sout-mux-caching=\(cache)")
        m.addOption(":http-user-agent=\(userAgent)")
        m.addOption(":http-reconnect=true")
        if hardwareDecode {
            m.addOption(":avcodec-hw=any")
        } else {
            m.addOption(":avcodec-hw=none")
        }
        // Prefer low delay for live
        m.addOption(":clock-jitter=0")
        m.addOption(":clock-synchro=0")

        media = m
        player = p
        p.media = m
        p.play()
        // Initial gain; re-applied when .playing fires
        p.audio?.volume = 140

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard gen == self.loadGeneration, self.isLoading, !self.isPlaying else { return }
            self.error = "Stream timed out while loading (VLC)"
            self.isLoading = false
            self.isBuffering = false
        }
        #else
        error = "VLC not available on this platform"
        isLoading = false
        #endif
    }

    func stop() {
        loadGeneration += 1
        stopPlayerOnly()
        isLoading = false
        isBuffering = false
        isPlaying = false
        hasRenderedFrame = false
    }

    private func stopPlayerOnly() {
        #if os(iOS) || os(tvOS)
        player?.stop()
        player?.delegate = nil
        player?.media = nil
        player = nil
        media = nil
        #endif
    }

    func play() {
        #if os(iOS) || os(tvOS)
        player?.play()
        isPlaying = true
        // hasRenderedFrame set ONLY in mediaPlayerTimeChanged on time progress (B3)
        #endif
    }

    func pause() {
        #if os(iOS) || os(tvOS)
        player?.pause()
        isPlaying = false
        #endif
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func jumpToLive() {
        #if os(iOS) || os(tvOS)
        // Live: stop/start is more reliable than seek on infinite TS.
        if let url = media?.url?.absoluteString {
            start(url: url)
        } else {
            player?.play()
        }
        #endif
    }

    func setMuted(_ muted: Bool) {
        #if os(iOS) || os(tvOS)
        player?.audio?.isMuted = muted
        if !muted {
            applyPreferredVolume()
        }
        #endif
    }

    /// Soft boost for quiet IPTV (Android libVLC 140/200 parity ~ VLCKit 0…200 scale).
    func applyPreferredVolume() {
        #if os(iOS) || os(tvOS)
        // VLCKit: 0–200, 100 = unity
        player?.audio?.volume = Int32(140)
        #endif
    }
}

#if os(iOS) || os(tvOS)
extension VLCPlayerController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let p = self.player else { return }
            switch p.state {
            case .buffering:
                self.isBuffering = true
                if !self.isPlaying && !self.hasRenderedFrame {
                    self.isLoading = true
                }
            case .playing:
                self.isLoading = false
                self.isBuffering = false
                self.isPlaying = true
                // DO NOT set hasRenderedFrame here (B3) — only on time advance in mediaPlayerTimeChanged
                self.error = nil
                self.applyPreferredVolume()
            case .paused:
                self.isPlaying = false
                self.isLoading = false
                self.isBuffering = false
            case .error:
                self.isLoading = false
                self.isBuffering = false
                self.isPlaying = false
                self.error = "Playback failed (VLC)"
            case .stopped, .ended:
                self.isPlaying = false
            case .opening:
                self.isLoading = true
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let p = self.player else { return }
            let currentTime = p.time?.intValue ?? 0
            let hasVideoOut = p.hasVideoOut
            if currentTime > 0 || hasVideoOut == true {
                if !self.hasRenderedFrame {
                    self.hasRenderedFrame = true
                }
                if !self.isPlaying {
                    self.isLoading = false
                    self.isBuffering = false
                    self.isPlaying = true
                    self.error = nil
                }
            }
        }
    }
}
#endif

#if canImport(UIKit)
struct VLCPlayerSurface: UIViewRepresentable {
    @ObservedObject var engine: VLCPlayerController

    func makeUIView(context: Context) -> UIView {
        engine.drawableView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.backgroundColor = .black
    }
}
#endif
