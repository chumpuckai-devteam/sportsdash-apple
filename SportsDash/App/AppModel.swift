import Combine
import Foundation
import SwiftUI

/// Shared app state — Flutter providers parity.
@MainActor
final class AppModel: ObservableObject {
    @Published var games: [Game] = []
    @Published var channels: [IptvChannel] = []
    @Published var isLoadingScores = false
    @Published var isLoadingChannels = false
    @Published var scoresError: String?
    @Published var channelsError: String?
    @Published var lastUpdated: Date?
    /// Saved IPTV sources (multi-playlist).
    @Published var playlists: [IptvPlaylist] = []
    @Published var activePlaylistId: String?
    /// Convenience: active playlist config (backward compatible).
    @Published var iptvConfig: IptvConfig?
    @Published var xtreamAccount: XtreamAccountInfo?
    @Published var isLoadingAccount = false
    @Published var favoriteTeamIds: Set<String> = []
    @Published var lastPlayedGameIds: [String] = []
    @Published var playerPrefs = PlayerPrefs()
    @Published var selectedLeagues: [SportLeague] = SportLeague.defaults
    @Published var dashboardFilter: DashboardFilter = .live
    @Published var epgByChannel: [String: [EpgProgram]] = [:]
    @Published var isLoadingEpg = false
    /// Channels with EPG entries loaded (may be empty lists).
    @Published var epgLoadedCount = 0
    @Published var lastEpgReload: Date?
    @Published var epgError: String?
    /// Human status while EPG loads (e.g. “Downloading full guide (XMLTV)…”).
    @Published var epgStatus: String?

    let sportsAPI = SportsAPI()
    let iptvService = IptvService()
    let matching = MatchingService()
    let epgService = EpgService()
    private let storage = StorageService.shared

    private var scoresTimer: Timer?
    private var playlistTimer: Timer?
    private var lastPlaylistReload: Date?
    private var epgLoadTask: Task<Void, Never>?

    init() {
        favoriteTeamIds = storage.favoriteTeamIds()
        lastPlayedGameIds = storage.lastPlayedGameIds()
        playerPrefs = storage.playerPrefs()
        selectedLeagues = storage.selectedLeagues()
        playlists = storage.loadPlaylists()
        activePlaylistId = storage.activePlaylistId() ?? playlists.first?.id
        iptvConfig = storage.loadActiveConfig()
    }

    var activePlaylist: IptvPlaylist? {
        guard let activePlaylistId else { return playlists.first }
        return playlists.first(where: { $0.id == activePlaylistId }) ?? playlists.first
    }

    func bootstrap() async {
        // Scores first (lightweight). Playlist next. EPG in background so launch
        // never blocks on a large guide download.
        await refreshScores()
        if let config = iptvConfig, config.isConfigured {
            await reloadChannels()
            lastPlaylistReload = Date()
            Task { await refreshXtreamAccount() }
            Task { await reloadEpg(force: false) }
        }
        startScoresPolling()
        startPlaylistPolling()
    }

