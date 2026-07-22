import AVFoundation
import AVKit
import Combine
import Foundation

#if os(iOS)
import MobileVLCKit
#elseif os(tvOS)
import TVVLCKit
#endif

/// Which concrete engine is currently driving the surface.
enum PlaybackEngineKind: String, Sendable {
    case vlc
    case avPlayer
}

/// Multi-engine playback: **official VLCKit** (hard IPTV) + **AVPlayer** (clean HLS).
/// Path A — CocoaPods MobileVLCKit / TVVLCKit (not SPM wrappers).
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isPlaying = false
    @Published var error: String?
    @Published var banner: String?
    @Published private(set) var engineLabel: String = ""
    @Published private(set) var activeEngine: PlaybackEngineKind = .vlc
    @Published private(set) var aspectFill = false

    /// Shared VLC player — drawable is attached by `VLCPlayerSurface`.
    let vlcPlayer = VLCMediaPlayer()
    /// Native AVPlayer for clean HLS / system features.
    let avPlayer = AVPlayer()

    private var currentURL: String?
    private var candidateURLs: [String] = []
    private var candidateIndex = 0
    private var engineAttemptIndex = 0
    private var engineOrder: [PlaybackEngineKind] = [.vlc]
    private var loadGeneration = 0
    private var prefs = PlayerPrefs()
    private var vlcObserver: NSObjectProtocol?
    private var avTimeObserver: Any?
    private var avStatusCancellable: AnyCancellable?
    private var avItemCancellable: AnyCancellable?
    private var stallWatch: Task<Void, Never>?

    init() {
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        #if os(iOS)
        avPlayer.allowsExternalPlayback = true
        avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        #endif
    }

    deinit {
        // MainActor class — cleanup via stop when possible; remove observers best-effort.
    }

    func configure(prefs: PlayerPrefs) {
        self.prefs = prefs
        engineLabel = prefs.primaryPlayer.label
            + (prefs.fallbackPlayers ? " · fallback on" : "")
    }

    /// No-op global retained for settings call sites (was KSOptions).
    static func applyGlobal(_ prefs: PlayerPrefs) {
        // Network caching / audio session configured per start.
        _ = prefs
    }

    func start(url: String) {
        stopPlayerOnly(clearError: true)

        currentURL = url
        candidateURLs = IptvService.playbackURLCandidates(
            from: url,
            preferredFormat: prefs.preferredLiveFormat
        )
        candidateIndex = 0
        engineAttemptIndex = 0
        engineOrder = Self.engineOrder(for: candidateURLs.first ?? url, prefs: prefs)
        loadGeneration += 1
        let gen = loadGeneration
        isLoading = true
        isBuffering = true
        isPlaying = false
        error = nil

        Task { @MainActor in
            await configureAudioSession()
            guard gen == self.loadGeneration else { return }
            guard let first = self.candidateURLs.first else {
                self.error = "Invalid stream URL"
                self.isLoading = false
                return
            }
            self.open(urlString: first, generation: gen, engine: self.engineOrder[0])
        }
    }

    func stop() {
        loadGeneration += 1
        stallWatch?.cancel()
        stallWatch = nil
        stopPlayerOnly(clearError: true)
        currentURL = nil
        candidateURLs = []
        candidateIndex = 0
        engineAttemptIndex = 0
        banner = nil
        isLoading = false
        isBuffering = false
        isPlaying = false
    }

    func jumpToLive() {
        switch activeEngine {
        case .vlc:
            // VLC live: stop/start is the reliable live-edge rejoin.
            if let url = currentURL {
                start(url: url)
                banner = "Rejoined live stream"
            }
        case .avPlayer:
            if let item = avPlayer.currentItem {
                let duration = item.duration
                if duration.isNumeric && duration.seconds.isFinite && duration.seconds > 2 {
                    let live = CMTime(seconds: max(0, duration.seconds - 0.5), preferredTimescale: 600)
                    avPlayer.seek(to: live, toleranceBefore: .zero, toleranceAfter: .zero)
                    avPlayer.play()
                    markReady()
                    banner = "Jumped to live"
                } else if let url = currentURL {
                    start(url: url)
                    banner = "Rejoined live stream"
                }
            } else if let url = currentURL {
                start(url: url)
                banner = "Rejoined live stream"
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if banner != nil { banner = nil }
        }
    }

    func setAspectFill(_ fill: Bool) {
        aspectFill = fill
    }

    // MARK: - Transport

    func togglePlayPause() {
        switch activeEngine {
        case .vlc:
            if vlcPlayer.isPlaying {
                vlcPlayer.pause()
                isPlaying = false
            } else {
                vlcPlayer.play()
                isPlaying = true
                isLoading = false
                isBuffering = false
            }
        case .avPlayer:
            if avPlayer.timeControlStatus == .playing {
                avPlayer.pause()
                isPlaying = false
            } else {
                avPlayer.play()
                isPlaying = true
                isLoading = false
                isBuffering = false
            }
        }
    }

    func pause() {
        vlcPlayer.pause()
        avPlayer.pause()
        isPlaying = false
    }

    func resumePlay() {
        switch activeEngine {
        case .vlc: vlcPlayer.play()
        case .avPlayer: avPlayer.play()
        }
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
        if let audio = vlcPlayer.audio {
            audio.isMuted = muted
        }
        avPlayer.isMuted = muted
    }

    var isMuted: Bool {
        switch activeEngine {
        case .vlc: return vlcPlayer.audio?.isMuted ?? false
        case .avPlayer: return avPlayer.isMuted
        }
    }

    func togglePictureInPicture() {
        // System PiP is strongest on AVPlayer; VLC path shows guidance.
        if activeEngine == .avPlayer {
            banner = "Use the system PiP control or pop-out player"
        } else {
            banner = "PiP: switch to AVKit for system Picture in Picture, or use Pop out"
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if banner?.contains("PiP") == true { banner = nil }
        }
    }

    var isPiPActive: Bool { false }

    struct SubtitleOption: Identifiable, Hashable {
        var id: String
        var name: String
        var isEnabled: Bool
    }

    func subtitleOptions() -> [SubtitleOption] {
        guard activeEngine == .vlc else { return [] }
        // VLC exposes tracks via videoSubTitlesIndexes / Names when available.
        let indexes = vlcPlayer.videoSubTitlesIndexes as? [NSNumber] ?? []
        let names = vlcPlayer.videoSubTitlesNames as? [String] ?? []
        return indexes.enumerated().map { idx, num in
            let name = idx < names.count ? names[idx] : "Track \(idx + 1)"
            let current = vlcPlayer.currentVideoSubTitleIndex
            return SubtitleOption(
                id: "\(num.intValue)",
                name: name,
                isEnabled: num.int32Value == current
            )
        }
    }

    func selectSubtitle(named name: String?) {
        guard activeEngine == .vlc else {
            banner = "Captions: switch to VLC engine"
            return
        }
        let indexes = vlcPlayer.videoSubTitlesIndexes as? [NSNumber] ?? []
        let names = vlcPlayer.videoSubTitlesNames as? [String] ?? []
        if let name, let idx = names.firstIndex(of: name), idx < indexes.count {
            vlcPlayer.currentVideoSubTitleIndex = indexes[idx].int32Value
            banner = "Subtitles: \(name)"
        } else {
            vlcPlayer.currentVideoSubTitleIndex = -1
            banner = "Subtitles: Off"
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if banner?.hasPrefix("Subtitles") == true { banner = nil }
        }
    }

    func cycleSubtitleTrack() {
        let opts = subtitleOptions()
        guard !opts.isEmpty else {
            banner = "No captions on this stream"
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if banner?.contains("captions") == true { banner = nil }
            }
            return
        }
        if let current = opts.firstIndex(where: \.isEnabled) {
            let next = current + 1
            if next < opts.count {
                selectSubtitle(named: opts[next].name)
            } else {
                selectSubtitle(named: nil)
                banner = "Subtitles: cycle complete"
            }
        } else {
            selectSubtitle(named: opts[0].name)
        }
    }

    // MARK: - Engine selection

    private static func engineOrder(for url: String, prefs: PlayerPrefs) -> [PlaybackEngineKind] {
        let lower = url.lowercased()
        let looksHLS = lower.contains(".m3u8")
        let looksTS = lower.contains(".ts") && !looksHLS

        let primary: PlaybackEngineKind = {
            switch prefs.primaryPlayer {
            case .vlc: return .vlc
            case .avKit: return .avPlayer
            case .auto:
                // Clean HLS → AV first; TS / unknown IPTV → VLC first.
                return looksHLS && !looksTS ? .avPlayer : .vlc
            }
        }()

        if !prefs.fallbackPlayers {
            return [primary]
        }
        let secondary: PlaybackEngineKind = (primary == .vlc) ? .avPlayer : .vlc
        return [primary, secondary]
    }

    // MARK: - Open / fail

    private func open(urlString: String, generation: Int, engine: PlaybackEngineKind) {
        guard generation == loadGeneration else { return }
        guard let url = Self.makeURL(urlString) else {
            handleFail("Invalid stream URL", generation: generation)
            return
        }

        activeEngine = engine
        currentURL = urlString
        isLoading = true
        isBuffering = true
        isPlaying = false
        error = nil
        engineLabel = (engine == .vlc ? "VLC" : "AV")
            + (prefs.fallbackPlayers ? " · fallback on" : "")

        switch engine {
        case .vlc:
            openVLC(url: url, generation: generation)
        case .avPlayer:
            openAV(url: url, generation: generation)
        }

        stallWatch?.cancel()
        stallWatch = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard generation == self.loadGeneration, self.isLoading, !self.isPlaying else { return }
            self.handleFail("Stream timed out while loading", generation: generation)
        }
    }

    private func openVLC(url: URL, generation: Int) {
        detachAVObservers()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)

        let media = VLCMedia(url: url)
        var opts: [String: Any] = [
            "network-caching": Int(prefs.clampedBufferSeconds * 1000),
            "live-caching": Int(prefs.clampedBufferSeconds * 1000),
            "file-caching": 300,
            "clock-jitter": 0,
            "clock-synchro": 0,
        ]
        let ua = prefs.userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ua.isEmpty {
            opts["http-user-agent"] = ua
        }
        media.addOptions(opts)
        vlcPlayer.media = media
        vlcPlayer.delegate = VLCPlayerBridge.shared
        VLCPlayerBridge.shared.attach(self, generation: generation)
        vlcPlayer.play()
    }

    private func openAV(url: URL, generation: Int) {
        vlcPlayer.stop()
        vlcPlayer.media = nil
        VLCPlayerBridge.shared.detach(self)

        detachAVObservers()
        let headers: [String: String] = {
            let ua = prefs.userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
            return ua.isEmpty ? [:] : ["User-Agent": ua]
        }()
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        avPlayer.replaceCurrentItem(with: item)
        avPlayer.play()

        avStatusCancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, generation == self.loadGeneration else { return }
                switch status {
                case .readyToPlay:
                    self.markReady()
                case .failed:
                    self.handleFail(item.error?.localizedDescription ?? "AVPlayer failed", generation: generation)
                default:
                    break
                }
            }

        avItemCancellable = item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keepUp in
                guard let self, generation == self.loadGeneration else { return }
                if keepUp {
                    self.markReady()
                } else if self.isPlaying {
                    self.isBuffering = true
                }
            }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, generation == self.loadGeneration else { return }
                let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                self.handleFail(err ?? "Playback failed", generation: generation)
            }
        }
    }

    private func stopPlayerOnly(clearError: Bool) {
        stallWatch?.cancel()
        stallWatch = nil
        VLCPlayerBridge.shared.detach(self)
        vlcPlayer.stop()
        vlcPlayer.media = nil
        detachAVObservers()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        if clearError { error = nil }
    }

    private func detachAVObservers() {
        avStatusCancellable?.cancel()
        avStatusCancellable = nil
        avItemCancellable?.cancel()
        avItemCancellable = nil
        if let avTimeObserver {
            avPlayer.removeTimeObserver(avTimeObserver)
            self.avTimeObserver = nil
        }
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

    func markReady() {
        isLoading = false
        isBuffering = false
        isPlaying = true
        error = nil
    }

    func handleVLCState(_ state: VLCMediaPlayerState, generation: Int) {
        guard generation == loadGeneration, activeEngine == .vlc else { return }
        switch state {
        case .buffering:
            if !isPlaying { isLoading = true }
            isBuffering = true
        case .playing:
            markReady()
        case .paused:
            isPlaying = false
            isLoading = false
            isBuffering = false
        case .error:
            handleFail("VLC playback failed", generation: generation)
        case .stopped, .ended:
            if let url = currentURL {
                // Live reconnect
                banner = "Stream ended — rejoining…"
                start(url: url)
            }
        default:
            break
        }
    }

    private func handleFail(_ message: String, generation: Int) {
        guard generation == loadGeneration else { return }

        // Next engine for this URL
        let nextEngine = engineAttemptIndex + 1
        if nextEngine < engineOrder.count {
            engineAttemptIndex = nextEngine
            banner = "Trying \(engineOrder[nextEngine] == .vlc ? "VLC" : "AVKit")…"
            stopPlayerOnly(clearError: true)
            isLoading = true
            isBuffering = true
            open(urlString: candidateURLs[candidateIndex], generation: generation, engine: engineOrder[nextEngine])
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.banner?.contains("Trying") == true { self.banner = nil }
            }
            return
        }

        // Next URL candidate, reset engines
        let nextURL = candidateIndex + 1
        if nextURL < candidateURLs.count {
            candidateIndex = nextURL
            engineAttemptIndex = 0
            engineOrder = Self.engineOrder(for: candidateURLs[nextURL], prefs: prefs)
            banner = "Trying alternate format…"
            stopPlayerOnly(clearError: true)
            isLoading = true
            isBuffering = true
            open(urlString: candidateURLs[nextURL], generation: generation, engine: engineOrder[0])
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
        let l = raw.lowercased()
        if l.contains("timeout") { return "Stream timed out. Check your connection or try another channel." }
        if l.contains("401") || l.contains("403") { return "Access denied. Playlist credentials may be expired." }
        if l.contains("404") { return "Stream not found. Channel may be offline." }
        return raw
    }

    private static func makeURL(_ string: String) -> URL? {
        if let u = URL(string: string), u.scheme != nil { return u }
        return URL(string: string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? string)
    }
}

// MARK: - VLC delegate bridge (ObjC delegate → MainActor controller)

@MainActor
final class VLCPlayerBridge: NSObject, VLCMediaPlayerDelegate {
    static let shared = VLCPlayerBridge()

    private weak var controller: PlaybackController?
    private var generation: Int = 0

    func attach(_ controller: PlaybackController, generation: Int) {
        self.controller = controller
        self.generation = generation
    }

    func detach(_ controller: PlaybackController) {
        if self.controller === controller {
            self.controller = nil
        }
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            self.controller?.handleVLCState(player.state, generation: self.generation)
        }
    }
}
