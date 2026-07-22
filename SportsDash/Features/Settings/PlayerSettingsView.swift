import SwiftUI

/// Video player settings — mirrors UHF: primary engine, fallback, buffer, KSPlayer toggles.
struct PlayerSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    private var fallbackBinding: Binding<Bool> {
        PrefsBinding.field(appModel, get: \.fallbackPlayers) { $0.fallbackPlayers = $1 }
    }

    private var adaptiveBinding: Binding<Bool> {
        PrefsBinding.field(appModel, get: \.adaptiveFrameRate) { $0.adaptiveFrameRate = $1 }
    }

    private var hardwareBinding: Binding<Bool> {
        PrefsBinding.field(appModel, get: \.hardwareDecode) { $0.hardwareDecode = $1 }
    }

    private var asyncBinding: Binding<Bool> {
        PrefsBinding.field(appModel, get: \.asynchronousDecompression) { $0.asynchronousDecompression = $1 }
    }

    private var aspectBinding: Binding<PlayerAspectMode> {
        PrefsBinding.field(appModel, get: \.aspect) { $0.aspect = $1 }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: fallbackBinding) {
                    Label("Fallback video players", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(SportsColors.gold)
                Text("If the primary engine fails, try the other one automatically.")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            } header: {
                Text("General settings")
            }

            Section {
                ForEach(PrimaryVideoPlayer.allCases) { player in
                    Button {
                        var p = appModel.playerPrefs
                        p.primaryPlayer = player
                        appModel.setPlayerPrefs(p)
                        PlaybackController.applyGlobal(p)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.label)
                                    .foregroundStyle(SportsColors.text)
                                Text(player.detail)
                                    .font(.caption)
                                    .foregroundStyle(SportsColors.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if appModel.playerPrefs.primaryPlayer == player {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SportsColors.gold)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(SportsColors.muted)
                            }
                        }
                    }
                }
            } header: {
                Text("Primary video player")
            } footer: {
                Text("KSPlayer is the default — most reliable for live IPTV. Native AVKit is optional for clean HLS only.")
                    .font(.caption2)
            }

            Section {
                HStack {
                    Button {
                        adjustBuffer(by: -1)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    Text("\(Int(appModel.playerPrefs.clampedBufferSeconds)) seconds")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(SportsColors.text)
                    Spacer()

                    Button {
                        adjustBuffer(by: 1)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                Text("How much media to buffer ahead. Higher values reduce stalls; lower values cut live delay.")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            } header: {
                Text("Buffer duration")
            }

            Section {
                Toggle(isOn: adaptiveBinding) {
                    Label("Adaptive frame rate", systemImage: "gauge.with.dots.needle.33percent")
                }
                .tint(SportsColors.gold)
                Toggle(isOn: hardwareBinding) {
                    Label("Hardware decode", systemImage: "cpu")
                }
                .tint(SportsColors.gold)
                Toggle(isOn: asyncBinding) {
                    Label("Asynchronous decompression", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(SportsColors.gold)
                Text("Hardware decode is recommended. Async decompression can help some streams but may hurt others.")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            } header: {
                Text("KSPlayer (Metal)")
            }

            Section {
                Picker("Aspect ratio", selection: aspectBinding) {
                    ForEach(PlayerAspectMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text("You can also cycle aspect from the player toolbar.")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            } header: {
                Text("Display")
            }
        }
        .scrollContentBackground(.hidden)
        .background(SportsColors.voidBlack)
        .navigationTitle("Video player")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: appModel.playerPrefs) { _, newPrefs in
            PlaybackController.applyGlobal(newPrefs)
        }
    }

    private func adjustBuffer(by delta: Double) {
        var p = appModel.playerPrefs
        p.bufferSeconds = min(15, max(1, p.clampedBufferSeconds + delta))
        appModel.setPlayerPrefs(p)
        PlaybackController.applyGlobal(p)
    }
}
