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
                            ProgressView()
                        } else {
                            Text("Save & Load")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SportsColors.gold)
                    .foregroundStyle(SportsColors.voidBlack)
                    .disabled(isSaving)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                    }
                }

                Section("About") {
                    Text("SportsDash")
                        .font(.headline)
                    Text("Native SwiftUI app for iOS and Apple TV. Flutter prototype remains at chumpuckai-devteam/sportsdash for reference.")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Channels", value: "\(appModel.channels.count)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SportsColors.voidBlack)
            .navigationTitle("Settings")
        }
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
            let channels = try await appModel.iptvService.loadChannels(config: config)
            await MainActor.run {
                appModel.channels = channels
                statusMessage = "Loaded \(channels.count) channels."
            }
            // TODO: Keychain persistence
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
