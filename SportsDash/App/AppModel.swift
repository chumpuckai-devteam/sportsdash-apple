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
    @Published var iptvConfig: IptvConfig?
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
        iptvConfig = storage.loadIptvConfig()
    }

    func bootstrap() async {
        await refreshScores()
        if let config = iptvConfig, config.isConfigured {
            await reloadChannels()
            lastPlaylistReload = Date()
            // Full guide for every channel — progressive so Guide paints early.
            await reloadEpg(force: true)
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

    func saveIptvConfig(_ config: IptvConfig) async throws {
        storage.saveIptvConfig(config)
        iptvConfig = storage.loadIptvConfig()
        try await {
            isLoadingChannels = true
            defer { isLoadingChannels = false }
            channels = try await iptvService.loadChannels(config: storage.loadIptvConfig() ?? config)
        }()
        // Fresh playlist → pull full EPG in the background.
        Task { await reloadEpg(force: true) }
    }

    func clearIptvConfig() {
        epgLoadTask?.cancel()
        storage.clearIptvConfig()
        iptvConfig = nil
        channels = []
        epgByChannel = [:]
        epgLoadedCount = 0
        lastEpgReload = nil
        epgError = nil
    }

    /// Full EPG for every loaded channel. Progressive merge so Guide updates live.
    func reloadEpg(force: Bool = false) async {
        guard !channels.isEmpty else {
            epgByChannel = [:]
            epgLoadedCount = 0
            return
        }
        if isLoadingEpg, !force { return }
        if !force, lastEpgReload != nil, !epgByChannel.isEmpty, epgLoadedCount >= channels.count {
            return
        }

        epgLoadTask?.cancel()
        let snapshot = channels
        let config = iptvConfig
        isLoadingEpg = true
        epgError = nil
        if force {
            epgByChannel = [:]
            epgLoadedCount = 0
        }

        let task = Task { @MainActor in
            let map = await epgService.loadForChannels(
                channels: snapshot,
                config: config,
                limitPerChannel: 24,
                batchSize: 12
            ) { [weak self] batch in
                guard let self else { return }
                var next = self.epgByChannel
                for (k, v) in batch { next[k] = v }
                self.epgByChannel = next
                self.epgLoadedCount = next.count
            }
            guard !Task.isCancelled else { return }
            // Final merge (covers empty batches).
            var next = epgByChannel
            for (k, v) in map { next[k] = v }
            epgByChannel = next
            epgLoadedCount = next.count
            lastEpgReload = Date()
            isLoadingEpg = false
            if map.isEmpty {
                epgError = "No EPG data returned from provider."
            }
        }
        epgLoadTask = task
        await task.value
    }

    /// Load EPG only for channels missing from the cache (used when opening a guide category early).
    func loadEpgIfNeeded(for channels: [IptvChannel]) async {
        let missing = channels.filter { epgByChannel[$0.id] == nil }
        guard !missing.isEmpty else { return }
        if isLoadingEpg {
            // Full load already running — wait for it.
            await epgLoadTask?.value
            return
        }
        isLoadingEpg = true
        defer { isLoadingEpg = false }
        let map = await epgService.loadForChannels(
            channels: missing,
            config: iptvConfig,
            limitPerChannel: 24,
            batchSize: 12
        ) { [weak self] batch in
            guard let self else { return }
            var next = self.epgByChannel
            for (k, v) in batch { next[k] = v }
            self.epgByChannel = next
            self.epgLoadedCount = next.count
        }
        var next = epgByChannel
        for (k, v) in map { next[k] = v }
        epgByChannel = next
        epgLoadedCount = next.count
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

