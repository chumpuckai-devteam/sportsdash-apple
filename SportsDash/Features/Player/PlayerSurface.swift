import SwiftUI

/// Hosts VLC or AVPlayer surface for the active backend.
struct PlayerSurface: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        Group {
            #if canImport(UIKit)
            switch playback.activeBackend {
            case .vlc:
                VLCPlayerSurface(engine: playback.vlcEngine)
            case .av:
                AVPlayerSurface(engine: playback.avEngine)
            }
            #else
            Color.black
            #endif
        }
        .background(Color.black)
    }
}
