import SwiftUI

/// Chooses KSPlayer vs MPV (spike) surface for the active engine.
struct PlayerSurface: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        Group {
            #if canImport(UIKit)
            if playback.usesMPV, let mpv = playback.mpvEngine {
                MPVPlayerSurface(engine: mpv)
            } else {
                KSPlayerSurface(playback: playback)
            }
            #else
            Color.black
            #endif
        }
        .background(Color.black)
    }
}
