import SwiftUI

/// Multi-playlist manager + Xtream account status.
struct PlaylistSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showEditor = false
    @State private var editingPlaylistId: String?
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                if appModel.playlists.isEmpty {
                    Text("No playlists yet. Add an Xtream or M3U source to get started.")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                } else {
                    ForEach(appModel.playlists) { pl in
                        playlistRow(pl)
                    }
                    .onDelete(perform: delete)
                }

                Button {
                    editingPlaylistId = nil
                    showEditor = true
                } label: {
                    Label("Add playlist", systemImage: "plus.circle.fill")
                        .foregroundStyle(SportsColors.gold)
                }
            } header: {
                Text("Playlists")
            } footer: {
                Text("Only the selected playlist’s channels and EPG are loaded. Switch anytime without losing other sources.")
            }

            if let account = appModel.xtreamAccount {
                Section {
                    LabeledContent("Username", value: account.username ?? "—")
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(account.status ?? "—")
                            .foregroundStyle(account.isActive ? SportsColors.live : SportsColors.danger)
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Connections", value: account.connectionsLabel)
                    LabeledContent("Expires", value: account.expDateLabel)
                    if account.isTrial {
                        Text("Trial account")
                            .font(.caption)
                            .foregroundStyle(SportsColors.gold)
                    }
                    if let msg = account.message, !msg.isEmpty {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                    }
                    Button {
                        Task { await appModel.refreshXtreamAccount() }
                    } label: {
                        if appModel.isLoadingAccount {
                            ProgressView()
                        } else {
                            Label("Refresh account status", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Pulled from your Xtream panel for the selected playlist.")
                }
            } else if appModel.iptvConfig?.type == .xtream {
                Section("Account") {
                    if appModel.isLoadingAccount {
                        ProgressView("Checking account…")
                    } else {
                        Button("Load account status") {
                            Task { await appModel.refreshXtreamAccount() }
                        }
                        Text("Could not load status. Check credentials or server.")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                    }
                }
            }

            Section {
                Button {
                    Task {
                        await appModel.reloadChannels()
                        statusMessage = appModel.channelsError
                            ?? "Playlist reloaded · \(appModel.channels.count) channels."
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
                        statusMessage = appModel.epgError
                            ?? "EPG reloaded · \(appModel.epgLoadedCount) channels cached."
                    }
                } label: {
                    if appModel.isLoadingEpg {
                        HStack {
                            ProgressView()
                            Text(appModel.epgStatus ?? "Reloading EPG…")
                        }
                    } else {
                        Label("Reload EPG", systemImage: "calendar")
                    }
                }
                .disabled(appModel.channels.isEmpty || appModel.isLoadingEpg)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }
            } header: {
                Text("Reload")
            }
        }
        .scrollContentBackground(.hidden)
        .background(SportsColors.voidBlack)
        .navigationTitle("Playlists")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showEditor) {
            PlaylistEditorSheet(
                playlistId: editingPlaylistId,
                existing: editingPlaylistId.flatMap { id in
                    appModel.playlists.first(where: { $0.id == id })?.config
                }
            )
            .environmentObject(appModel)
        }
        .task {
            if appModel.iptvConfig?.type == .xtream {
                await appModel.refreshXtreamAccount()
            }
        }
    }

    private func playlistRow(_ pl: IptvPlaylist) -> some View {
        let isActive = pl.id == appModel.activePlaylistId
        return HStack(spacing: 12) {
            Button {
                Task { await appModel.selectPlaylist(id: pl.id) }
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? SportsColors.gold : SportsColors.muted)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(pl.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SportsColors.text)
                Text(pl.config.type == .xtream ? "Xtream" : "M3U")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            }

            Spacer()

            if isActive {
                Text("Active")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SportsColors.voidBlack)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SportsColors.gold, in: Capsule())
            }

            Button {
                editingPlaylistId = pl.id
                showEditor = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(SportsColors.muted)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(SportsColors.panel)
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets {
            let id = appModel.playlists[i].id
            appModel.removePlaylist(id: id)
        }
    }
}

// MARK: - Add / Edit sheet

private struct PlaylistEditorSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    var playlistId: String?
    var existing: IptvConfig?

    @State private var sourceType: IptvSourceType = .xtream
    @State private var displayName = ""
    @State private var m3uURL = ""
    @State private var host = ""
    @State private var user = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $displayName)
                    Picker("Type", selection: $sourceType) {
                        Text("Xtream").tag(IptvSourceType.xtream)
                        Text("M3U").tag(IptvSourceType.m3u)
                    }
                    .pickerStyle(.segmented)
                }

                if sourceType == .m3u {
                    Section("M3U") {
                        TextField("Playlist URL", text: $m3uURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .keyboardType(.URL)
                            #endif
                    }
                } else {
                    Section("Xtream") {
                        TextField("Server URL", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Username", text: $user)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                    }
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(SportsColors.danger)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SportsColors.voidBlack)
            .navigationTitle(playlistId == nil ? "Add playlist" : "Edit playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear(perform: hydrate)
        }
    }

    private func hydrate() {
        guard let existing else { return }
        sourceType = existing.type
        displayName = existing.displayName ?? ""
        m3uURL = existing.m3uURL ?? ""
        host = existing.xtreamHost ?? ""
        user = existing.xtreamUsername ?? ""
        password = existing.xtreamPassword ?? ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var config = IptvConfig(
            type: sourceType,
            m3uURL: m3uURL,
            xtreamHost: host,
            xtreamUsername: user,
            xtreamPassword: password,
            displayName: name.isEmpty ? nil : name
        )
        if name.isEmpty {
            config.displayName = config.summaryLabel
        }
        guard config.isConfigured else {
            error = "Fill in required fields."
            return
        }
        do {
            if let playlistId {
                try await appModel.updatePlaylist(id: playlistId, config: config)
            } else {
                try await appModel.addPlaylist(config)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
