import SwiftUI

/// General settings — playlist refresh, storage, user agent, live stream format, movie ratings keys.
struct GeneralSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var statusMessage: String?
    @State private var omdbKey: String = ""
    @State private var tmdbKey: String = ""
    @State private var omdbSaved = false
    @State private var tmdbSaved = false
    @State private var omdbMask: String?
    @State private var tmdbMask: String?
    @State private var isTesting = false

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
                keyStatusRow(title: "OMDb", saved: omdbSaved, mask: omdbMask)
                SecureField("Paste OMDb API key", text: $omdbKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    #if os(iOS)
                    .keyboardType(.asciiCapable)
                    #endif
                    .onSubmit { saveOmdb() }
                Button(action: saveOmdb) {
                    Label(omdbSaved ? "Update OMDb key" : "Save OMDb key", systemImage: "key.fill")
                }

                keyStatusRow(title: "TMDB", saved: tmdbSaved, mask: tmdbMask)
                SecureField("Paste TMDB API key (optional)", text: $tmdbKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    #if os(iOS)
                    .keyboardType(.asciiCapable)
                    #endif
                    .onSubmit { saveTmdb() }
                Button(action: saveTmdb) {
                    Label(tmdbSaved ? "Update TMDB key" : "Save TMDB key", systemImage: "key.fill")
                }

                Text(
                    "Keys power Critic/Audience scores on movie guide rows (e.g. UK | Movies). Free OMDb key: omdbapi.com — tap Save after pasting. Field clears on success; status above stays green."
                )
                .font(.caption)
                .foregroundStyle(SportsColors.muted)

                Button {
                    Task { await runTest() }
                } label: {
                    if isTesting {
                        HStack {
                            ProgressView()
                            Text("Testing lookup…")
                        }
                    } else {
                        Label("Test ratings (Inception)", systemImage: "wand.and.stars")
                    }
                }
                .disabled(isTesting)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(statusMessage))
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .onAppear { refreshKeyStatus() }
    }

    // MARK: - Keys

    private func refreshKeyStatus() {
        omdbSaved = KeychainStore.hasValue(account: MovieRatingsService.omdbKeyAccount)
        tmdbSaved = KeychainStore.hasValue(account: MovieRatingsService.tmdbKeyAccount)
        omdbMask = KeychainStore.maskedPreview(account: MovieRatingsService.omdbKeyAccount)
        tmdbMask = KeychainStore.maskedPreview(account: MovieRatingsService.tmdbKeyAccount)
    }

    private func saveOmdb() {
        let trimmed = omdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: MovieRatingsService.omdbKeyAccount)
            omdbKey = ""
            refreshKeyStatus()
            statusMessage = "OMDb key cleared."
            return
        }
        let ok = KeychainStore.set(trimmed, account: MovieRatingsService.omdbKeyAccount)
        omdbKey = ""
        refreshKeyStatus()
        if ok, omdbSaved {
            statusMessage = "OMDb key saved · on device \(omdbMask ?? "••••"). Tap Test ratings next."
        } else {
            statusMessage = "OMDb save failed — try again."
        }
    }

    private func saveTmdb() {
        let trimmed = tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: MovieRatingsService.tmdbKeyAccount)
            tmdbKey = ""
            refreshKeyStatus()
            statusMessage = "TMDB key cleared."
            return
        }
        let ok = KeychainStore.set(trimmed, account: MovieRatingsService.tmdbKeyAccount)
        tmdbKey = ""
        refreshKeyStatus()
        if ok, tmdbSaved {
            statusMessage = "TMDB key saved · on device \(tmdbMask ?? "••••")."
        } else {
            statusMessage = "TMDB save failed — try again."
        }
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        refreshKeyStatus()
        let result = await MovieRatingsService.shared.testLookup(title: "Inception")
        statusMessage = result
    }

    @ViewBuilder
    private func keyStatusRow(title: String, saved: Bool, mask: String?) -> some View {
        HStack {
            Image(systemName: saved ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(saved ? SportsColors.live : SportsColors.danger)
            Text(saved ? "\(title) key on device" : "\(title) key not saved")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SportsColors.text)
            Spacer()
            if let mask {
                Text(mask)
                    .font(.caption.monospaced())
                    .foregroundStyle(SportsColors.muted)
            }
        }
        .listRowBackground(SportsColors.panel)
    }

    private func statusColor(_ message: String) -> Color {
        let m = message.lowercased()
        if m.contains("ok") || m.contains("saved") { return SportsColors.live }
        if m.contains("fail") || m.contains("no api") || m.contains("no score") { return SportsColors.danger }
        return SportsColors.muted
    }
}