    func startScoresPolling() {
        scoresTimer?.invalidate()
        scoresTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshScores(silent: true)
            }
        }
    }

    /// Reload IPTV playlist on the schedule from General settings.
    func startPlaylistPolling() {
        playlistTimer?.invalidate()
        let hours = playerPrefs.playlistRefresh.rawValue
        guard hours > 0 else { return }
        // Check every 15 minutes whether the refresh interval has elapsed.
        playlistTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.maybeReloadPlaylist()
            }
        }
    }

    private func maybeReloadPlaylist() async {
        let hours = playerPrefs.playlistRefresh.rawValue
        guard hours > 0, iptvConfig?.isConfigured == true else { return }
        let last = lastPlaylistReload ?? .distantPast
        let elapsed = Date().timeIntervalSince(last)
        guard elapsed >= Double(hours) * 3600 else { return }
        await reloadChannels()
        lastPlaylistReload = Date()
        await reloadEpg(force: true)
    }

    func refreshScores(silent: Bool = false) async {
        if !silent { isLoadingScores = true }
        scoresError = nil
        defer { if !silent { isLoadingScores = false } }
        let leagues = selectedLeagues.isEmpty ? SportLeague.defaults : selectedLeagues
        // Progressive updates — first leagues paint quickly instead of waiting for all.
        let result = await sportsAPI.fetchScoreboards(leagues: leagues) { [weak self] partial in
            Task { @MainActor in
                guard let self else { return }
                // Only push partial if we still have nothing or fewer games
                if self.games.count < partial.count || self.games.isEmpty {
                    self.games = partial
                    self.lastUpdated = Date()
                }
            }
        }
        games = result
        lastUpdated = Date()
    }

    /// Matching can be heavy with large playlists — keep off hot SwiftUI paths when possible.
    nonisolated func matchesSync(game: Game, channels: [IptvChannel]) -> [ChannelMatch] {
        MatchingService().matchGameToChannels(game, channels: channels)
    }

    /// Reload playlist only (does not clear EPG until new channel ids differ).
    func reloadChannels() async {
        guard let config = iptvConfig, config.isConfigured else {
            channels = []
            return
        }
        isLoadingChannels = true
        channelsError = nil
        defer { isLoadingChannels = false }
        do {
            channels = try await iptvService.loadChannels(config: config)
        } catch {
            channelsError = error.localizedDescription
        }
    }

    /// Add a new playlist and make it active.
    func addPlaylist(_ config: IptvConfig) async throws {
        guard config.isConfigured else { throw IptvError.invalidConfig }
        var list = playlists
        let pl = IptvPlaylist(config: config)
        list.append(pl)
        storage.savePlaylists(list, activeId: pl.id)
        playlists = storage.loadPlaylists()
        activePlaylistId = pl.id
        iptvConfig = storage.loadActiveConfig()
        try await {
            isLoadingChannels = true
            defer { isLoadingChannels = false }
            channels = try await iptvService.loadChannels(config: config)
        }()
        Task { await refreshXtreamAccount() }
        Task { await reloadEpg(force: true) }
    }

    /// Update the active playlist credentials (or create one if empty).
    func saveIptvConfig(_ config: IptvConfig) async throws {
        guard config.isConfigured else { throw IptvError.invalidConfig }
        var list = playlists
        if let active = activePlaylistId, let idx = list.firstIndex(where: { $0.id == active }) {
            list[idx].config = config
            storage.savePlaylists(list, activeId: active)
        } else {
            let pl = IptvPlaylist(config: config)
            list.append(pl)
            storage.savePlaylists(list, activeId: pl.id)
            activePlaylistId = pl.id
        }
        playlists = storage.loadPlaylists()
        iptvConfig = storage.loadActiveConfig()
        try await {
            isLoadingChannels = true
            defer { isLoadingChannels = false }
            guard let cfg = storage.loadActiveConfig() else { return }
            channels = try await iptvService.loadChannels(config: cfg)
        }()
        Task { await refreshXtreamAccount() }
        Task { await reloadEpg(force: true) }
    }

    func selectPlaylist(id: String) async {
        guard playlists.contains(where: { $0.id == id }) else { return }
        storage.savePlaylists(playlists, activeId: id)
        activePlaylistId = id
        iptvConfig = storage.loadActiveConfig()
        channels = []
        epgByChannel = [:]
        epgLoadedCount = 0
        xtreamAccount = nil
        storage.clearEpgCache()
        await reloadChannels()
        lastPlaylistReload = Date()
        Task { await refreshXtreamAccount() }
        Task { await reloadEpg(force: true) }
    }

    func removePlaylist(id: String) {
        let wasActive = activePlaylistId == id
        var list = playlists.filter { $0.id != id }
        KeychainStore.delete(account: "iptv_pass_\(id)")
        let newActive: String? = wasActive ? list.first?.id : activePlaylistId
        if list.isEmpty {
            clearIptvConfig()
            return
        }
        storage.savePlaylists(list, activeId: newActive)
        playlists = storage.loadPlaylists()
        activePlaylistId = newActive
        iptvConfig = storage.loadActiveConfig()
        if wasActive {
            channels = []
            epgByChannel = [:]
            storage.clearEpgCache()
            Task {
                await reloadChannels()
                await refreshXtreamAccount()
                await reloadEpg(force: true)
            }
        }
    }

    /// Update credentials for a playlist id (does not switch active unless it is active).
    func updatePlaylist(id: String, config: IptvConfig) async throws {
        guard config.isConfigured else { throw IptvError.invalidConfig }
        var list = playlists
        guard let idx = list.firstIndex(where: { $0.id == id }) else {
            try await addPlaylist(config)
            return
        }
        list[idx].config = config
        storage.savePlaylists(list, activeId: activePlaylistId)
        playlists = storage.loadPlaylists()
        if activePlaylistId == id {
            iptvConfig = storage.loadActiveConfig()
            try await {
                isLoadingChannels = true
                defer { isLoadingChannels = false }
                channels = try await iptvService.loadChannels(config: config)
            }()
            Task { await refreshXtreamAccount() }
            Task { await reloadEpg(force: true) }
        }
    }

    func clearIptvConfig() {
        epgLoadTask?.cancel()
        storage.clearIptvConfig()
        playlists = []
        activePlaylistId = nil
        iptvConfig = nil
        xtreamAccount = nil
        channels = []
        epgByChannel = [:]
        epgLoadedCount = 0
        lastEpgReload = nil
        epgError = nil
        epgStatus = nil
    }

    func refreshXtreamAccount() async {
        guard let config = iptvConfig, config.type == .xtream, config.isConfigured else {
            xtreamAccount = nil
            return
        }
        isLoadingAccount = true
        defer { isLoadingAccount = false }
        do {
            xtreamAccount = try await iptvService.fetchXtreamAccountInfo(config: config)
        } catch {
            xtreamAccount = nil
        }
    }

    /// Full EPG: disk download + background parse. UI only gets status ticks + final result.
    func reloadEpg(force: Bool = false) async {
        guard !channels.isEmpty else {
            epgByChannel = [:]
            epgLoadedCount = 0
            return
        }
        if isLoadingEpg, !force { return }
        if !force, !epgByChannel.isEmpty {
            return
        }

        // Instant path: load previous parse from disk cache (no network, no RAM spike).
        if !force, let cached = storage.loadEpgCache(), !cached.isEmpty {
            epgByChannel = cached
            epgLoadedCount = cached.count
            lastEpgReload = storage.epgCacheSavedAt
            epgStatus = "Guide from cache · \(cached.count) channels"
            epgError = nil
            // Refresh in background if cache is older than 3 hours.
            if let saved = storage.epgCacheSavedAt,
               Date().timeIntervalSince(saved) > 3 * 3600 {
                Task { await self.reloadEpg(force: true) }
            }
            return
        }

        epgLoadTask?.cancel()
        let snapshot = channels
        let config = iptvConfig
        isLoadingEpg = true
        epgError = nil
        epgStatus = "Downloading guide to disk…"
        if force {
            // Keep showing old listings while refreshing so Settings/Guide stay usable.
        }

        // Heavy work runs off the main actor — Settings stays responsive.
        let service = epgService
        let storageRef = storage
        let task = Task.detached(priority: .utility) { [weak self] () -> [String: [EpgProgram]] in
            let map = await service.loadForChannels(
                channels: snapshot,
                config: config,
                limitPerChannel: EpgService.maxProgramsPerChannel,
                batchSize: 12,
                preferBulk: true,
                fillMissingWithShortEpg: false,
                onBatch: nil,
                onStatus: { msg in
                    Task { @MainActor in
                        self?.epgStatus = msg
                    }
                }
            )
            if !map.isEmpty {
                await MainActor.run {
                    storageRef.saveEpgCache(map)
                }
            }
            return map
        }
        epgLoadTask = Task { @MainActor in
            let map = await task.value
            guard !Task.isCancelled else {
                self.isLoadingEpg = false
                return
            }
            let compact = map.filter { !$0.value.isEmpty }
            if !compact.isEmpty {
                self.epgByChannel = compact
                self.epgLoadedCount = compact.count
                self.lastEpgReload = Date()
                self.epgStatus = "Guide ready · \(compact.count) channels"
                self.epgError = nil
            } else {
                self.epgError = "No EPG data returned. Provider may not expose XMLTV."
                self.epgStatus = nil
            }
            self.isLoadingEpg = false
        }
        await epgLoadTask?.value
    }

    /// Fill gaps for a guide category without blocking UI; uses short EPG only.
    func loadEpgIfNeeded(for channels: [IptvChannel]) async {
        let missing = channels.filter { ch in
            guard let list = epgByChannel[ch.id] else { return true }
            return list.isEmpty
        }
        guard !missing.isEmpty else { return }
        if isLoadingEpg { return } // bulk job owns the pipeline

        // Prefer cache hit first.
        if epgByChannel.isEmpty, let cached = storage.loadEpgCache(), !cached.isEmpty {
            epgByChannel = cached
            epgLoadedCount = cached.count
            let still = missing.filter { epgByChannel[$0.id]?.isEmpty != false }
            if still.isEmpty { return }
        }

        isLoadingEpg = true
        epgStatus = "Filling \(missing.count) channels…"
        let service = epgService
        let config = iptvConfig
        let need = Array(missing.prefix(80))

        let map = await Task.detached(priority: .utility) {
            await service.loadForChannels(
                channels: need,
                config: config,
                limitPerChannel: 8,
                batchSize: 12,
                preferBulk: false,
                fillMissingWithShortEpg: true,
                onBatch: nil,
                onStatus: nil
            )
        }.value

        var next = epgByChannel
        for (k, v) in map where !v.isEmpty { next[k] = v }
        epgByChannel = next
        epgLoadedCount = next.count
        isLoadingEpg = false
        if epgStatus?.hasPrefix("Filling") == true {
            epgStatus = next.isEmpty ? nil : "Guide · \(next.count) channels"
        }
    }

    func toggleFavorite(teamId: String) {
        storage.toggleFavorite(teamId: teamId)
        favoriteTeamIds = storage.favoriteTeamIds()
    }

    func isFavorite(_ game: Game) -> Bool {
        favoriteTeamIds.contains(game.home.id) || favoriteTeamIds.contains(game.away.id)
    }

    func recordLastPlayed(gameId: String) {
        lastPlayedGameIds = storage.recordLastPlayed(gameId: gameId)
    }

    func setPlayerPrefs(_ prefs: PlayerPrefs) {
        let refreshChanged = prefs.playlistRefresh != playerPrefs.playlistRefresh
        playerPrefs = prefs
        storage.setPlayerPrefs(prefs)
        PlaybackController.applyGlobal(prefs)
        if refreshChanged {
            startPlaylistPolling()
        }
    }

    func setSelectedLeagues(_ leagues: [SportLeague]) {
        selectedLeagues = leagues
        storage.setSelectedLeagues(leagues)
        Task { await refreshScores() }
    }

    func matches(for game: Game) -> [ChannelMatch] {
        // Snapshot channels to avoid long main-thread holds on huge playlists
        let chans = channels
        return matching.matchGameToChannels(game, channels: chans)
    }

    var filteredGames: [Game] {
        switch dashboardFilter {
        case .live:
            return games.filter(\.isLive)
        case .upcoming:
            return games.filter(\.isUpcoming)
        case .favorites:
            return games.filter {
                ($0.isLive || $0.isUpcoming) && isFavorite($0)
            }
        case .all:
            return games
        }
    }

    var favoriteGames: [Game] {
        games.filter {
            ($0.isLive || $0.isUpcoming) && isFavorite($0)
        }
    }

    var channelGroups: [(name: String, channels: [IptvChannel])] {
        var order: [String] = []
        var map: [String: [IptvChannel]] = [:]
        for ch in channels {
            let g = (ch.group?.isEmpty == false) ? ch.group! : "Other"
            if map[g] == nil {
                order.append(g)
                map[g] = []
            }
            map[g]?.append(ch)
        }
        return order.map { (name: $0, channels: map[$0] ?? []) }
    }

}

