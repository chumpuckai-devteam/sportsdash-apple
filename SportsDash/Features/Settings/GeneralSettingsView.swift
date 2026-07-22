import SwiftUI

/// General settings — playlist refresh, storage, user agent, live stream format, movie ratings keys.
struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var statusMessage: String?
    @State private var omdbKey: String = ""
    @State private var tmdbKey: String = ""
    @State private var omdbSaved = false
    @State private var tmdbSaved = false

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
                SecureField("OMDb API key", text: $omdbKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    let trimmed = omdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        KeychainStore.delete(account: MovieRatingsService.omdbKeyAccount)
                        omdbSaved = false
                        statusMessage = "OMDb key cleared."
                    } else {
                        KeychainStore.set(trimmed, account: MovieRatingsService.omdbKeyAccount)
                        omdbSaved = true
                        omdbKey = "" // do not keep secret in view state after save
                        statusMessage = "OMDb key saved to Keychain."
                    }
                } label: {
                    Label("Save OMDb key", systemImage: "key.fill")
                }

                SecureField("TMDB API key (optional fallback)", text: $tmdbKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    let trimmed = tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        KeychainStore.delete(account: MovieRatingsService.tmdbKeyAccount)
                        tmdbSaved = false
                        statusMessage = "TMDB key cleared."
                    } else {
                        KeychainStore.set(trimmed, account: MovieRatingsService.tmdbKeyAccount)
                        tmdbSaved = true
                        tmdbKey = "" // do not keep secret in view state after save
                        statusMessage = "TMDB key saved to Keychain."
                    }
                } label: {
                    Label("Save TMDB key", systemImage: "key.fill")
                }

                Text(
                    "Used for RT-style critic/audience scores on movie EPG titles. Keys stay in Keychain — never committed to git. OMDb is preferred (includes Rotten Tomatoes % when available). Free keys: omdbapi.com · themoviedb.org"
                        + (omdbSaved || tmdbSaved ? " · key on device." : "")
                )
                .font(.caption)
                .foregroundStyle(SportsColors.muted)
            } header: {
                Text("Movie ratings")
            }

            Section {
                Button {
                    Task {
                        await appModel.reloadEpg(force: true)
                        statusMessage = "EPG reloaded · \(appModel.epgLoadedCount) channels."
                    }
                } label: {
                    if appModel.isLoadingEpg {
                        HStack {
                            ProgressView()
                            Text("Reloading EPG \(appModel.epgLoadedCount)/\(max(appModel.channels.count, 1))…")
                        }
                    } else {
                        Label("Reload EPG", systemImage: "calendar.badge.clock")
                    }
                }
                .disabled(appModel.channels.isEmpty || appModel.isLoadingEpg)

                Button {
                    appModel.epgByChannel = [:]
                    appModel.epgLoadedCount = 0
                    appModel.lastEpgReload = nil
                    appModel.epgStatus = nil
                    StorageService.shared.clearEpgCache()
                    statusMessage = "EPG cache cleared (memory + disk)."
                } label: {
                    Label("Clear EPG data", systemImage: "book")
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
                Text("EPG & storage")
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
        .onAppear {
            omdbSaved = KeychainStore.get(account: MovieRatingsService.omdbKeyAccount) != nil
            tmdbSaved = KeychainStore.get(account: MovieRatingsService.tmdbKeyAccount) != nil
        }
    }
}
