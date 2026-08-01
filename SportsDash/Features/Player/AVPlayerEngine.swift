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
    @Published var error: String?

    let player = AVPlayer()
    private var itemObservers: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var loadGeneration = 0
    private var userAgent = "VLC/3.0.21 LibVLC/3.0.21"

    func configure(userAgent: String) {
        let ua = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userAgent = ua.isEmpty ? "VLC/3.0.21 LibVLC/3.0.21" : ua
    }

    func start(url: String) {
        error = nil
        isLoading = true
        isBuffering = true
        isPlaying = false
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
        clearItem()
        isLoading = false
        isBuffering = false
        isPlaying = false
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
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                if self.player.timeControlStatus == .playing {
                    self.markReady()
                } else if self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
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
    }
}

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
        #endif
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== engine.player {
            vc.player = engine.player
        }
    }
}
#endif
