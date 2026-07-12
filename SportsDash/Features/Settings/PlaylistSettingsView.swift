import SwiftUI

/// IPTV playlist credentials (Xtream / M3U) + separate playlist / EPG reload.
struct PlaylistSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var sourceType: IptvSourceType = .m3u
    @State private var m3uURL = ""
    @State private var host = ""
    @State private var user = ""
    @State private var password = ""
    @State private var statusMessage: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                if let cfg = appModel.iptvConfig, cfg.isConfigured {
                    Text("Configured · \(appModel.channels.count) channels")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                } else {
                    Text("Add a playlist to browse channels and match live games.")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }

                Picker("Type", selection: $sourceType) {
                    Text("M3U").tag(IptvSourceType.m3u)
                    Text("Xtream").tag(IptvSourceType.xtream)
                }
                .pickerStyle(.segmented)

                if sourceType == .m3u {
                    TextField("Playlist URL", text: $m3uURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                } else {
                    TextField("Server URL", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
            } header: {
                Text("Source")
            }

            Section {
                Button {
                    Task { await saveAndLoad() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Save & Load").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SportsColors.gold)
                .foregroundStyle(SportsColors.voidBlack)
                .disabled(isSaving)

                if appModel.iptvConfig != nil {
                    Button("Remove playlist", role: .destructive) {
                        appModel.clearIptvConfig()
                        m3uURL = ""; host = ""; user = ""; password = ""
                        statusMessage = "Cleared."
                    }
                }
            }

            Section {
                Button {
                    Task {
                        isSaving = true
                        defer { isSaving = false }
                        await appModel.reloadChannels()
                        if let err = appModel.channelsError {
                            statusMessage = err
                        } else {
                            statusMessage = "Playlist reloaded · \(appModel.channels.count) channels."
                        }
                    }
                } label: {
                    if appModel.isLoadingChannels {
                        HStack {
                            ProgressView()
                            Text("Reloading playlist…")
                        }
                    } else {
                        Label("Reload playlist", systemImage: "list.bullet.rectangle")
                    }
                }
                .disabled(appModel.iptvConfig == nil || appModel.isLoadingChannels)

                Button {
                    Task {
                        await appModel.reloadEpg(force: true)
                        if let err = appModel.epgError {
                            statusMessage = err
                        } else {
                            let withData = appModel.epgByChannel.values.filter { !$0.isEmpty }.count
                            statusMessage = "EPG reloaded · \(withData)/\(appModel.channels.count) channels have listings."
                        }
                    }
                } label: {
                    if appModel.isLoadingEpg {
                        HStack {
                            ProgressView()
                            Text(epgProgressLabel)
                        }
                    } else {
                        Label("Reload EPG", systemImage: "calendar")
                    }
                }
                .disabled(appModel.channels.isEmpty || appModel.isLoadingEpg)

                if let updated = appModel.lastEpgReload {
                    Text("Last EPG update \(updated.formatted(date: .omitted, time: .shortened)) · \(appModel.epgLoadedCount) channels cached")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }
            } header: {
                Text("Reload")
            } footer: {
                Text("Reload playlist refreshes channels only. Reload EPG downloads the guide to a temp file on disk, then parses it in the background so Settings stays responsive. A disk cache makes the next launch nearly instant.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(SportsColors.voidBlack)
        .navigationTitle("Playlist")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: hydrate)
    }

    private var epgProgressLabel: String {
        let total = max(appModel.channels.count, 1)
        return "EPG \(appModel.epgLoadedCount)/\(total)…"
    }

    private func hydrate() {
        guard let cfg = appModel.iptvConfig else { return }
        sourceType = cfg.type
        m3uURL = cfg.m3uURL ?? ""
        host = cfg.xtreamHost ?? ""
        user = cfg.xtreamUsername ?? ""
        password = cfg.xtreamPassword ?? ""
    }

    private func saveAndLoad() async {
        isSaving = true
        defer { isSaving = false }
        let config = IptvConfig(
            type: sourceType,
            m3uURL: m3uURL,
            xtreamHost: host,
            xtreamUsername: user,
            xtreamPassword: password,
            displayName: sourceType == .m3u ? "M3U" : "Xtream"
        )
        guard config.isConfigured else {
            statusMessage = "Fill in required fields."
            return
        }
        do {
            try await appModel.saveIptvConfig(config)
            statusMessage = "Loaded \(appModel.channels.count) channels. EPG loading in background…"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
