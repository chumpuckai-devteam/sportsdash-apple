import SwiftUI

/// Root settings hub — grouped list with modern section chrome.
struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            List {
                if SetupChecklist.isIncomplete(appModel) {
                    Section {
                        SetupChecklistCard()
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Setup")
                    }
                }

                Section {
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

                    if let account = appModel.xtreamAccount {
                        HStack {
                            Text("Status")
                                .foregroundStyle(SportsColors.muted)
                            Spacer()
                            Text(account.status ?? "—")
                                .fontWeight(.semibold)
                                .foregroundStyle(account.isActive ? SportsColors.live : SportsColors.danger)
                        }
                        .listRowBackground(SportsColors.panel)

                        HStack {
                            Text("Expires")
                                .foregroundStyle(SportsColors.muted)
                            Spacer()
                            Text(account.expDateLabel)
                                .foregroundStyle(SportsColors.text)
                        }
                        .listRowBackground(SportsColors.panel)

                        HStack {
                            Text("Connections")
                                .foregroundStyle(SportsColors.muted)
                            Spacer()
                            Text(account.connectionsLabel)
                                .foregroundStyle(SportsColors.text)
                        }
                        .listRowBackground(SportsColors.panel)
                    }

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
                } header: {
                    Text("Playlists")
                }

                Section {
                    #if os(iOS)
                    Toggle(isOn: PrefsBinding.field(appModel, get: { $0.notificationsEnabled }, set: { $0.notificationsEnabled = $1 })) {
                        settingsRow(
                            icon: "bell.fill",
                            tint: SportsColors.gold,
                            title: "Game alerts",
                            subtitle: "Favorite teams only · start + goals"
                        )
                    }
                    .listRowBackground(SportsColors.panel)
                    .tint(SportsColors.gold)
                    .onChange(of: appModel.playerPrefs.notificationsEnabled) { _, enabled in
                        Task {
                            if enabled {
                                let ok = await GameNotificationService.shared.requestAuthorizationIfNeeded()
                                if !ok {
                                    var p = appModel.playerPrefs
                                    p.notificationsEnabled = false
                                    appModel.setPlayerPrefs(p)
                                }
                            } else {
                                // Drop scheduled starts immediately (process also clears on next poll).
                                await GameNotificationService.shared.process(
                                    games: appModel.games,
                                    favoriteTeamIds: appModel.favoriteTeamIds,
                                    notifyStarts: false,
                                    notifyGoals: false,
                                    masterEnabled: false
                                )
                            }
                        }
                    }

                    if appModel.playerPrefs.notificationsEnabled {
                        Toggle(
                            "Game starting soon",
                            isOn: PrefsBinding.field(appModel, get: { $0.notifyGameStarts }, set: { $0.notifyGameStarts = $1 })
                        )
                        .listRowBackground(SportsColors.panel)
                        .tint(SportsColors.gold)
                        Toggle(
                            "Goals / score changes",
                            isOn: PrefsBinding.field(appModel, get: { $0.notifyGoals }, set: { $0.notifyGoals = $1 })
                        )
                        .listRowBackground(SportsColors.panel)
                        .tint(SportsColors.gold)
                    }

                                        #endif

                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        settingsRow(icon: "gearshape", tint: SportsColors.muted, title: "General")
                    }
                    .listRowBackground(SportsColors.panel)

                    NavigationLink {
                        UISettingsView()
                    } label: {
                        settingsRow(icon: "slider.horizontal.3", tint: SportsColors.goldDim, title: "User interface")
                    }
                    .listRowBackground(SportsColors.panel)

                    NavigationLink {
                        PlayerSettingsView()
                    } label: {
                        settingsRow(icon: "play.rectangle", tint: SportsColors.live, title: "Video player")
                    }
                    .listRowBackground(SportsColors.panel)

                    NavigationLink {
                        ScoresSettingsView()
                    } label: {
                        settingsRow(icon: "sportscourt", tint: SportsColors.gold, title: "Scores & leagues")
                    }
                    .listRowBackground(SportsColors.panel)
                } header: {
                    Text("App")
                } footer: {
                    Text("Game alerts are local only (no push server), favorite teams only, and off by default. Not a Sprint 1 release requirement.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SportsDash")
                                    .font(.headline)
                                    .foregroundStyle(SportsColors.text)
                                Text("Native SwiftUI · iOS & Apple TV")
                                    .font(.caption)
                                    .foregroundStyle(SportsColors.muted)
                            }
                        }
                        Text("Playback: VLC (libVLC) hard engine + AVPlayer for clean HLS. LGPL — see About. Movie scores via OMDb/TMDB when you add keys in General.")
                            .font(.caption2)
                            .foregroundStyle(SportsColors.muted)
                        Text("This product uses libVLC / VLCKit (© VideoLAN), licensed under LGPLv2.1+. https://www.videolan.org/")
                            .font(.caption2)
                            .foregroundStyle(SportsColors.muted)
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .font(.caption2)
                            .foregroundStyle(SportsColors.muted)
                        LabeledContent("Version", value: "1.0.0")
                        LabeledContent("Channels", value: "\(appModel.channels.count)")
                        LabeledContent("Live games", value: "\(appModel.games.filter(\.isLive).count)")
                    }
                    .listRowBackground(SportsColors.panel)
                } header: {
                    Text("About")
                }
            }
            .sportsHideScrollBackground()
            .sportsScreenBackground()
            .navigationTitle("Settings")
            .sportsNavTitleMode(large: true)
            .sportsInsetGroupedList()
        }
    }

    private var playlistTitle: String {
        if appModel.playlists.isEmpty { return "Playlists" }
        let active = appModel.activePlaylist?.name ?? "Playlist"
        if appModel.playlists.count > 1 {
            return "\(active) · \(appModel.playlists.count) sources"
        }
        return active
    }

    private var playlistSubtitle: String {
        if appModel.playlists.isEmpty {
            return "Add Xtream or M3U"
        }
        if appModel.channels.isEmpty {
            return "No channels loaded"
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
