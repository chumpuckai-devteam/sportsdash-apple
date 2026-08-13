import SwiftUI

/// Video player settings — primary engine (VLC/AV), fallback, buffer, decode.
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
                ForEach(PrimaryVideoPlayer.selectableCases) { player in
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
                Text("Auto detects MPEG-TS vs HLS on Apple: TS → VLC (libVLC, LGPL); HLS → AVPlayer. Android ships libVLC as its single engine. Enable Apple fallback to try the other engine once if the first fails. Video AirPlay works best on AV.")
                    .font(.caption2)
            }

            Section {
                HStack {
                    Button {
                        adjustBuffer(by: -1)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 36, height: 36)
                            .background(SportsColors.border.opacity(0.55), in: Circle())
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
                            .background(SportsColors.border.opacity(0.55), in: Circle())
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
                Text("Decode")
            }

        }
        .sportsHideScrollBackground()
        .background(SportsColors.voidBlack)
        .navigationTitle("Video player")
        .sportsNavTitleMode(large: false)
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
