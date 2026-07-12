import SwiftUI

/// Root settings hub — UHF-style sections (Playlist + Advanced pages).
struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("Playlist") {
                    NavigationLink {
                        PlaylistSettingsView()
                    } label: {
                        settingsRow(
                            icon: "list.bullet.rectangle",
                            tint: SportsColors.gold,
                            title: playlistTitle,
                            subtitle: playlistSubtitle
                        )
                    }
                    .listRowBackground(SportsColors.panel)

                    if appModel.isLoadingEpg {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small).tint(SportsColors.gold)
                            Text(appModel.epgStatus ?? "Downloading EPG…")
                                .font(.caption)
                                .foregroundStyle(SportsColors.muted)
                        }
                        .listRowBackground(SportsColors.panel)
                    } else if let status = appModel.epgStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .listRowBackground(SportsColors.panel)
                    } else if appModel.epgLoadedCount > 0 {
                        Text("EPG ready · \(appModel.epgByChannel.values.filter { !$0.isEmpty }.count) channels with listings")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .listRowBackground(SportsColors.panel)
                    }
                }

                Section("Advanced") {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        settingsRow(icon: "gearshape", tint: .gray, title: "General")
                    }
                    .listRowBackground(SportsColors.panel)

                    NavigationLink {
                        UISettingsView()
                    } label: {
                        settingsRow(icon: "slider.horizontal.3", tint: .blue, title: "User interface")
                    }
                    .listRowBackground(SportsColors.panel)

                    NavigationLink {
                        PlayerSettingsView()
                    } label: {
                        settingsRow(icon: "play.rectangle", tint: .green, title: "Video player")
                    }
                    .listRowBackground(SportsColors.panel)

                    NavigationLink {
                        ScoresSettingsView()
                    } label: {
                        settingsRow(icon: "sportscourt", tint: SportsColors.gold, title: "Scores & leagues")
                    }
                    .listRowBackground(SportsColors.panel)
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SportsDash").font(.headline).foregroundStyle(SportsColors.text)
                        Text("Native SwiftUI sports IPTV for iOS & Apple TV.")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                        LabeledContent("Version", value: "1.0.0")
                        LabeledContent("Channels", value: "\(appModel.channels.count)")
                        LabeledContent("Live games", value: "\(appModel.games.filter(\.isLive).count)")
                    }
                    .listRowBackground(SportsColors.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SportsColors.voidBlack)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }

    private var playlistTitle: String {
        appModel.iptvConfig?.displayName
            ?? (appModel.iptvConfig?.type == .xtream ? "Xtream" : "Playlist")
    }

    private var playlistSubtitle: String {
        if appModel.channels.isEmpty {
            return appModel.iptvConfig == nil ? "Not configured" : "No channels loaded"
        }
        return "\(appModel.channels.count) channels"
    }

    private func settingsRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String? = nil
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SportsColors.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Shared prefs helpers

extension View {
    /// Apply a mutation to `AppModel.playerPrefs` and persist.
    func updatePrefs(_ appModel: AppModel, _ mutate: (inout PlayerPrefs) -> Void) {
        var p = appModel.playerPrefs
        mutate(&p)
        appModel.setPlayerPrefs(p)
    }
}

/// Binding helper for nested PlayerPrefs fields.
@MainActor
enum PrefsBinding {
    static func field<T>(
        _ appModel: AppModel,
        get: @escaping (PlayerPrefs) -> T,
        set: @escaping (inout PlayerPrefs, T) -> Void
    ) -> Binding<T> {
        Binding(
            get: { get(appModel.playerPrefs) },
            set: { newValue in
                var p = appModel.playerPrefs
                set(&p, newValue)
                appModel.setPlayerPrefs(p)
            }
        )
    }
}
