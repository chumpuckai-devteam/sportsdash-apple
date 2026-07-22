import SwiftUI

/// Video player settings — Auto / VLC / AVKit (Path A).
struct PlayerSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    private var fallbackBinding: Binding<Bool> {
        PrefsBinding.field(appModel, get: \.fallbackPlayers) { $0.fallbackPlayers = $1 }
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
                Text("If the primary engine fails, try the other one automatically (VLC ↔ AVKit).")
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
                Text("Path A: VLC (libVLC, LGPL) handles hard IPTV/TS. AVKit handles clean HLS and system routes. KSPlayer/FFmpegKit removed.")
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
                Text("Network caching hint for VLC (ms = seconds × 1000). Higher values reduce stalls; lower values cut live delay.")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            } header: {
                Text("Buffer duration")
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
