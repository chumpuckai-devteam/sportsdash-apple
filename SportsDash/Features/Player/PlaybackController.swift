import AVFoundation
import Combine
import Foundation

/// AVPlayer tuned for live IPTV (HLS / progressive).
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published var error: String?
    @Published var banner: String?

    private var statusObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var keepUpObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var triedAlternate = false
    private var currentURL: String?
    private var loadGeneration = 0

    func start(url: String) {
        stopPlayerOnly()
        currentURL = url
        loadGeneration += 1
        let gen = loadGeneration
        isLoading = true
        isBuffering = true
        error = nil
        triedAlternate = false

        Task { @MainActor in
            await configureAudioSession()
            guard gen == self.loadGeneration else { return }
            self.open(url: url, generation: gen)
        }
    }

    func stop() {
        loadGeneration += 1
        stopPlayerOnly()
        currentURL = nil
        error = nil
        banner = nil
        isLoading = false
        isBuffering = false
    }

    func jumpToLive() {
        guard let player, let item = player.currentItem else {
            if let url = currentURL { start(url: url) }
            return
        }
        let duration = item.duration
        if duration.isNumeric, duration.seconds.isFinite, duration.seconds > 2 {
            let edge = CMTime(
                seconds: max(0, duration.seconds - 0.35),
                preferredTimescale: 600
            )
            player.seek(to: edge, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            banner = "Jumped to live"
        } else if let url = currentURL {
            start(url: url)
            banner = "Rejoined live stream"
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if banner != nil { banner = nil }
        }
    }

    // MARK: - Private

    private func stopPlayerOnly() {
        statusObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        keepUpObservation?.invalidate()
        timeControlObservation?.invalidate()
        statusObservation = nil
        bufferEmptyObservation = nil
        keepUpObservation = nil
        timeControlObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func configureAudioSession() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            // Non-fatal — video can still play
        }
    }

    private func open(url: String, generation: Int) {
        guard let u = URL(string: url) else {
            error = "Invalid stream URL"
            isLoading = false
            isBuffering = false
            return
        }

        // Headers many IPTV panels expect
        let headers: [String: String] = [
            "User-Agent": "SportsDash/1.0 (iOS; AVPlayer)",
            "Accept": "*/*",
            "Connection": "keep-alive",
        ]
        let asset = AVURLAsset(
            url: u,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers,
                // Prefer network for live; don't over-cache incomplete segments
                AVURLAssetAllowsCellularAccessKey: true,
            ]
        )

        let item = AVPlayerItem(asset: asset)
        // Live-friendly buffering
        item.preferredForwardBufferDuration = 4
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        if #available(iOS 15.0, tvOS 15.0, *) {
            item.preferredPeakBitRate = 0 // let ABR choose
        }

        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        // Slightly more aggressive for live feel once playing
        if #available(iOS 15.0, *) {
            p.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        player = p

        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.isBuffering = false
                    self.player?.play()
                case .failed:
                    self.handleFail(
                        item.error?.localizedDescription ?? "Playback failed",
                        generation: generation
                    )
                default:
                    break
                }
            }
        }

        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                if item.isPlaybackBufferEmpty { self.isBuffering = true }
            }
        }
        keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                if item.isPlaybackLikelyToKeepUp {
                    self.isBuffering = false
                    self.isLoading = false
                }
            }
        }
        timeControlObservation = p.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }

        // Fail open if stuck too long
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            guard generation == self.loadGeneration, self.isLoading else { return }
            self.handleFail("Stream timed out while loading", generation: generation)
        }
    }

    private func handleFail(_ message: String, generation: Int) {
        guard generation == loadGeneration else { return }
        if !triedAlternate, let url = currentURL,
           let alt = IptvService.alternateXtreamContainer(url) {
            triedAlternate = true
            banner = "Trying alternate stream format…"
            open(url: alt, generation: generation)
            currentURL = alt
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.banner?.contains("alternate") == true { self.banner = nil }
            }
            return
        }
        isLoading = false
        isBuffering = false
        error = friendlyError(message)
    }

    private func friendlyError(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("not connected") || s.contains("network") {
            return "Network error. Check Wi‑Fi or try again."
        }
        if s.contains("404") || s.contains("-1102") || s.contains("not found") {
            return "Stream not found (expired or wrong URL). Try another channel."
        }
        if s.contains("401") || s.contains("403") || s.contains("auth") {
            return "Access denied. Re-save IPTV credentials in Settings."
        }
        if s.contains("format") || s.contains("-11828") || s.contains("-11800") {
            return "Format not supported by AVPlayer. Try another stream or container."
        }
        return raw
    }
}
