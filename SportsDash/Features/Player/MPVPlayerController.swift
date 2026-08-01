import AVFoundation
import Combine
import Foundation
import QuartzCore

#if canImport(UIKit)
import UIKit
#endif

#if canImport(Libmpv)
import Libmpv
#endif

/// Spike hard engine: libmpv via MPVKit **LGPL** product only (never MPVKit-GPL).
/// Clean-room SportsDash wrapper — not a copy of Nuvio app sources.
@MainActor
final class MPVPlayerController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isPlaying = false
    @Published var error: String?

    #if canImport(UIKit)
    let hostView = MPVHostView()
    #endif

    #if canImport(Libmpv)
    private var mpv: OpaquePointer?
    private let eventQueue = DispatchQueue(label: "sportsdash.mpv.events", qos: .userInitiated)
    private var loadGeneration = 0
    private var userAgent = "VLC/3.0.18 LibVLC/3.0.18"
    private var bufferSeconds: Double = 3
    private var hardwareDecode = true
    #endif

    var isLinked: Bool {
        #if canImport(Libmpv)
        true
        #else
        false
        #endif
    }

    func configure(userAgent: String, bufferSeconds: Double, hardwareDecode: Bool) {
        #if canImport(Libmpv)
        let ua = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userAgent = ua.isEmpty ? "VLC/3.0.18 LibVLC/3.0.18" : ua
        self.bufferSeconds = max(1, min(15, bufferSeconds))
        self.hardwareDecode = hardwareDecode
        #endif
    }

    func start(url: String) {
        #if canImport(Libmpv)
        error = nil
        isLoading = true
        isBuffering = true
        isPlaying = false
        loadGeneration += 1
        let gen = loadGeneration

        ensureMpv()
        guard mpv != nil else {
            isLoading = false
            isBuffering = false
            return
        }

        applyHeaders()
        let cacheSecs = Int(max(2, bufferSeconds))
        setOption("cache", "yes")
        setOption("demuxer-readahead-secs", "\(cacheSecs)")
        setOption("cache-secs", "\(cacheSecs)")
        setOption("hwdec", hardwareDecode ? "videotoolbox" : "no")
        setOption("network-timeout", "15")
        setOption("stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=5")

        command(["loadfile", url, "replace"])

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard gen == self.loadGeneration, self.isLoading, !self.isPlaying else { return }
            self.error = "Stream timed out while loading (mpv)"
            self.isLoading = false
            self.isBuffering = false
        }
        #else
        error = "Libmpv not linked — add MPVKit (LGPL product) via SPM."
        isLoading = false
        isBuffering = false
        #endif
    }

    func stop() {
        #if canImport(Libmpv)
        loadGeneration += 1
        if mpv != nil { command(["stop"]) }
        isLoading = false
        isBuffering = false
        isPlaying = false
        #endif
    }

    func destroy() {
        #if canImport(Libmpv)
        stop()
        if let mpv {
            mpv_terminate_destroy(mpv)
        }
        mpv = nil
        #endif
    }

    func play() {
        #if canImport(Libmpv)
        setProperty("pause", "no")
        isPlaying = true
        #endif
    }

    func pause() {
        #if canImport(Libmpv)
        setProperty("pause", "yes")
        isPlaying = false
        #endif
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func jumpToLive() {
        #if canImport(Libmpv)
        command(["seek", "100", "absolute-percent", "exact"])
        play()
        #endif
    }

    #if canImport(Libmpv)
    private func ensureMpv() {
        if mpv != nil { return }
        #if canImport(UIKit)
        hostView.layoutIfNeeded()
        let layer = hostView.metalLayer
        mpv = mpv_create()
        guard let mpv else {
            error = "Failed to create mpv instance"
            return
        }
        _ = mpv_request_log_messages(mpv, "warn")

        var layerPtr = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerPtr)
        setOption("vo", "gpu-next")
        setOption("gpu-api", "vulkan")
        setOption("gpu-context", "moltenvk")
        setOption("hwdec", hardwareDecode ? "videotoolbox" : "no")
        setOption("ao", "audiounit")
        setOption("keep-open", "yes")
        setOption("idle", "yes")
        setOption("osc", "no")
        setOption("input-default-bindings", "no")

        let status = mpv_initialize(mpv)
        if status < 0 {
            error = "mpv_initialize failed (\(status))"
            mpv_terminate_destroy(mpv)
            self.mpv = nil
            return
        }

        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)

        let box = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let ctx else { return }
            let owner = Unmanaged<MPVPlayerController>.fromOpaque(ctx).takeUnretainedValue()
            owner.eventQueue.async { owner.drainEvents() }
        }, box)
        #endif
    }

    private func applyHeaders() {
        let fields = [
            "User-Agent: \(userAgent)",
            "Accept: */*",
            "Connection: keep-alive",
        ].joined(separator: "\r\n")
        setProperty("http-header-fields", fields)
        setOption("user-agent", userAgent)
    }

    private func drainEvents() {
        guard let mpv else { return }
        while true {
            guard let ev = mpv_wait_event(mpv, 0) else { break }
            let id = ev.pointee.event_id
            if id == MPV_EVENT_NONE { break }

            switch id {
            case MPV_EVENT_FILE_LOADED, MPV_EVENT_PLAYBACK_RESTART:
                Task { @MainActor in
                    self.isLoading = false
                    self.isBuffering = false
                    self.isPlaying = true
                    self.error = nil
                }
            case MPV_EVENT_END_FILE:
                Task { @MainActor in
                    // Treat unexpected end as failure if we never marked ready.
                    if self.isLoading {
                        self.error = "Playback failed (mpv end-file)"
                        self.isLoading = false
                        self.isBuffering = false
                        self.isPlaying = false
                    }
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                handlePropertyChange(ev)
            default:
                break
            }
        }
    }

    private func handlePropertyChange(_ ev: UnsafePointer<mpv_event>) {
        guard let propPtr = ev.pointee.data else { return }
        let prop = propPtr.assumingMemoryBound(to: mpv_event_property.self).pointee
        guard let nameC = prop.name else { return }
        let name = String(cString: nameC)

        if name == "paused-for-cache", prop.format == MPV_FORMAT_FLAG, let d = prop.data {
            let flag = d.assumingMemoryBound(to: Int32.self).pointee != 0
            Task { @MainActor in
                self.isBuffering = flag
                if flag { self.isLoading = false }
            }
        } else if name == "pause", prop.format == MPV_FORMAT_FLAG, let d = prop.data {
            let paused = d.assumingMemoryBound(to: Int32.self).pointee != 0
            Task { @MainActor in
                self.isPlaying = !paused
                if !paused {
                    self.isLoading = false
                    self.isBuffering = false
                }
            }
        } else if name == "time-pos", prop.format == MPV_FORMAT_DOUBLE {
            Task { @MainActor in
                if self.isLoading || self.isBuffering {
                    self.isLoading = false
                    self.isBuffering = false
                    self.isPlaying = true
                }
            }
        }
    }

    @discardableResult
    private func setOption(_ key: String, _ value: String) -> Bool {
        guard let mpv else { return false }
        return mpv_set_option_string(mpv, key, value) >= 0
    }

    @discardableResult
    private func setProperty(_ key: String, _ value: String) -> Bool {
        guard let mpv else { return false }
        return mpv_set_property_string(mpv, key, value) >= 0
    }

    private func command(_ args: [String]) {
        guard let mpv else { return }
        var cargs = args.map { strdup($0) } + [nil]
        defer {
            for p in cargs where p != nil { free(p) }
        }
        _ = mpv_command(mpv, &cargs)
    }
    #endif
}

#if canImport(UIKit)
final class MPVHostView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        metalLayer.backgroundColor = UIColor.black.cgColor
        #if os(iOS) || os(tvOS)
        metalLayer.contentsScale = UIScreen.main.scale
        #endif
        metalLayer.framebufferOnly = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds
        let scale = metalLayer.contentsScale
        metalLayer.drawableSize = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
    }
}

struct MPVPlayerSurface: UIViewRepresentable {
    @ObservedObject var engine: MPVPlayerController

    func makeUIView(context: Context) -> MPVHostView {
        engine.hostView
    }

    func updateUIView(_ uiView: MPVHostView, context: Context) {
        uiView.setNeedsLayout()
    }
}
#endif
