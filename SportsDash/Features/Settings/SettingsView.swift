import SwiftUI

/// Root settings hub — grouped list with modern section chrome.
struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var epg: EpgStore

    var body: some View {
        NavigationStack {
            #if os(iOS)
            jumbotronHub
            #else
            jumbotronTvHub
            #if false
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

                    if epg.isLoadingEpg {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small).tint(SportsColors.gold)
                            Text(epg.epgStatus ?? "Downloading EPG…")
                                .font(.caption)
                                .foregroundStyle(SportsColors.muted)
                        }
                        .listRowBackground(SportsColors.panel)
                    } else if let status = epg.epgStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .listRowBackground(SportsColors.panel)
                    } else if epg.epgLoadedCount > 0 {
                        Text("EPG ready · \(epg.epgLoadedCount) channels with listings")
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
                                } else {
                                    appModel.scheduleScoresBackgroundRefresh()
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
                                appModel.scheduleScoresBackgroundRefresh()
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
                        .onChange(of: appModel.playerPrefs.notifyGameStarts) { _, _ in
                            appModel.scheduleScoresBackgroundRefresh()
                        }
                        Toggle(
                            "Goals / score changes",
                            isOn: PrefsBinding.field(appModel, get: { $0.notifyGoals }, set: { $0.notifyGoals = $1 })
                        )
                        .listRowBackground(SportsColors.panel)
                        .tint(SportsColors.gold)
                        .onChange(of: appModel.playerPrefs.notifyGoals) { _, _ in
                            appModel.scheduleScoresBackgroundRefresh()
                        }
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
                    Text("Game alerts are local only (no push server), favorite teams only, off by default. Score changes require the app to refresh scores (open app or best-effort BG refresh on iOS). Start-soon uses iOS calendar schedule and can fire when suspended.")
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
            #endif
            #endif
        }
    }

    #if os(tvOS)
    private var jumbotronTvHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                JumbotronScreenTitle(first: "CONTROL ", gold: "ROOM", size: 64)

                SetupChecklistCard()

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        tvSectionLabel("SOURCE", tick: SportsColors.live)
                        VStack(spacing: 0) {
                            NavigationLink { PlaylistSettingsView() } label: {
                                tvSettingsRow(
                                    icon: "list.bullet.rectangle",
                                    title: {
                                        if appModel.playlists.isEmpty { return "XTREAM · ADD SOURCE" }
                                        return "XTREAM · \((appModel.activePlaylist?.name ?? "PLAYLIST").uppercased())"
                                    }(),
                                    value: "\(appModel.channels.count) CH ›"
                                )
                            }
                            .buttonStyle(.plain)
                            .sportsTVFocusClean()
                            if let account = appModel.xtreamAccount {
                                tvMetaRow("STATUS", account.status?.uppercased() ?? "—",
                                          color: account.isActive ? SportsColors.live : SportsColors.danger)
                                tvMetaRow("EXPIRES", account.expDateLabel.uppercased(), color: SportsColors.gold)
                                tvMetaRow("CONNECTIONS", account.connectionsLabel, color: SportsColors.gold)
                            } else if epg.isLoadingEpg {
                                tvMetaRow("EPG", epg.epgStatus?.uppercased() ?? "…", color: SportsColors.muted)
                            }
                        }
                        .jumbotronPanel(border: SportsColors.border)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        tvSectionLabel("SYSTEM", tick: SportsColors.gold)
                        VStack(spacing: 0) {
                            NavigationLink { GeneralSettingsView() } label: {
                                tvSettingsRow(icon: "gearshape", title: "GENERAL", value: "›")
                            }
                            .buttonStyle(.plain)
                            .sportsTVFocusClean()
                            NavigationLink { UISettingsView() } label: {
                                tvSettingsRow(
                                    icon: "line.3.horizontal",
                                    title: "USER INTERFACE",
                                    value: appModel.playerPrefs.cleanUpNames ? "CLEAN NAMES ›" : "›"
                                )
                            }
                            .buttonStyle(.plain)
                            .sportsTVFocusClean()
                            NavigationLink { PlayerSettingsView() } label: {
                                tvSettingsRow(icon: "play.fill", title: "VIDEO PLAYER", value: "VLC ›")
                            }
                            .buttonStyle(.plain)
                            .sportsTVFocusClean()
                            NavigationLink { ScoresSettingsView() } label: {
                                tvSettingsRow(
                                    icon: "sportscourt",
                                    title: "LEAGUES ON SCORES",
                                    value: "\((appModel.selectedLeagues.isEmpty ? SportLeague.defaults.count : appModel.selectedLeagues.count)) SELECTED ›"
                                )
                            }
                            .buttonStyle(.plain)
                            .sportsTVFocusClean()
                        }
                        .jumbotronPanel()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, SportsTVMetrics.screenInset)
            .padding(.bottom, 40)
        }
        .sportsScreenBackground()
        .navigationTitle("")
        .focusSection()
    }

    private func tvSectionLabel(_ title: String, tick: Color) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(tick).frame(width: 6, height: 22)
            Text(title)
                .font(JumbotronFonts.display(24))
                .foregroundStyle(SportsColors.muted)
                .tracking(2)
        }
    }

    private func tvSettingsRow(icon: String, title: String, value: String) -> some View {
        SportsTVFocused { focused in
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                    .frame(width: 36, height: 36)
                    .overlay { Rectangle().stroke(focused ? SportsColors.voidBlack : SportsColors.border, lineWidth: SportsTVMetrics.hairline) }
                Text(title)
                    .font(JumbotronFonts.display(30))
                    .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .font(JumbotronFonts.body(16))
                    .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.7) : SportsColors.muted)
            }
            .padding(.horizontal, 20)
            .frame(height: SportsTVMetrics.settingsRowHeight)
            .background(focused ? SportsColors.gold : Color.clear)
            .overlay(alignment: .top) { Rectangle().fill(SportsColors.gridDot).frame(height: SportsTVMetrics.hairline) }
            .shadow(color: focused ? SportsColors.ledGlow : .clear, radius: focused ? SportsTVMetrics.focusGlowRadius : 0)
            .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
            .animation(SportsTVFocusMotion.animation, value: focused)
        }
        .frame(minHeight: SportsTVMetrics.minFocusSize)
    }

    private func tvMetaRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(JumbotronFonts.body(16))
                .foregroundStyle(SportsColors.muted)
            Spacer()
            JumbotronLED(text: value, size: 16, color: color, glow: color == SportsColors.live || color == SportsColors.gold)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .overlay(alignment: .top) { Rectangle().fill(SportsColors.gridDot).frame(height: SportsTVMetrics.hairline) }
    }
    #endif

    #if os(iOS)
    private var jumbotronHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                JumbotronScreenTitle(first: "CONTROL ", gold: "ROOM")
                    .padding(.top, 4)

                SetupChecklistCard()

                sectionLabel("SOURCE", tick: SportsColors.live)
                VStack(spacing: 0) {
                    NavigationLink {
                        PlaylistSettingsView()
                    } label: {
                        settingsHubRow(
                            icon: "list.bullet.rectangle",
                            title: playlistHubTitle,
                            value: playlistHubValue
                        )
                    }
                    .buttonStyle(.plain)
                    if let account = appModel.xtreamAccount {
                        hubMetaRow("STATUS", account.status?.uppercased() ?? "—",
                                   color: account.isActive ? SportsColors.live : SportsColors.danger,
                                   glow: account.isActive)
                        hubMetaRow("EXPIRES", account.expDateLabel.uppercased(), color: SportsColors.gold, glow: true)
                        hubMetaRow("CONNECTIONS", account.connectionsLabel, color: SportsColors.gold, glow: true)
                    } else if epg.isLoadingEpg {
                        hubMetaRow("EPG", epg.epgStatus?.uppercased() ?? "…", color: SportsColors.muted, glow: false)
                    }
                }
                .jumbotronPanel()

                sectionLabel("ALERTS", tick: SportsColors.danger)
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        settingsIcon("bell.fill", stroke: SportsColors.danger)
                        Text("GAME ALERTS")
                            .font(JumbotronFonts.display(22))
                            .jumbotronDisplayTracking(22)
                            .foregroundStyle(SportsColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(alertsCaption)
                            .font(JumbotronFonts.body(11))
                            .foregroundStyle(SportsColors.muted)
                        JumbotronToggle(
                            isOn: PrefsBinding.field(
                                appModel,
                                get: { $0.notificationsEnabled },
                                set: { $0.notificationsEnabled = $1 }
                            )
                        )
                        .onChange(of: appModel.playerPrefs.notificationsEnabled) { _, enabled in
                            Task { await handleAlertsToggle(enabled) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: SportsMetrics.settingsRowHeight)
                    .frame(minHeight: 44)
                    if appModel.playerPrefs.notificationsEnabled {
                        hubToggleRow("GAME STARTING SOON", PrefsBinding.field(appModel, get: { $0.notifyGameStarts }, set: { $0.notifyGameStarts = $1 }))
                        hubToggleRow("GOALS / SCORE CHANGES", PrefsBinding.field(appModel, get: { $0.notifyGoals }, set: { $0.notifyGoals = $1 }))
                    }
                }
                .jumbotronPanel()

                sectionLabel("SYSTEM", tick: SportsColors.gold)
                VStack(spacing: 0) {
                    NavigationLink { GeneralSettingsView() } label: {
                        settingsHubRow(icon: "gearshape", title: "GENERAL", value: "›")
                    }
                    .buttonStyle(.plain)
                    NavigationLink { UISettingsView() } label: {
                        settingsHubRow(icon: "line.3.horizontal", title: "USER INTERFACE", value: appModel.playerPrefs.cleanUpNames ? "CLEAN NAMES ›" : "›")
                    }
                    .buttonStyle(.plain)
                    NavigationLink { PlayerSettingsView() } label: {
                        settingsHubRow(icon: "play.fill", title: "VIDEO PLAYER", value: playerValue, iconFill: SportsColors.live)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { ScoresSettingsView() } label: {
                        settingsHubRow(icon: "sportscourt", title: "LEAGUES ON SCORES", value: leaguesValue)
                    }
                    .buttonStyle(.plain)
                }
                .jumbotronPanel()
            }
            .padding(.horizontal, SportsMetrics.screenInset)
            .padding(.bottom, 28)
        }
        .sportsHideScrollBackground()
        .sportsScreenBackground()
        .navigationTitle("")
        .sportsNavTitleMode(large: false)
        .toolbarBackground(.hidden, for: .navigationBar)
        .jumbotronAXCap()
    }

    private var playlistHubTitle: String {
        if appModel.playlists.isEmpty { return "XTREAM · ADD SOURCE" }
        let name = appModel.activePlaylist?.name.uppercased() ?? "PLAYLIST"
        return "XTREAM · \(name)"
    }

    private var playlistHubValue: String {
        if appModel.channels.isEmpty { return "0 CH ›" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return "\(f.string(from: NSNumber(value: appModel.channels.count)) ?? "\(appModel.channels.count)") CH ›"
    }

    private var alertsCaption: String {
        var bits: [String] = []
        if appModel.playerPrefs.notifyGameStarts { bits.append("STARTS") }
        if appModel.playerPrefs.notifyGoals { bits.append("GOALS") }
        return bits.isEmpty ? "OFF" : bits.joined(separator: " + ")
    }

    private var playerValue: String { "AUTO · VLC / AV ›" }

    private var leaguesValue: String {
        let n = appModel.selectedLeagues.isEmpty ? SportLeague.defaults.count : appModel.selectedLeagues.count
        return "\(n) SELECTED ›"
    }

    private func sectionLabel(_ title: String, tick: Color) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(tick).frame(width: 4, height: 14)
            Text(title)
                .font(JumbotronFonts.display(16))
                .foregroundStyle(SportsColors.muted)
                .tracking(2)
        }
        .padding(.top, 4)
        .accessibilityAddTraits(.isHeader)
    }

    private func settingsHubRow(icon: String, title: String, value: String, iconFill: Color? = nil) -> some View {
        HStack(spacing: 10) {
            settingsIcon(icon, stroke: iconFill ?? SportsColors.gold, fill: iconFill)
            Text(title)
                .font(JumbotronFonts.display(22))
                .jumbotronDisplayTracking(22)
                .foregroundStyle(SportsColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(JumbotronFonts.body(11))
                .foregroundStyle(SportsColors.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: SportsMetrics.settingsRowHeight)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { Rectangle().fill(SportsColors.gridDot).frame(height: 2) }
    }

    private func settingsIcon(_ name: String, stroke: Color, fill: Color? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(fill ?? stroke)
            .frame(width: 28, height: 28)
            .overlay { Rectangle().stroke(SportsColors.border, lineWidth: 1) }
    }

    private func hubMetaRow(_ label: String, _ value: String, color: Color, glow: Bool) -> some View {
        HStack {
            Text(label)
                .font(JumbotronFonts.body(11))
                .foregroundStyle(SportsColors.muted)
            Spacer()
            JumbotronLED(text: value, size: 12, color: color, glow: glow)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .overlay(alignment: .top) { Rectangle().fill(SportsColors.gridDot).frame(height: 2) }
        .accessibilityElement(children: .combine)
    }

    private func hubToggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(JumbotronFonts.body(11))
                .foregroundStyle(SportsColors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            JumbotronToggle(isOn: binding)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .overlay(alignment: .top) { Rectangle().fill(SportsColors.gridDot).frame(height: 2) }
    }

    private func handleAlertsToggle(_ enabled: Bool) async {
        if enabled {
            let ok = await GameNotificationService.shared.requestAuthorizationIfNeeded()
            if !ok {
                var p = appModel.playerPrefs
                p.notificationsEnabled = false
                appModel.setPlayerPrefs(p)
            } else {
                appModel.scheduleScoresBackgroundRefresh()
            }
        } else {
            await GameNotificationService.shared.process(
                games: appModel.games,
                favoriteTeamIds: appModel.favoriteTeamIds,
                notifyStarts: false,
                notifyGoals: false,
                masterEnabled: false
            )
            appModel.scheduleScoresBackgroundRefresh()
        }
    }
    #endif

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
