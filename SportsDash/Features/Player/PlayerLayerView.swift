import KSPlayer
import SwiftUI

#if canImport(UIKit)
import UIKit

/// Hosts KSPlayer’s render view (FFmpeg Metal or AVPlayerLayer under the hood).
struct KSPlayerSurface: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        Group {
            if let url = playback.playURL {
                KSVideoPlayer(
                    coordinator: playback.coordinator,
                    url: url,
                    options: playback.options
                )
                .background(Color.black)
            } else {
                Color.black
            }
        }
    }
}
#endif
