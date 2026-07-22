import AVFoundation
import AVKit
import SwiftUI

#if os(iOS)
import MobileVLCKit
import UIKit
#elseif os(tvOS)
import TVVLCKit
import UIKit
#endif

/// Hosts either VLC drawable or AVPlayerLayer based on `playback.activeEngine`.
struct PlayerSurface: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        ZStack {
            Color.black
            switch playback.activeEngine {
            case .vlc:
                VLCPlayerSurface(playback: playback)
            case .avPlayer:
                AVPlayerSurface(playback: playback)
            }
        }
        .background(Color.black)
    }
}

// Back-compat name used across PlayerView / FloatingPlayerView.
typealias KSPlayerSurface = PlayerSurface

// MARK: - VLC

struct VLCPlayerSurface: UIViewRepresentable {
    @ObservedObject var playback: PlaybackController

    func makeUIView(context: Context) -> VLCDrawableView {
        let view = VLCDrawableView()
        view.backgroundColor = .black
        playback.vlcPlayer.drawable = view
        return view
    }

    func updateUIView(_ uiView: VLCDrawableView, context: Context) {
        if playback.vlcPlayer.drawable as? UIView !== uiView {
            playback.vlcPlayer.drawable = uiView
        }
        uiView.contentMode = playback.aspectFill ? .scaleAspectFill : .scaleAspectFit
        // VLC uses videoAspectRatio / scale for some cases; contentMode on drawable helps letterbox.
    }

    static func dismantleUIView(_ uiView: VLCDrawableView, coordinator: ()) {
        // Drawable cleared when controller stops / swaps engines.
        _ = uiView
    }
}

/// Plain UIView used as VLC drawable surface.
final class VLCDrawableView: UIView {
    override class var layerClass: AnyClass { CALayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - AVPlayer

struct AVPlayerSurface: UIViewRepresentable {
    @ObservedObject var playback: PlaybackController

    func makeUIView(context: Context) -> AVPlayerLayerView {
        let view = AVPlayerLayerView()
        view.player = playback.avPlayer
        view.videoGravity = playback.aspectFill ? .resizeAspectFill : .resizeAspect
        return view
    }

    func updateUIView(_ uiView: AVPlayerLayerView, context: Context) {
        uiView.player = playback.avPlayer
        uiView.videoGravity = playback.aspectFill ? .resizeAspectFill : .resizeAspect
    }
}

final class AVPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
