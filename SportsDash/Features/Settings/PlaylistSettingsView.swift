import SwiftUI

/// IPTV playlist credentials (Xtream / M3U).
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

                Button {
                    Task {
                        isSaving = true
                        defer { isSaving = false }
                        do {
                            try await appModel.reloadChannels()
                            statusMessage = "Reloaded \(appModel.channels.count) channels."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Reload playlist", systemImage: "arrow.clockwise")
                }
                .disabled(appModel.iptvConfig == nil || isSaving)

                if appModel.iptvConfig != nil {
                    Button("Remove playlist", role: .destructive) {
                        appModel.clearIptvConfig()
                        m3uURL = ""; host = ""; user = ""; password = ""
                        statusMessage = "Cleared."
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }
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
            statusMessage = "Loaded \(appModel.channels.count) channels."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
