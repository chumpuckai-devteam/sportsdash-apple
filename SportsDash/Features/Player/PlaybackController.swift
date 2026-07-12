import AVFoundation
import Combine
import Foundation
import KSPlayer

/// Multi-engine playback via KSPlayer (KSMEPlayer / FFmpeg + optional KSAVPlayer).
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published var error: String?
    @Published var banner: String?
    @Published private(set) var playURL: URL?
    @Published private(set) var options = KSOptions()
    @Published private(set) var engineLabel: String = ""

    let coordinator = KSVideoPlayer.Coordinator()

    private var currentURL: String?
    private var candidateURLs: [String] = []
    private var candidateIndex = 0
    private var loadGeneration = 0
    private var prefs = PlayerPrefs()
    private var didWireCoordinator = false

    init() {
        wireCoordinator()
    }

    func configure(prefs: PlayerPrefs) {
        self.prefs = prefs
        Self.applyGlobal(prefs)
        engineLabel = prefs.primaryPlayer.label
            + (prefs.fallbackPlayers ? " · fallback on" : "")
    }

    func start(url: String) {
        stopPlayerOnly(clearError: true)
        currentURL = url
        candidateURLs = IptvService.playbackURLCandidates(
            from: url,
            preferredFormat: prefs.preferredLiveFormat
        )
        candidateIndex = 0
        loadGeneration += 1
        let gen = loadGeneration
        isLoading = true
        isBuffering = true
        error = nil

        Task { @MainActor in
            await configureAudioSession()
            guard gen == self.loadGeneration else { return }
            Self.applyGlobal(self.prefs)
            self.open(urlString: self.candidateURLs[0], generation: gen)
        }
    }

    func stop() {
        loadGeneration += 1
        stopPlayerOnly(clearError: true)
        currentURL = nil
        candidateURLs = []
        candidateIndex = 0
        banner = nil
        isLoading = false
        isBuffering = false
    }

    func jumpToLive() {
        if let layer = coordinator.playerLayer {
            let duration = layer.player.duration
            if duration.isFinite, duration > 2 {
                layer.seek(time: max(0, duration - 0.5), autoPlay: true) { [weak self] finished in
                    Task { @MainActor in
                        if finished {
                            self?.banner = "Jumped to live"
                        } else if let url = self?.currentURL {
                            self?.start(url: url)
                            self?.banner = "Rejoined live stream"
                        }
                    }
                }
            } else if let url = currentURL {
                start(url: url)
                banner = "Rejoined live stream"
            }
        } else if let url = currentURL {
            start(url: url)
            banner = "Rejoined live stream"
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if banner != nil { banner = nil }
        }
    }

    func setAspectFill(_ fill: Bool) {
        coordinator.isScaleAspectFill = fill
        if let player = coordinator.playerLayer?.player {
            player.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
        }
    }

    // MARK: - Global KSPlayer config

    static func applyGlobal(_ prefs: PlayerPrefs) {
        KSOptions.isAutoPlay = true
        KSOptions.hardwareDecode = prefs.hardwareDecode
        KSOptions.asynchronousDecompression = prefs.asynchronousDecompression
        KSOptions.preferredFrame = prefs.adaptiveFrameRate
        KSOptions.preferredForwardBufferDuration = prefs.clampedBufferSeconds
        KSOptions.maxBufferDuration = max(15, prefs.clampedBufferSeconds * 5)
        KSOptions.isSecondOpen = true
        KSOptions.logLevel = .warning

        switch prefs.primaryPlayer {
        case .ksPlayer:
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = prefs.fallbackPlayers ? KSAVPlayer.self : nil
        case .avKit:
            KSOptions.firstPlayerType = KSAVPlayer.self
            KSOptions.secondPlayerType = prefs.fallbackPlayers ? KSMEPlayer.self : nil
        }
    }

    // MARK: - Private

    private func wireCoordinator() {
        guard !didWireCoordinator else { return }
        didWireCoordinator = true

        coordinator.onStateChanged = { [weak self] _, state in
            Task { @MainActor in
                self?.handleState(state)
            }
        }
        coordinator.onFinish = { [weak self] _, err in
            Task { @MainActor in
                self?.handleFinish(error: err)
            }
        }
        coordinator.onBufferChanged = { [weak self] count, _ in
            Task { @MainActor in
                guard let self else { return }
                if count == 0 {
                    self.isLoading = true
                    self.isBuffering = true
                }
            }
        }
    }

    private func stopPlayerOnly(clearError: Bool) {
        coordinator.resetPlayer()
        playURL = nil
        if clearError { error = nil }
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

    private func open(urlString: String, generation: Int) {
        guard let u = Self.makeURL(urlString) else {
            error = "Invalid stream URL"
            isLoading = false
            isBuffering = false
            return
        }

        currentURL = urlString
        options = makeOptions()
        isLoading = true
        isBuffering = true
        error = nil
        playURL = u

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard generation == self.loadGeneration, self.isLoading else { return }
            self.handleFail("Stream timed out while loading", generation: generation)
        }
    }

    private func makeOptions() -> KSOptions {
        let o = KSOptions()
        o.hardwareDecode = prefs.hardwareDecode
        o.asynchronousDecompression = prefs.asynchronousDecompression
        o.preferredForwardBufferDuration = prefs.clampedBufferSeconds
        o.maxBufferDuration = max(15, prefs.clampedBufferSeconds * 5)
        o.isSecondOpen = true
        let ua = prefs.userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        o.userAgent = ua.isEmpty
            ? "VLC/3.0.18 LibVLC/3.0.18"
            : ua
        o.appendHeader([
            "Accept": "*/*",
            "Connection": "keep-alive",
        ])
        o.probesize = 500_000
        o.maxAnalyzeDuration = 2_000_000
        o.formatContextOptions["fflags"] = "nobuffer"
        o.formatContextOptions["flags"] = "low_delay"
        o.formatContextOptions["reconnect"] = 1
        o.formatContextOptions["reconnect_streamed"] = 1
        o.formatContextOptions["reconnect_delay_max"] = 5
        return o
    }

    private func handleState(_ state: KSPlayerState) {
        switch state {
        case .preparing, .initialized:
            isLoading = true
            isBuffering = true
        case .readyToPlay:
            isLoading = false
            isBuffering = false
            error = nil
            coordinator.playerLayer?.play()
        case .buffering:
            isBuffering = true
        case .bufferFinished, .paused:
            isLoading = false
            isBuffering = false
        case .error:
            handleFail("Playback failed", generation: loadGeneration)
        case .playedToTheEnd:
            if let url = currentURL {
                banner = "Stream ended — rejoining…"
                start(url: url)
            }
        }
    }

    private func handleFinish(error err: Error?) {
        if let err {
            handleFail(err.localizedDescription, generation: loadGeneration)
        }
    }

    private func handleFail(_ message: String, generation: Int) {
        guard generation == loadGeneration else { return }

        let next = candidateIndex + 1
        if next < candidateURLs.count {
            candidateIndex = next
            let nextURL = candidateURLs[next]
            banner = "Trying alternate format…"
            stopPlayerOnly(clearError: true)
            isLoading = true
            isBuffering = true
            open(urlString: nextURL, generation: generation)
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
            return "Stream unavailable (panel offline, expired link, or blocked). Try another stream or switch player in Settings."
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
            return "Format not supported. Enable fallback players or switch primary engine in Settings → Video player."
        }
        return raw
    }

    private static func makeURL(_ string: String) -> URL? {
        if let u = URL(string: string) { return u }
        if let encoded = string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: encoded)
        }
        return nil
    }
}
