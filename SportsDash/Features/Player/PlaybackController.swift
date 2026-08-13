import AVFoundation
import Combine
import Foundation

#if os(iOS)
extension Notification.Name {
    static let sportsDashWillBackground = Notification.Name("SportsDashWillBackground")
}
#endif

/// Multi-engine playback for SportsDash:
/// - **Auto (default):** TS / unknown → **VLC** (libVLC); HLS → **AVPlayer**
/// - Explicit VLC or AV overrides
/// Cross-platform story: Android ships the same libVLC family.
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isPlaying = false
    @Published var error: String?
    @Published var banner: String?
    @Published private(set) var engineLabel: String = ""
    @Published private(set) var detectedContainer: StreamContainer = .unknown
    @Published private(set) var activeBackend: PlayerBackend = .vlc

    enum PlayerBackend: String {
        case vlc
        case av
    }

    private(set) var vlcEngine = VLCPlayerController()
    private(set) var avEngine = AVPlayerEngine()

    private var currentURL: String?
    private var candidateURLs: [String] = []
    private var candidateIndex = 0
    private var loadGeneration = 0
    private var prefs = PlayerPrefs()
    private var bags = Set<AnyCancellable>()
    private var muted = false
    private var didCrossEngineFallback = false

    #if os(iOS)
    private var lifecycleObserver: Any?
    #endif

    init() {
        bindEngines()
        #if os(iOS)
        startObservingLifecycle()
        #endif
    }

    func configure(prefs: PlayerPrefs) {
        self.prefs = prefs
        engineLabel = prefs.primaryPlayer.label
            + (prefs.fallbackPlayers ? " · fallback on" : "")
        vlcEngine.configure(
            userAgent: prefs.userAgent,
            bufferSeconds: prefs.clampedBufferSeconds,
            hardwareDecode: prefs.hardwareDecode
        )
        avEngine.configure(userAgent: prefs.userAgent)
    }

    static func applyGlobal(_ prefs: PlayerPrefs) {
        // No KS global config anymore.
        _ = prefs
    }

    func start(url: String) {
        stopEngines(clearError: true)
        currentURL = url
        candidateURLs = IptvService.playbackURLCandidates(
            from: url,
            preferredFormat: prefs.preferredLiveFormat
        )
        candidateIndex = 0
        loadGeneration += 1
        didCrossEngineFallback = false
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
        stopEngines(clearError: true)
        currentURL = nil
        candidateURLs = []
        candidateIndex = 0
        banner = nil
        isLoading = false
        isBuffering = false
        isPlaying = false
        isPiPActive = false
    }

    func jumpToLive() {
        switch activeBackend {
        case .vlc:
            vlcEngine.jumpToLive()
        case .av:
            avEngine.jumpToLive()
        }
        banner = "Jumped to live"
        clearBannerSoon()
    }

    func togglePlayPause() {
        switch activeBackend {
        case .vlc: vlcEngine.togglePlayPause()
        case .av: avEngine.togglePlayPause()
        }
        isPlaying = activeBackend == .vlc ? vlcEngine.isPlaying : avEngine.isPlaying
    }

    func pause() {
        switch activeBackend {
        case .vlc: vlcEngine.pause()
        case .av: avEngine.pause()
        }
        isPlaying = false
    }

    func resumePlay() {
        switch activeBackend {
        case .vlc: vlcEngine.play()
        case .av: avEngine.play()
        }
        isPlaying = true
        isLoading = false
        isBuffering = false
    }

    func toggleMute() {
        setMuted(!muted)
        banner = muted ? "Muted" : "Unmuted"
        clearBannerSoon()
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        vlcEngine.setMuted(muted)
        avEngine.setMuted(muted)
    }

    var isMuted: Bool { muted }

    // MARK: - System Picture-in-Picture support (iOS AV path only for video PiP)
    // Simplified: system PiP only via AV/HLS automatic path on AVPlayerViewController.
    // VLC/TS: no system video PiP; audio bg + in-app float only. No auto handoff/destructive switch.
    #if os(iOS)
    var supportsSystemPictureInPicture: Bool {
        if activeBackend == .av {
            return avEngine.supportsSystemPiP
        }
        return false
    }

    var canUseSystemPiP: Bool {
        supportsSystemPictureInPicture
    }

    @Published private(set) var isPiPActive: Bool = false
    #else
    var supportsSystemPictureInPicture: Bool { false }
    var canUseSystemPiP: Bool { false }
    @Published private(set) var isPiPActive: Bool = false
    #endif

    func togglePictureInPicture() {
        #if os(iOS)
        if activeBackend == .av {
            if avEngine.supportsSystemPiP {
                avEngine.startSystemPiPIfPossible()
            } else {
                banner = "System PiP not supported on this device"
                clearBannerSoon()
            }
        } else {
            // Honest for VLC: no destructive handoff
            startSystemPiPIfPossible()
        }
        #else
        banner = "System Picture-in-Picture is iOS-only"
        clearBannerSoon()
        #endif
    }

    func startSystemPiPIfPossible() {
        #if os(iOS)
        guard isPlaying else { return }
        if activeBackend == .av {
            // Rely on automatic PiP (flags already set on AVPlayerSurface).
            // AVPlayerViewController will enter PiP on background when playing inline.
            banner = nil
            avEngine.startSystemPiPIfPossible()  // no-op but keeps API
            return
        }
        // VLC path: DO NOT stop VLC, do not handoff. Show banner once.
        banner = "System video PiP works on AV/HLS streams. VLC/TS keeps audio in background; use in-app pop-out inside SportsDash."
        clearBannerSoon()
        // Keep VLC running for audio bg.
        #else
        banner = "PiP is iOS-only"
        clearBannerSoon()
        #endif
    }

    #if os(iOS)
    func startObservingLifecycle() {
        // Clean previous
        if let obs = lifecycleObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: .sportsDashWillBackground,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPlaying else { return }
                // Only for .av let automatic PiP work (no spam on VLC).
                // For VLC: silent (audio bg continues; no banner spam every background).
                if self.activeBackend == .av {
                    self.startSystemPiPIfPossible()
                }
                // else: silent for VLC/TS
            }
        }
    }
    #endif

    struct SubtitleOption: Identifiable, Hashable {
        var id: String
        var name: String
        var isEnabled: Bool
    }

    func subtitleOptions() -> [SubtitleOption] { [] }

    func selectSubtitle(named name: String?) {
        _ = name
        banner = "Captions: not wired on VLC path yet"
        clearBannerSoon()
    }

    func cycleSubtitleTrack() {
        banner = "Captions: not wired on VLC path yet"
        clearBannerSoon()
    }

    // MARK: - Private

    private func bindEngines() {
        vlcEngine.$isLoading.receive(on: RunLoop.main).sink { [weak self] v in
            guard let self, self.activeBackend == .vlc else { return }
            self.isLoading = v
        }.store(in: &bags)
        vlcEngine.$isBuffering.receive(on: RunLoop.main).sink { [weak self] v in
            guard let self, self.activeBackend == .vlc else { return }
            self.isBuffering = v
        }.store(in: &bags)
        vlcEngine.$isPlaying.receive(on: RunLoop.main).sink { [weak self] v in
            guard let self, self.activeBackend == .vlc else { return }
            if v {
                self.isLoading = false
                self.isBuffering = false
                self.isPlaying = true
                self.error = nil
            } else if !self.isLoading {
                self.isPlaying = false
            }
        }.store(in: &bags)
        #if os(iOS)
        avEngine.$isSystemPiPActive.receive(on: RunLoop.main).sink { [weak self] v in
            guard let self, self.activeBackend == .av else { return }
            self.isPiPActive = v
        }.store(in: &bags)
        #endif
        vlcEngine.$error.receive(on: RunLoop.main).sink { [weak self] err in
            guard let self, self.activeBackend == .vlc, let err, !err.isEmpty else { return }
            self.handleFail(err, generation: self.loadGeneration)
        }.store(in: &bags)

        avEngine.$isLoading.receive(on: RunLoop.main).sink { [weak self] v in
            guard let self, self.activeBackend == .av else { return }
            self.isLoading = v
        }.store(in: &bags)
        avEngine.$isBuffering.receive(on: RunLoop.main).sink { [weak self] v in
            guard let self, self.activeBackend == .av else { return }
            self.isBuffering = v
        }.store(in: &bags)
        avEngine.$isPlaying.receive(on: RunLoop.main).sink { [weak self] v in
            guard let self, self.activeBackend == .av else { return }
            if v {
                self.isLoading = false
                self.isBuffering = false
                self.isPlaying = true
                self.error = nil
            } else if !self.isLoading {
                self.isPlaying = false
            }
        }.store(in: &bags)
        avEngine.$error.receive(on: RunLoop.main).sink { [weak self] err in
            guard let self, self.activeBackend == .av, let err, !err.isEmpty else { return }
            self.handleFail(err, generation: self.loadGeneration)
        }.store(in: &bags)

    }

    private func stopEngines(clearError: Bool) {
        vlcEngine.stop()
        avEngine.stop()
        if clearError { error = nil }
    }

    private func configureAudioSession() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {}
    }

    private func open(urlString: String, generation: Int) {
        currentURL = urlString
        detectedContainer = StreamContainer.detect(urlString)
        isLoading = true
        isBuffering = true
        isPlaying = false
        error = nil

        let preferAV: Bool = {
            switch prefs.primaryPlayer {
            case .avKit: return true
            case .vlc, .ksPlayer, .mpvKit: return false
            case .auto:
                return detectedContainer == .hls
            }
        }()

        if preferAV {
            activeBackend = .av
            engineLabel = label(for: .av)
            avEngine.configure(userAgent: prefs.userAgent)
            avEngine.start(url: urlString)
        } else {
            activeBackend = .vlc
            engineLabel = label(for: .vlc)
            vlcEngine.configure(
                userAgent: prefs.userAgent,
                bufferSeconds: prefs.clampedBufferSeconds,
                hardwareDecode: prefs.hardwareDecode
            )
            vlcEngine.start(url: urlString)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard generation == self.loadGeneration, self.isLoading, !self.isPlaying else { return }
            self.handleFail("Stream timed out while loading", generation: generation)
        }
    }

    private func label(for backend: PlayerBackend) -> String {
        let tag = detectedContainer.shortLabel
        switch prefs.primaryPlayer {
        case .auto:
            return "Auto · \(tag) → \(backend == .av ? "AV" : "VLC")"
                + (prefs.fallbackPlayers ? " · fallback" : "")
        case .vlc, .ksPlayer, .mpvKit:
            return "VLC · \(tag)" + (prefs.fallbackPlayers ? " · fallback" : "")
        case .avKit:
            return "AV · \(tag)" + (prefs.fallbackPlayers ? " · fallback" : "")
        }
    }

    private func handleFail(_ message: String, generation: Int) {
        guard generation == loadGeneration else { return }

        // Cross-engine fallback once
        if prefs.fallbackPlayers, !didCrossEngineFallback {
            didCrossEngineFallback = true
            if activeBackend == .vlc {
                banner = "VLC failed — trying AV…"
                activeBackend = .av
                engineLabel = "Fallback · AV"
                isLoading = true
                isBuffering = true
                isPlaying = false
                error = nil
                avEngine.start(url: candidateURLs[candidateIndex])
                clearBannerSoon()
                return
            } else {
                banner = "AV failed — trying VLC…"
                activeBackend = .vlc
                engineLabel = "Fallback · VLC"
                isLoading = true
                isBuffering = true
                isPlaying = false
                error = nil
                vlcEngine.start(url: candidateURLs[candidateIndex])
                clearBannerSoon()
                return
            }
        }

        let next = candidateIndex + 1
        if next < candidateURLs.count {
            candidateIndex = next
            banner = "Trying alternate format…"
            stopEngines(clearError: true)
            isLoading = true
            isBuffering = true
            isPlaying = false
            open(urlString: candidateURLs[next], generation: generation)
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
        if s.contains("network") || s.contains("-1009") {
            return "Network error. Check Wi‑Fi or try again."
        }
        if s.contains("401") || s.contains("403") || s.contains("auth") {
            return "Access denied. Re-save IPTV credentials in Settings."
        }
        if s.contains("404") || s.contains("not found") {
            return "Stream not found. Try another channel."
        }
        if s.contains("format") || s.contains("demux") {
            return "Format not supported. Try Auto mode or another stream."
        }
        return raw
    }

    private func clearBannerSoon() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if banner != nil { banner = nil }
        }
    }
}
