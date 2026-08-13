import AVFoundation
import AVKit
import Combine
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Soft path — Apple AVPlayer for clean HLS (.m3u8).
@MainActor
final class AVPlayerEngine: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isPlaying = false
    @Published private(set) var hasRenderedFrame = false
    @Published private(set) var hasAdvancedPlayback = false
    @Published private(set) var hasOutputProgress = false
    @Published var error: String?

    @Published private(set) var isSystemPiPActive = false

    let player = AVPlayer()
    private var itemObservers: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var loadGeneration = 0
    private var userAgent = "VLC/3.0.21 LibVLC/3.0.21"
    private var lastObservedSeconds: Double?

    func configure(userAgent: String) {
        let ua = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userAgent = ua.isEmpty ? "VLC/3.0.21 LibVLC/3.0.21" : ua
    }

    func start(url: String) {
        error = nil
        isLoading = true
        isBuffering = true
        isPlaying = false
        hasRenderedFrame = false
        hasAdvancedPlayback = false
        hasOutputProgress = false
        lastObservedSeconds = nil
        loadGeneration += 1
        let gen = loadGeneration

        clearItem()

        guard let u = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") else {
            error = "Invalid stream URL"
            isLoading = false
            isBuffering = false
            return
        }

        let headers = [
            "User-Agent": userAgent,
            "Accept": "*/*",
        ]
        let asset = AVURLAsset(url: u, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        observe(item: item, generation: gen)
        player.replaceCurrentItem(with: item)
        player.play()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard gen == self.loadGeneration, self.isLoading, !self.isPlaying else { return }
            self.error = "Stream timed out while loading (AVPlayer)"
            self.isLoading = false
            self.isBuffering = false
        }
    }

    func stop() {
        loadGeneration += 1
        #if os(iOS)
        stopSystemPiP()
        #endif
        clearItem()
        isLoading = false
        isBuffering = false
        isPlaying = false
        hasRenderedFrame = false
        hasAdvancedPlayback = false
        hasOutputProgress = false
        lastObservedSeconds = nil
        #if os(iOS)
        isSystemPiPActive = false
        #endif
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func jumpToLive() {
        guard let item = player.currentItem else { return }
        let duration = item.duration
        if duration.isNumeric, duration.seconds.isFinite {
            let t = CMTime(seconds: max(0, duration.seconds - 1), preferredTimescale: 600)
            player.seek(to: t)
            player.play()
            isPlaying = true
        } else {
            player.play()
        }
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    // MARK: - System Picture-in-Picture (iOS only)
    // Simplified coherent path (ship-safe):
    // - REMOVE separate AVPictureInPictureController with unattached AVPlayerLayer (competing owner for the player).
    // - Primary activation is AUTOMATIC via AVPlayerViewController flags set in AVPlayerSurface.
    // - startSystemPiPIfPossible(): no-op or best-effort only (if we later hold ref to AVPlayerViewController).
    // - supportsSystemPiP = AVPictureInPictureController.isPictureInPictureSupported()
    // - stopSystemPiP: safe no-op.
    // - Removed unused: pipStateObserver / dead notif observers / setup func / AVPictureInPictureControllerDelegate.
    // - State sync via AVPlayerViewControllerDelegate (Coordinator below).
    #if os(iOS)
    var supportsSystemPiP: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func startSystemPiPIfPossible() {
        // No-op: rely on automatic PiP from AVPlayerViewController when allowsPictureInPicturePlayback
        // and canStartPictureInPictureAutomaticallyFromInline are true (set on the surface).
        // Programmatic trigger here is not needed for the background-to-PiP flow.
        guard supportsSystemPiP else { return }
    }

    func stopSystemPiP() {
        // Safe no-op. System / AVPlayerViewController manages the PiP window lifetime.
    }

    func setSystemPiPActive(_ value: Bool) {
        isSystemPiPActive = value
    }
    #endif

    private func clearItem() {
        itemObservers.forEach { $0.invalidate() }
        itemObservers.removeAll()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        hasRenderedFrame = false
        hasAdvancedPlayback = false
        hasOutputProgress = false
        lastObservedSeconds = nil
    }

    private func observe(item: AVPlayerItem, generation: Int) {
        itemObservers.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                switch item.status {
                case .readyToPlay:
                    self.markReady()
                case .failed:
                    self.isLoading = false
                    self.isBuffering = false
                    self.isPlaying = false
                    self.error = item.error?.localizedDescription ?? "Playback failed (AVPlayer)"
                default:
                    break
                }
            }
        })
        itemObservers.append(item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                if item.isPlaybackBufferEmpty {
                    self.isBuffering = true
                }
            }
        })
        itemObservers.append(item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                if item.isPlaybackLikelyToKeepUp {
                    self.markReady()
                }
            }
        })
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                self.error = err ?? "Playback failed"
                self.isPlaying = false
                self.isLoading = false
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                let secs = time.seconds
                let tc = self.player.timeControlStatus
                let rate = self.player.rate
                if tc == .playing {
                    if let last = self.lastObservedSeconds {
                        if (secs - last) > 0.2 || (rate > 0 && secs != last) {
                            self.hasRenderedFrame = true
                            self.hasAdvancedPlayback = true
                            self.hasOutputProgress = true
                        }
                    } else {
                        // First sample only stores baseline, does not approve.
                    }
                    self.lastObservedSeconds = secs
                    self.isPlaying = true
                    self.isLoading = false
                    self.isBuffering = false
                    self.error = nil
                } else if tc == .waitingToPlayAtSpecifiedRate {
                    self.isBuffering = true
                }
            }
        }
    }

    private func markReady() {
        isLoading = false
        isBuffering = false
        isPlaying = true
        error = nil
        // NOTE: hasRenderedFrame / hasAdvancedPlayback set ONLY from time progress in periodic observer
        // (readyToPlay / likelyToKeepUp can report true before actual frames advance)
    }
}

// No more AVPictureInPictureControllerDelegate on engine (removed competing controller path).

#if canImport(UIKit)
struct AVPlayerSurface: UIViewControllerRepresentable {
    @ObservedObject var engine: AVPlayerEngine

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = engine.player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        #if os(iOS)
        vc.allowsPictureInPicturePlayback = true
        if #available(iOS 14.2, *) {
            vc.canStartPictureInPictureAutomaticallyFromInline = true
        }
        vc.delegate = context.coordinator
        #endif
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== engine.player {
            vc.player = engine.player
        }
    }

    #if os(iOS)
    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let engine: AVPlayerEngine

        init(engine: AVPlayerEngine) {
            self.engine = engine
        }

        // Primary delegate for system PiP state from AVPlayerViewController's built-in PiP.
        // Do NOT create a second PiP controller.
        func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            MainActor.assumeIsolated {
                engine.setSystemPiPActive(true)
            }
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            MainActor.assumeIsolated {
                engine.setSystemPiPActive(false)
            }
        }

        func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void) {
            MainActor.assumeIsolated {
                engine.setSystemPiPActive(false)
            }
            completionHandler(true)
        }
    }
    #endif
}
#endif
