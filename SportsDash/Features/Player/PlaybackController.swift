import AVFoundation
import Combine
import Foundation

/// AVPlayer tuned for live IPTV (HLS / progressive) with multi-URL fallback.
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
    private var errorObservation: NSKeyValueObservation?
    private var currentURL: String?
    private var candidateURLs: [String] = []
    private var candidateIndex = 0
    private var loadGeneration = 0

    func start(url: String) {
        stopPlayerOnly()
        currentURL = url
        candidateURLs = IptvService.playbackURLCandidates(from: url)
        candidateIndex = 0
        loadGeneration += 1
        let gen = loadGeneration
        isLoading = true
        isBuffering = true
        error = nil

        Task { @MainActor in
            await configureAudioSession()
            guard gen == self.loadGeneration else { return }
            self.open(url: self.candidateURLs[0], generation: gen)
        }
    }

    func stop() {
        loadGeneration += 1
        stopPlayerOnly()
        currentURL = nil
        candidateURLs = []
        candidateIndex = 0
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
        errorObservation?.invalidate()
        statusObservation = nil
        bufferEmptyObservation = nil
        keepUpObservation = nil
        timeControlObservation = nil
        errorObservation = nil
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
            // Non-fatal
        }
    }

    private func open(url: String, generation: Int) {
        // URL(string:) fails if string has unencoded spaces; use URLComponents if needed
        guard let u = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? url) else {
            error = "Invalid stream URL"
            isLoading = false
            isBuffering = false
            return
        }

        currentURL = url

        let headers: [String: String] = [
            "User-Agent":
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            "Accept": "*/*",
            "Connection": "keep-alive",
        ]
        let asset = AVURLAsset(
            url: u,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers,
                AVURLAssetAllowsCellularAccessKey: true,
            ]
        )

        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
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
                    let msg = item.error?.localizedDescription
                        ?? (item.error as NSError?)?.localizedFailureReason
                        ?? "Playback failed"
                    self.handleFail(msg, generation: generation)
                default:
                    break
                }
            }
        }

        errorObservation = item.observe(\.error, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration, let err = item.error else { return }
                self.handleFail(err.localizedDescription, generation: generation)
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

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000_000)
            guard generation == self.loadGeneration, self.isLoading else { return }
            self.handleFail("Stream timed out while loading", generation: generation)
        }
    }

    private func handleFail(_ message: String, generation: Int) {
        guard generation == loadGeneration else { return }

        // Auto-advance through m3u8 → ts → bare candidates
        let next = candidateIndex + 1
        if next < candidateURLs.count {
            candidateIndex = next
            let nextURL = candidateURLs[next]
            banner = "Trying alternate format…"
            stopPlayerOnly()
            isLoading = true
            isBuffering = true
            error = nil
            open(url: nextURL, generation: generation)
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
        if s.contains("resource unavailable") || s.contains("-1008") || s.contains("not available") {
            return "Stream unavailable (panel offline, expired link, or blocked). Try another stream."
        }
        if s.contains("not connected") || s.contains("network") || s.contains("-1009") {
            return "Network error. Check Wi‑Fi or try again."
        }
        if s.contains("404") || s.contains("-1102") || s.contains("not found") {
            return "Stream not found. Try another channel."
        }
        if s.contains("401") || s.contains("403") || s.contains("auth") {
            return "Access denied. Re-save IPTV credentials in Settings."
        }
        if s.contains("format") || s.contains("-11828") || s.contains("-11800") || s.contains("-11850") {
            return "Format not supported by iOS AVPlayer. Try another stream."
        }
        return raw
    }
}
