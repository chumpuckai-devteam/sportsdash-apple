import SwiftUI
import AVKit

/// Minimal AVPlayer shell — full IPTV player (KSPlayer/LIVE/aspect) lands in M3.
struct PlayerPlaceholderView: View {
    let channel: IptvChannel
    let game: Game?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = URL(string: channel.url) {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            } else {
                Text("Invalid stream URL")
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle(channel.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
