import AVFoundation
import Combine
import Foundation
import KSPlayer

/// Multi-engine playback:
/// - **Auto (default):** HLS → AVPlayer; TS / unknown → KSPlayer FFmpeg (hard)
/// - Explicit KS / AV / MPV (spike) overrides
/// - Fallback tries the other KS backend or format candidates
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
    /// True when chrome should host `MPVPlayerSurface` instead of KS.
    @Published private(set) var usesMPV = false
    @Published private(set) var detectedContainer: StreamContainer = .unknown

    let coordinator = KSVideoPlayer.Coordinator()
    /// Spike engine — created lazily when primary is MPV (or Auto hard-path chooses MPV later).
    private(set) var mpvEngine: MPVPlayerController?

    private var currentURL: String?
    private var candidateURLs: [String] = []
    private var candidateIndex = 0
    private var loadGeneration = 0
    private var prefs = PlayerPrefs()
    private var firstFrameWatch: Task<Void, Never>?
    private var mpvStateWatch: Task<Void, Never>?
    private var mpvBag: Set<AnyCancellable> = []

    init() {
        attachCoordinatorCallbacks()
    }

    func configure(prefs: PlayerPrefs) {
        self.prefs = prefs
        Self.applyGlobal(prefs, forURL: nil)
        engineLabel = prefs.primaryPlayer.label
            + (prefs.fallbackPlayers ? " · fallback on" : "")
    }

    func start(url: String) {
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
            self.open(urlString: self.candidateURLs[0], generation: gen)
        }
    }

    func stop() {
        loadGeneration += 1
        firstFrameWatch?.cancel()
        firstFrameWatch = nil
        mpvStateWatch?.cancel()
        mpvStateWatch = nil
        stopPlayerOnly(clearError: true, clearCallbacks: true)
        currentURL = nil
        candidateURLs = []
        candidateIndex = 0
        banner = nil
        isLoading = false
        isBuffering = false
        isPlaying = false
        usesMPV = false
    }

    func jumpToLive() {
        if usesMPV, let mpv = mpvEngine {
            mpv.jumpToLive()
            banner = "Jumped to live"
            clearBannerSoon()
            return
        }
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
                        self?.clearBannerSoon()
                    }
                }
            } else if let url = currentURL {
                start(url: url)
                banner = "Rejoined live stream"
                clearBannerSoon()
            }
        } else if let url = currentURL {
            start(url: url)
            banner = "Rejoined live stream"
            clearBannerSoon()
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
        if usesMPV, let mpv = mpvEngine {
            mpv.togglePlayPause()
            isPlaying = mpv.isPlaying
            return
        }
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
        if usesMPV {
            mpvEngine?.pause()
            isPlaying = false
            return
        }
        coordinator.playerLayer?.pause()
        isPlaying = false
    }

    func resumePlay() {
        if usesMPV {
            mpvEngine?.play()
            isPlaying = true
            isLoading = false
            isBuffering = false
            return
        }
        coordinator.playerLayer?.play()
        isPlaying = true
        isLoading = false
        isBuffering = false
    }

    func toggleMute() {
        setMuted(!isMuted)
        banner = isMuted ? "Muted" : "Unmuted"
        clearBannerSoon()
    }

    func setMuted(_ muted: Bool) {
        coordinator.isMuted = muted
        coordinator.playbackVolume = muted ? 0 : 1
        if let player = coordinator.playerLayer?.player {
            player.isMuted = muted
            player.playbackVolume = muted ? 0 : 1
        }
        // mpv mute not wired in spike — KS path only
    }

    var isMuted: Bool { coordinator.isMuted }

    func togglePictureInPicture() {
        guard !usesMPV, let layer = coordinator.playerLayer else {
            banner = usesMPV ? "PiP not in MPV spike yet" : "PiP unavailable"
            clearBannerSoon()
            return
        }
        layer.isPipActive.toggle()
        banner = layer.isPipActive ? "Picture in Picture on" : "Picture in Picture off"
        clearBannerSoon()
    }

    var isPiPActive: Bool {
        coordinator.playerLayer?.isPipActive ?? false
    }

    struct SubtitleOption: Identifiable, Hashable {
        var id: String
        var name: String
        var isEnabled: Bool
    }

    func subtitleOptions() -> [SubtitleOption] {
        guard !usesMPV, let player = coordinator.playerLayer?.player else { return [] }
        return player.tracks(mediaType: .subtitle).enumerated().map { idx, track in
            SubtitleOption(
                id: "\(idx)-\(track.name)",
                name: track.name.isEmpty ? "Track \(idx + 1)" : track.name,
                isEnabled: track.isEnabled
            )
        }
    }

    func selectSubtitle(named name: String?) {
        guard !usesMPV, let player = coordinator.playerLayer?.player else { return }
        let tracks = player.tracks(mediaType: .subtitle)
        if let name,
           let track = tracks.first(where: { $0.name == name || "\($0.name)" == name }) {
            selectTrack(player: player, track: track)
            banner = "Subtitles: \(track.name.isEmpty ? "On" : track.name)"
        } else {
            banner = "Subtitles: Off"
        }
        clearBannerSoon()
    }

    func cycleSubtitleTrack() {
        guard !usesMPV, let player = coordinator.playerLayer?.player else {
            banner = "No captions on this stream"
            clearBannerSoon()
            return
        }
        let mediaTracks = player.tracks(mediaType: .subtitle)
        guard !mediaTracks.isEmpty else {
            banner = "No captions on this stream"
            clearBannerSoon()
            return
        }

        if let currentIdx = mediaTracks.firstIndex(where: \.isEnabled) {
            let next = currentIdx + 1
            if next < mediaTracks.count {
                let track = mediaTracks[next]
                selectTrack(player: player, track: track)
                let name = track.name
                banner = "Subtitles: \(name.isEmpty ? "Track \(next + 1)" : name)"
            } else {
                banner = "Subtitles: cycle complete"
            }
        } else if let first = mediaTracks.first {
            selectTrack(player: player, track: first)
            banner = "Subtitles: \(first.name.isEmpty ? "On" : first.name)"
        }
        clearBannerSoon()
    }

    private func selectTrack(player: some MediaPlayerProtocol, track: any MediaPlayerTrack) {
        func open<T: MediaPlayerTrack>(_ t: T) {
            player.select(track: t)
        }
        _openExistential(track, do: open)
    }

    // MARK: - Global KSPlayer config

    /// Configure KS first/second types from prefs + optional URL detection.
    static func applyGlobal(_ prefs: PlayerPrefs, forURL urlString: String?) {
        KSOptions.isAutoPlay = true
        KSOptions.hardwareDecode = prefs.hardwareDecode
        KSOptions.asynchronousDecompression = prefs.asynchronousDecompression
        KSOptions.preferredFrame = prefs.adaptiveFrameRate
        KSOptions.preferredForwardBufferDuration = prefs.clampedBufferSeconds
        KSOptions.maxBufferDuration = max(15, prefs.clampedBufferSeconds * 5)
        KSOptions.isSecondOpen = true
        KSOptions.logLevel = .warning

        let preferAV: Bool = {
            switch prefs.primaryPlayer {
            case .avKit:
                return true
            case .ksPlayer, .mpvKit:
                return false
            case .auto:
                guard let urlString else {
                    // No URL yet — TS-first default (IPTV).
                    return false
                }
                switch StreamContainer.detect(urlString) {
                case .hls: return true
                case .ts, .unknown: return false
                }
            }
        }()

        if preferAV {
            KSOptions.firstPlayerType = KSAVPlayer.self
            KSOptions.secondPlayerType = prefs.fallbackPlayers ? KSMEPlayer.self : nil
        } else {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = prefs.fallbackPlayers ? KSAVPlayer.self : nil
        }
    }

    /// Back-compat for Settings call sites.
    static func applyGlobal(_ prefs: PlayerPrefs) {
        applyGlobal(prefs, forURL: nil)
    }

    // MARK: - Private

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
                if count == 0 {
                    if !self.isPlaying {
                        self.isBuffering = true
                    }
                } else {
                    self.isBuffering = true
                    self.isLoading = false
                }
            }
        }
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
        mpvStateWatch?.cancel()
        mpvStateWatch = nil
        mpvBag.removeAll()
        mpvEngine?.stop()

        if clearCallbacks {
            coordinator.resetPlayer()
        } else {
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
        guard Self.makeURL(urlString) != nil else {
            error = "Invalid stream URL"
            isLoading = false
            isBuffering = false
            return
        }

        currentURL = urlString
        detectedContainer = StreamContainer.detect(urlString)
        isLoading = true
        isBuffering = true
        isPlaying = false
        error = nil

        // Route: explicit MPV, or Auto never uses MPV yet — MPV is opt-in spike.
        let useMPV = prefs.primaryPlayer == .mpvKit
            && detectedContainer != .hls // prefer AV/KS for clean HLS even if MPV selected? User asked AV for HLS
        // If user picked MPV but stream is HLS → use AV via KS path
        if prefs.primaryPlayer == .mpvKit && detectedContainer == .hls {
            usesMPV = false
            openKS(urlString: urlString, generation: generation, forceAV: true)
            engineLabel = "Auto · HLS → AV (MPV skipped)"
            return
        }
        if useMPV {
            openMPV(urlString: urlString, generation: generation)
            return
        }

        usesMPV = false
        openKS(urlString: urlString, generation: generation, forceAV: nil)
    }

    private func openKS(urlString: String, generation: Int, forceAV: Bool?) {
        guard let u = Self.makeURL(urlString) else { return }

        let preferAV: Bool
        if let forceAV {
            preferAV = forceAV
        } else {
            switch prefs.primaryPlayer {
            case .avKit:
                preferAV = true
            case .ksPlayer, .mpvKit:
                preferAV = false
            case .auto:
                preferAV = (detectedContainer == .hls)
            }
        }

        KSOptions.isAutoPlay = true
        KSOptions.hardwareDecode = prefs.hardwareDecode
        KSOptions.asynchronousDecompression = prefs.asynchronousDecompression
        KSOptions.preferredFrame = prefs.adaptiveFrameRate
        KSOptions.preferredForwardBufferDuration = prefs.clampedBufferSeconds
        KSOptions.maxBufferDuration = max(15, prefs.clampedBufferSeconds * 5)
        KSOptions.isSecondOpen = true
        KSOptions.logLevel = .warning
        if preferAV {
            KSOptions.firstPlayerType = KSAVPlayer.self
            KSOptions.secondPlayerType = prefs.fallbackPlayers ? KSMEPlayer.self : nil
        } else {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = prefs.fallbackPlayers ? KSAVPlayer.self : nil
        }

        let tag = detectedContainer.shortLabel
        switch prefs.primaryPlayer {
        case .auto:
            engineLabel = "Auto · \(tag) → \(preferAV ? "AV" : "KS")"
                + (prefs.fallbackPlayers ? " · fallback" : "")
        case .ksPlayer:
            engineLabel = "KS · \(tag)" + (prefs.fallbackPlayers ? " · fallback" : "")
        case .avKit:
            engineLabel = "AV · \(tag)" + (prefs.fallbackPlayers ? " · fallback" : "")
        case .mpvKit:
            engineLabel = preferAV ? "AV · HLS" : "KS · \(tag)"
        }

        options = makeOptions()
        attachCoordinatorCallbacks()
        playURL = u

        firstFrameWatch?.cancel()
        firstFrameWatch = Task { @MainActor in
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

    private func openMPV(urlString: String, generation: Int) {
        usesMPV = true
        playURL = nil // KS surface unused
        engineLabel = "MPV · \(detectedContainer.shortLabel) (spike)"

        let engine = mpvEngine ?? MPVPlayerController()
        mpvEngine = engine
        engine.configure(
            userAgent: prefs.userAgent,
            bufferSeconds: prefs.clampedBufferSeconds,
            hardwareDecode: prefs.hardwareDecode
        )

        mpvBag.removeAll()
        engine.$isLoading.receive(on: RunLoop.main).sink { [weak self] v in
            self?.isLoading = v
        }.store(in: &mpvBag)
        engine.$isBuffering.receive(on: RunLoop.main).sink { [weak self] v in
            self?.isBuffering = v
        }.store(in: &mpvBag)
        engine.$isPlaying.receive(on: RunLoop.main).sink { [weak self] v in
            if v {
                self?.markReady()
            } else if self?.isLoading == false {
                self?.isPlaying = false
            }
        }.store(in: &mpvBag)
        engine.$error.receive(on: RunLoop.main).sink { [weak self] err in
            guard let self, let err, !err.isEmpty else { return }
            self.handleFail(err, generation: generation)
        }.store(in: &mpvBag)

        engine.start(url: urlString)

        // Timeout
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard generation == self.loadGeneration, self.isLoading, !self.isPlaying else { return }
            self.handleFail("Stream timed out while loading (mpv)", generation: generation)
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

        // MPV fail → fall back to KS Auto path once if fallback on
        if usesMPV, prefs.fallbackPlayers, let url = currentURL {
            banner = "MPV failed — trying KS/AV…"
            usesMPV = false
            mpvEngine?.stop()
            openKS(urlString: candidateURLs[candidateIndex], generation: generation, forceAV: detectedContainer == .hls)
            clearBannerSoon()
            return
        }

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
            clearBannerSoon()
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

    private func clearBannerSoon() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if banner != nil { banner = nil }
        }
    }

    private static func makeURL(_ string: String) -> URL? {
        if let u = URL(string: string) { return u }
        if let encoded = string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: encoded)
        }
        return nil
    }
}
