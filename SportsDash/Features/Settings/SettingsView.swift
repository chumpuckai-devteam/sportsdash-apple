import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var sourceType: IptvSourceType = .m3u
    @State private var m3uURL = ""
    @State private var host = ""
    @State private var user = ""
    @State private var password = ""
    @State private var statusMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("IPTV source") {
                    if let cfg = appModel.iptvConfig, cfg.isConfigured {
                        Text("Configured · \(appModel.channels.count) channels")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                    } else {
                        Text("Not configured")
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
                        Button("Clear IPTV", role: .destructive) {
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

                Section("Player") {
                    Picker("Video engine", selection: engineBinding) {
                        ForEach(PlayerEngine.allCases) { engine in
                            Text(engine.label).tag(engine)
                        }
                    }
                    Text(appModel.playerPrefs.engine.detail)
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)

                    Toggle("Hardware decode", isOn: hardwareDecodeBinding)
                        .tint(SportsColors.gold)

                    Picker("Aspect ratio", selection: aspectBinding) {
                        ForEach(PlayerAspectMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Text("FFmpeg (KSPlayer) plays more IPTV formats than native AVPlayer. LIVE rejoins the live edge; aspect cycles from the player toolbar.")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }

                Section("Leagues on Scores") {
                    ForEach(SportLeague.allCases) { league in
                        Toggle(isOn: leagueBinding(league)) {
                            Text("\(league.emoji) \(league.label)")
                        }
                        .tint(SportsColors.gold)
                    }
                }

                Section("About") {
                    Text("SportsDash").font(.headline)
                    Text("Native SwiftUI for iOS & Apple TV. Flutter reference: chumpuckai-devteam/sportsdash.")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Channels", value: "\(appModel.channels.count)")
                    LabeledContent("Games", value: "\(appModel.games.count)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SportsColors.voidBlack)
            .navigationTitle("Settings")
            .onAppear(perform: hydrate)
        }
    }

    private var engineBinding: Binding<PlayerEngine> {
        Binding(
            get: { appModel.playerPrefs.engine },
            set: { v in
                var p = appModel.playerPrefs
                p.engine = v
                appModel.setPlayerPrefs(p)
            }
        )
    }

    private var hardwareDecodeBinding: Binding<Bool> {
        Binding(
            get: { appModel.playerPrefs.hardwareDecode },
            set: { v in
                var p = appModel.playerPrefs
                p.hardwareDecode = v
                appModel.setPlayerPrefs(p)
            }
        )
    }

    private var aspectBinding: Binding<PlayerAspectMode> {
        Binding(
            get: { appModel.playerPrefs.aspect },
            set: { v in
                var p = appModel.playerPrefs
                p.aspect = v
                appModel.setPlayerPrefs(p)
            }
        )
    }

    private func leagueBinding(_ league: SportLeague) -> Binding<Bool> {
        Binding(
            get: { appModel.selectedLeagues.contains(league) },
            set: { on in
                var list = appModel.selectedLeagues
                if on {
                    if !list.contains(league) { list.append(league) }
                } else {
                    list.removeAll { $0 == league }
                }
                appModel.setSelectedLeagues(list)
            }
        )
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
