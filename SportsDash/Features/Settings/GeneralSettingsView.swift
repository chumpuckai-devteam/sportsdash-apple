import SwiftUI

/// General settings — playlist refresh, storage, user agent, live stream format.
struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var statusMessage: String?

    private var refreshBinding: Binding<PlaylistRefreshInterval> {
        PrefsBinding.field(appModel, get: \.playlistRefresh) { $0.playlistRefresh = $1 }
    }

    private var formatBinding: Binding<LiveStreamFormat> {
        PrefsBinding.field(appModel, get: \.preferredLiveFormat) { $0.preferredLiveFormat = $1 }
    }

    private var userAgentBinding: Binding<String> {
        PrefsBinding.field(appModel, get: \.userAgent) { $0.userAgent = $1 }
    }

    var body: some View {
        Form {
            Section {
                Picker("Update playlists", selection: refreshBinding) {
                    ForEach(PlaylistRefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                Text("Automatically reloads your IPTV playlist on this schedule while the app is open.")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            } header: {
                Text("Update playlists")
            }

            Section {
                Button {
                    appModel.epgByChannel = [:]
                    statusMessage = "EPG cache cleared."
                } label: {
                    Label("EPG data", systemImage: "book")
                }
                Button {
                    statusMessage = "Temporary playback state cleared."
                } label: {
                    Label("Temporal files", systemImage: "folder")
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }
            } header: {
                Text("Clean up storage")
            }

            Section {
                TextField("User-Agent", text: userAgentBinding, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...4)
                Text("Sent with stream requests (FFmpeg & AVPlayer headers). Restart playback for changes to apply. Example: VLC/3.0.18 LibVLC/3.0.18")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            } header: {
                Text("User Agent")
            }

            Section {
                ForEach(LiveStreamFormat.allCases) { format in
                    Button {
                        var p = appModel.playerPrefs
                        p.preferredLiveFormat = format
                        appModel.setPlayerPrefs(p)
                    } label: {
                        HStack {
                            Text(format.label)
                                .foregroundStyle(SportsColors.text)
                            Spacer()
                            if appModel.playerPrefs.preferredLiveFormat == format {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SportsColors.gold)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(SportsColors.muted)
                            }
                        }
                    }
                }
                Text("When both containers exist, the preferred format is tried first.")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            } header: {
                Text("Preferred live stream format")
            }
        }
        .scrollContentBackground(.hidden)
        .background(SportsColors.voidBlack)
        .navigationTitle("General")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
