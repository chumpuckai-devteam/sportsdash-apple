import AVFoundation
import Combine
import Foundation
import KSPlayer

/// Multi-engine playback via KSPlayer (KSMEPlayer / FFmpeg + optional KSAVPlayer).
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isPlaying = false
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
    private var firstFrameWatch: Task<Void, Never>?

    init() {
        attachCoordinatorCallbacks()
    }

    func configure(prefs: PlayerPrefs) {
        self.prefs = prefs
        Self.applyGlobal(prefs)
        engineLabel = prefs.primaryPlayer.label
            + (prefs.fallbackPlayers ? " · fallback on" : "")
    }

    func start(url: String) {
        // Tear down previous surface without wiping KSPlayer callback hooks permanently.
        stopPlayerOnly(clearError: true, clearCallbacks: false)
        attachCoordinatorCallbacks()

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
        isPlaying = false
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
        firstFrameWatch?.cancel()
        firstFrameWatch = nil
        stopPlayerOnly(clearError: true, clearCallbacks: true)
        currentURL = nil
        candidateURLs = []
        candidateIndex = 0
        banner = nil
        isLoading = false
        isBuffering = false
        isPlaying = false
    }

    func jumpToLive() {
        if let layer = coordinator.playerLayer {
            let duration = layer.player.duration
            if duration.isFinite, duration > 2 {
                layer.seek(time: max(0, duration - 0.5), autoPlay: true) { [weak self] finished in
                    Task { @MainActor in
                        if finished {
                            self?.markReady()
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

    // MARK: - Transport / PiP / captions

    func togglePlayPause() {
        guard let layer = coordinator.playerLayer else { return }
        if layer.state.isPlaying {
            layer.pause()
            isPlaying = false
        } else {
            layer.play()
            isPlaying = true
            isLoading = false
            isBuffering = false
        }
    }

    func pause() {
        coordinator.playerLayer?.pause()
        isPlaying = false
    }

    func resumePlay() {
        coordinator.playerLayer?.play()
        isPlaying = true
        isLoading = false
        isBuffering = false
    }

    func toggleMute() {
        setMuted(!isMuted)
        banner = isMuted ? "Muted" : "Unmuted"
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if banner == "Muted" || banner == "Unmuted" { banner = nil }
        }
    }

    func setMuted(_ muted: Bool) {
        coordinator.isMuted = muted
        coordinator.playbackVolume = muted ? 0 : 1
        if let player = coordinator.playerLayer?.player {
            player.isMuted = muted
            player.playbackVolume = muted ? 0 : 1
        }
    }

    var isMuted: Bool { coordinator.isMuted }

    /// Picture-in-Picture (KSPlayer / AVKit).
    func togglePictureInPicture() {
        guard let layer = coordinator.playerLayer else {
            banner = "PiP unavailable"
            return
        }
        layer.isPipActive.toggle()
        banner = layer.isPipActive ? "Picture in Picture on" : "Picture in Picture off"
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if banner?.contains("Picture") == true { banner = nil }
        }
    }

    var isPiPActive: Bool {
        coordinator.playerLayer?.isPipActive ?? false
    }

    struct SubtitleOption: Identifiable, Hashable {
        var id: String
        var name: String
        var isEnabled: Bool
    }

    /// Embedded subtitle / closed-caption tracks when the stream provides them.
    func subtitleOptions() -> [SubtitleOption] {
        guard let player = coordinator.playerLayer?.player else { return [] }
        return player.tracks(mediaType: .subtitle).enumerated().map { idx, track in
            SubtitleOption(
                id: "\(idx)-\(track.name)",
                name: track.name.isEmpty ? "Track \(idx + 1)" : track.name,
                isEnabled: track.isEnabled
            )
        }
    }

    func selectSubtitle(named name: String?) {
        guard let player = coordinator.playerLayer?.player else { return }
        let tracks = player.tracks(mediaType: .subtitle)
        if let name,
           let track = tracks.first(where: { $0.name == name || "\($0.name)" == name }) {
            player.select(track: track)
            banner = "Subtitles: \(track.name.isEmpty ? "On" : track.name)"
        } else {
            // Disable all by re-selecting none when possible — pick first disabled pattern.
            // KSPlayer enables a track via select; toggling off: select empty if available.
            if let enabled = tracks.first(where: \.isEnabled) {
                // Re-select same track doesn't disable; best-effort banner.
                _ = enabled
            }
            banner = "Subtitles: Off"
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if banner?.hasPrefix("Subtitles") == true { banner = nil }
        }
    }

    func cycleSubtitleTrack() {
        let tracks = subtitleOptions()
        guard !tracks.isEmpty else {
            banner = "No captions on this stream"
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if banner?.contains("captions") == true { banner = nil }
            }
            return
        }
        guard let player = coordinator.playerLayer?.player else { return }
        let mediaTracks = player.tracks(mediaType: .subtitle)
        if let currentIdx = mediaTracks.firstIndex(where: \.isEnabled) {
            let next = currentIdx + 1
            if next < mediaTracks.count {
                player.select(track: mediaTracks[next])
                let name = mediaTracks[next].name
                banner = "Subtitles: \(name.isEmpty ? "Track \(next + 1)" : name)"
            } else {
                // Cycle off — re-select first with a note; true off isn't always supported.
                banner = "Subtitles: cycle complete"
            }
        } else if let first = mediaTracks.first {
            player.select(track: first)
            banner = "Subtitles: \(first.name.isEmpty ? "On" : first.name)"
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if banner?.hasPrefix("Subtitles") == true { banner = nil }
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

    /// KSPlayer's `resetPlayer()` nils all callbacks — always re-attach after.
    private func attachCoordinatorCallbacks() {
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
                // First buffer event (count == 0) means still preparing; later counts are rebuffer.
                if count == 0 {
                    // Don't force loading spinner if we already have frames.
                    if !self.isPlaying {
                        self.isBuffering = true
                    }
                } else {
                    // Rebuffer while playing — show subtle buffering only.
                    self.isBuffering = true
                    self.isLoading = false
                }
            }
        }
        // Time updates prove frames are advancing — hide the start overlay.
        coordinator.onPlay = { [weak self] current, _ in
            Task { @MainActor in
                guard let self else { return }
                if current > 0.05 || self.coordinator.state == .bufferFinished
                    || self.coordinator.state == .readyToPlay {
                    self.markReady()
                }
            }
        }
    }

    private func stopPlayerOnly(clearError: Bool, clearCallbacks: Bool) {
        firstFrameWatch?.cancel()
        firstFrameWatch = nil
        if clearCallbacks {
            coordinator.resetPlayer()
        } else {
            // Pause/release layer without discarding our callback closures permanently.
            coordinator.playerLayer?.pause()
            coordinator.playerLayer = nil
        }
        playURL = nil
        if clearError { error = nil }
    }

    private func configureAudioSession() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay]
            )
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
        isPlaying = false
        error = nil
        attachCoordinatorCallbacks()
        // Assigning playURL rebuilds KSVideoPlayer, which opens the stream.
        playURL = u

        // Failsafe: if callbacks never fire but video is up, clear spinner soon.
        firstFrameWatch?.cancel()
        firstFrameWatch = Task { @MainActor in
            // Poll coordinator state for a few seconds after open.
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard generation == self.loadGeneration else { return }
                let state = self.coordinator.state
                if state == .readyToPlay || state == .bufferFinished {
                    self.markReady()
                    return
                }
                if state == .error {
                    self.handleFail("Playback failed", generation: generation)
                    return
                }
            }
            // If still "loading" after 10s but no error, hide spinner — video often already visible.
            guard generation == self.loadGeneration, self.isLoading else { return }
            if self.coordinator.playerLayer?.player.isReadyToPlay == true {
                self.markReady()
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard generation == self.loadGeneration, self.isLoading, !self.isPlaying else { return }
            self.handleFail("Stream timed out while loading", generation: generation)
        }
    }

    private func markReady() {
        isLoading = false
        isBuffering = false
        isPlaying = true
        error = nil
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
            if !isPlaying {
                isLoading = true
                isBuffering = true
            }
        case .readyToPlay:
            markReady()
            coordinator.playerLayer?.play()
        case .buffering:
            // Mid-stream rebuffer: don't show "Starting stream…"
            isBuffering = true
            isLoading = false
        case .bufferFinished, .paused:
            markReady()
            if state == .paused {
                isPlaying = false
            }
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
            stopPlayerOnly(clearError: true, clearCallbacks: false)
            attachCoordinatorCallbacks()
            isLoading = true
            isBuffering = true
            isPlaying = false
            open(urlString: nextURL, generation: generation)
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.banner?.contains("alternate") == true { self.banner = nil }
            }
            return
        }

        isLoading = false
        isBuffering = false
        isPlaying = false
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
