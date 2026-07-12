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

    let sportsAPI = SportsAPI()
    let iptvService = IptvService()
    let matching = MatchingService()
    let epgService = EpgService()
    private let storage = StorageService.shared

    private var scoresTimer: Timer?

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
        }
        startScoresPolling()
    }

    func startScoresPolling() {
        scoresTimer?.invalidate()
        scoresTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshScores(silent: true)
            }
        }
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
    }

    func clearIptvConfig() {
        storage.clearIptvConfig()
        iptvConfig = nil
        channels = []
        epgByChannel = [:]
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
        playerPrefs = prefs
        storage.setPlayerPrefs(prefs)
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

    func loadEpg(for channels: [IptvChannel], limitPerChannel: Int = 12) async {
        isLoadingEpg = true
        defer { isLoadingEpg = false }
        let map = await epgService.loadForChannels(
            channels: channels,
            config: iptvConfig,
            limitPerChannel: limitPerChannel
        )
        // Merge so switching groups doesn't wipe other channels' EPG.
        var next = epgByChannel
        for (k, v) in map { next[k] = v }
        epgByChannel = next
    }
}
