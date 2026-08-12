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
    @Published var favoriteTeams: [TeamInfo] = []
    /// IPTV channel favorites (Guide ★) — Android long-press parity.
    @Published var favoriteChannelIds: Set<String> = []
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
    /// Precomputed category → channels (avoid O(n) rebuild every SwiftUI body).
    @Published private(set) var channelGroupNames: [String] = []
    @Published private(set) var channelsByGroup: [String: [IptvChannel]] = [:]
    /// True while background short-EPG waves are running (not the same as bulk download).
    @Published private(set) var isAutoFillingEpg = false

    // MARK: - Floating / full-screen player session (UHF-style pop-out)

    @Published var floatingPlayer: FloatingPlayerState?
    /// Full-screen player presentation from floating expand or deep links.
    @Published var fullScreenPlayer: PlayerRoute?
    /// Shared playback used by the floating mini player.
    let floatingPlayback = PlaybackController()

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
        favoriteTeams = storage.favoriteTeams()
        favoriteChannelIds = storage.favoriteChannelIds()
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
        // 1) Instant paint from disk caches (channels + EPG) — no network.
        let playlistId = activePlaylistId
        async let cachedChannels = Task.detached(priority: .userInitiated) {
            StorageService.loadChannelsCacheData(playlistId: playlistId)
        }.value
        async let cachedEpg = Task.detached(priority: .userInitiated) {
            StorageService.loadEpgCacheData()
        }.value

        if let chans = await cachedChannels, !chans.isEmpty, channels.isEmpty {
            applyChannels(chans, persistCache: false)
        }
        if let epg = await cachedEpg, epgByChannel.isEmpty {
            epgByChannel = epg.map
            epgLoadedCount = epg.map.count
            lastEpgReload = epg.savedAt
            epgStatus = "Guide from cache · \(epg.map.count) channels"
        }

        // 2) Network in background so first frame isn't blocked on Xtream/scores.
        let hasChannelCache = !channels.isEmpty
        let needsEpgNetwork = epgByChannel.isEmpty
        let epgStale: Bool = {
            guard let saved = lastEpgReload else { return false }
            return Date().timeIntervalSince(saved) > 3 * 3600
        }()

        Task { @MainActor in
            await refreshScores()
        }

        if let config = iptvConfig, config.isConfigured {
            if hasChannelCache {
                Task { @MainActor in
                    await reloadChannels(showLoading: false)
                    lastPlaylistReload = Date()
                }
            } else {
                await reloadChannels(showLoading: true)
                lastPlaylistReload = Date()
            }
            Task { @MainActor in
                await refreshXtreamAccount()
            }
            if needsEpgNetwork || epgStale {
                Task { @MainActor in
                    await reloadEpg(force: true)
                }
            }
        }

        startScoresPolling()
        startPlaylistPolling()
    }

    /// Rebuild category maps after channel list changes.
    private func applyChannels(_ list: [IptvChannel], persistCache: Bool) {
        channels = list
        rebuildChannelGroups(from: list)
        if persistCache {
            storage.saveChannelsCache(list, playlistId: activePlaylistId)
        }
    }

    private func rebuildChannelGroups(from list: [IptvChannel]) {
        var order: [String] = []
        var map: [String: [IptvChannel]] = [:]
        order.reserveCapacity(64)
        map.reserveCapacity(64)
        for ch in list {
            let g = (ch.group?.isEmpty == false) ? ch.group! : "Other"
            if map[g] == nil {
                order.append(g)
                map[g] = []
                map[g]?.reserveCapacity(32)
            }
            map[g]?.append(ch)
        }
        channelGroupNames = order
        channelsByGroup = map
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
        // Progressive updates — always apply denser snapshots so dated Upcoming
        // boards aren't dropped when pass-1 already filled finals/live.
        let result = await sportsAPI.fetchScoreboards(leagues: leagues) { [weak self] partial in
            Task { @MainActor in
                guard let self else { return }
                let richer =
                    partial.count > self.games.count
                    || Self.upcomingCount(partial) > Self.upcomingCount(self.games)
                    || self.games.isEmpty
                if richer {
                    self.games = partial
                    self.lastUpdated = Date()
                    self.migrateLegacyFavoriteTeamIds(using: partial)
                }
            }
        }
        games = result
        lastUpdated = Date()
        migrateLegacyFavoriteTeamIds(using: result)
    }

    private static func upcomingCount(_ games: [Game]) -> Int {
        games.filter(\.isUpcoming).count
    }

    /// Matching can be heavy with large playlists — keep off hot SwiftUI paths when possible.
    nonisolated func matchesSync(game: Game, channels: [IptvChannel]) -> [ChannelMatch] {
        MatchingService().matchGameToChannels(game, channels: channels)
    }

    /// Reload playlist only (does not clear EPG until new channel ids differ).
    func reloadChannels(showLoading: Bool = true) async {
        guard let config = iptvConfig, config.isConfigured else {
            applyChannels([], persistCache: false)
            return
        }
        if showLoading { isLoadingChannels = true }
        channelsError = nil
        defer { if showLoading { isLoadingChannels = false } }
        do {
            let list = try await iptvService.loadChannels(config: config)
            applyChannels(list, persistCache: true)
        } catch {
            channelsError = error.localizedDescription
            // Keep cached channels if network fails
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
            let list = try await iptvService.loadChannels(config: config)
            applyChannels(list, persistCache: true)
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
            let list = try await iptvService.loadChannels(config: cfg)
            applyChannels(list, persistCache: true)
        }()
        Task { await refreshXtreamAccount() }
        Task { await reloadEpg(force: true) }
    }

    func selectPlaylist(id: String) async {
        guard playlists.contains(where: { $0.id == id }) else { return }
        storage.savePlaylists(playlists, activeId: id)
        activePlaylistId = id
        iptvConfig = storage.loadActiveConfig()
        applyChannels([], persistCache: false)
        epgByChannel = [:]
        epgLoadedCount = 0
        xtreamAccount = nil
        storage.clearEpgCache()
        storage.clearChannelsCache()
        await reloadChannels()
        lastPlaylistReload = Date()
        Task { await refreshXtreamAccount() }
        Task { await reloadEpg(force: true) }
    }

    func removePlaylist(id: String) {
        let wasActive = activePlaylistId == id
        let list = playlists.filter { $0.id != id }
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
            applyChannels([], persistCache: false)
            epgByChannel = [:]
            storage.clearEpgCache()
            storage.clearChannelsCache()
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
                let list = try await iptvService.loadChannels(config: config)
                applyChannels(list, persistCache: true)
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
        applyChannels([], persistCache: false)
        storage.clearChannelsCache()
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

    // MARK: - Floating player (pop-out)

    /// Pop current stream into a floating mini player over the tab UI.
    func popOutPlayer(channel: IptvChannel, game: Game?) {
        floatingPlayback.configure(prefs: playerPrefs)
        floatingPlayback.start(url: channel.url)
        floatingPlayer = FloatingPlayerState(channel: channel, game: game, size: .compact)
        // Dismiss any full-screen cover driven by app-level route.
        fullScreenPlayer = nil
    }

    func closeFloatingPlayer() {
        floatingPlayback.stop()
        floatingPlayer = nil
    }

    func setFloatingPlayerSize(_ size: FloatingPlayerSize) {
        guard var session = floatingPlayer else { return }
        session.size = size
        floatingPlayer = session
    }

    /// Expand floating player into full-screen PlayerView (restarts session there).
    func expandFloatingPlayerToFullscreen() {
        guard let session = floatingPlayer else { return }
        let route = PlayerRoute(channel: session.channel, game: session.game, alternates: [])
        closeFloatingPlayer()
        fullScreenPlayer = route
    }

    /// Full EPG like other IPTV apps: bulk XMLTV + automatic progressive gap-fill.
    /// UI updates as batches arrive — no "Fill missing" required.
    func reloadEpg(force: Bool = false) async {
        guard !channels.isEmpty else {
            epgByChannel = [:]
            epgLoadedCount = 0
            return
        }
        if isLoadingEpg, !force { return }
        if !force, !epgByChannel.isEmpty {
            // Still backfill gaps in background without blocking Guide.
            Task { await self.autoFillAllMissingEpg() }
            return
        }

        // Instant path: disk cache paint, then background refresh/gap-fill.
        if !force, let cached = storage.loadEpgCache(), !cached.isEmpty {
            epgByChannel = cached
            epgLoadedCount = cached.count
            lastEpgReload = storage.epgCacheSavedAt
            epgStatus = "Guide from cache · \(cached.count) channels"
            epgError = nil
            let stale = storage.epgCacheSavedAt.map { Date().timeIntervalSince($0) > 3 * 3600 } ?? true
            if stale {
                Task { await self.reloadEpg(force: true) }
            } else {
                Task { await self.autoFillAllMissingEpg() }
            }
            return
        }

        epgLoadTask?.cancel()
        let snapshot = channels
        let config = iptvConfig
        isLoadingEpg = true
        epgError = nil
        epgStatus = "Downloading full guide…"

        let service = epgService
        let storageRef = storage

        let task = Task.detached(priority: .utility) { [weak self] () -> [String: [EpgProgram]] in
            let model = self
            let map = await service.loadForChannels(
                channels: snapshot,
                config: config,
                limitPerChannel: EpgService.maxProgramsPerChannel,
                batchSize: 16,
                preferBulk: true,
                fillMissingWithShortEpg: true,
                onBatch: { partial in
                    Task { @MainActor in
                        guard let model else { return }
                        // Progressive merge — Guide fills as data arrives.
                        var next = model.epgByChannel
                        for (k, v) in partial where !v.isEmpty { next[k] = v }
                        model.epgByChannel = next
                        model.epgLoadedCount = next.count
                        model.epgError = nil
                    }
                },
                onStatus: { msg in
                    Task { @MainActor in
                        model?.epgStatus = msg
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
                isLoadingEpg = false
                return
            }
            let compact = map.filter { !$0.value.isEmpty }
            if !compact.isEmpty {
                // Prefer richest map (batch merges may already equal this).
                if compact.count >= epgByChannel.count {
                    epgByChannel = compact
                } else {
                    var next = epgByChannel
                    for (k, v) in compact where !v.isEmpty { next[k] = v }
                    epgByChannel = next
                }
                epgLoadedCount = epgByChannel.count
                lastEpgReload = Date()
                epgStatus = "Guide ready · \(epgByChannel.count)/\(channels.count) channels"
                epgError = nil
                storage.saveEpgCache(epgByChannel)
            } else if epgByChannel.isEmpty {
                epgError = "No EPG data returned. Provider may not expose XMLTV."
                epgStatus = nil
            }
            isLoadingEpg = false
        }
        await epgLoadTask?.value
    }

    /// Background: auto-fill every channel still missing EPG (no user action).
    func autoFillAllMissingEpg() async {
        let missing = channels.filter { ch in
            guard let list = epgByChannel[ch.id] else { return true }
            return list.isEmpty
        }
        guard !missing.isEmpty else { return }
        if isLoadingEpg || isAutoFillingEpg { return }
        guard let config = iptvConfig, config.isConfigured else { return }

        isAutoFillingEpg = true
        defer { isAutoFillingEpg = false }

        let service = epgService
        let snapshot = missing
        epgStatus = "Auto-filling guide · \(missing.count) gaps…"

        let map = await Task.detached(priority: .utility) {
            await service.loadForChannels(
                channels: snapshot,
                config: config,
                limitPerChannel: 8,
                batchSize: 16,
                preferBulk: false,
                fillMissingWithShortEpg: true,
                onBatch: { partial in
                    Task { @MainActor in
                        var next = self.epgByChannel
                        for (k, v) in partial where !v.isEmpty { next[k] = v }
                        self.epgByChannel = next
                        self.epgLoadedCount = next.count
                    }
                },
                onStatus: { msg in
                    Task { @MainActor in
                        self.epgStatus = msg
                    }
                }
            )
        }.value

        if !map.isEmpty {
            var next = epgByChannel
            for (k, v) in map where !v.isEmpty { next[k] = v }
            epgByChannel = next
            epgLoadedCount = next.count
            storage.saveEpgCache(epgByChannel)
        }
        epgStatus = "Guide ready · \(epgLoadedCount)/\(channels.count) channels"
    }

    /// Preferential gap-fill for the open Guide category (still automatic; no button).
    /// Does not flip global isLoadingEpg so chrome stays live.
    func loadEpgIfNeeded(for channels: [IptvChannel]) async {
        let missing = channels.filter { ch in
            guard let list = epgByChannel[ch.id] else { return true }
            return list.isEmpty
        }
        guard !missing.isEmpty else { return }
        if isLoadingEpg { return }

        if epgByChannel.isEmpty, let cached = storage.loadEpgCache(), !cached.isEmpty {
            epgByChannel = cached
            epgLoadedCount = cached.count
            let still = missing.filter { epgByChannel[$0.id]?.isEmpty != false }
            if still.isEmpty { return }
        }

        let service = epgService
        let config = iptvConfig
        // Entire open category — not a 24/80 tip.
        let need = missing

        let map = await Task.detached(priority: .utility) {
            await service.loadForChannels(
                channels: need,
                config: config,
                limitPerChannel: 8,
                batchSize: 16,
                preferBulk: false,
                fillMissingWithShortEpg: true,
                onBatch: nil,
                onStatus: nil
            )
        }.value

        guard !map.isEmpty else { return }
        var next = epgByChannel
        for (k, v) in map where !v.isEmpty { next[k] = v }
        epgByChannel = next
        epgLoadedCount = next.count
        storage.saveEpgCache(next)
    }

    func toggleFavorite(teamId: String) {
        guard !teamId.isEmpty else { return }
        if let team = games.flatMap({ [$0.home, $0.away] }).first(where: { $0.id == teamId }) {
            toggleFavorite(team: team)
            return
        }
        storage.toggleFavorite(teamId: teamId)
        favoriteTeamIds = storage.favoriteTeamIds()
        favoriteTeams = storage.favoriteTeams()
    }

    func toggleFavorite(team: TeamInfo) {
        guard !team.id.isEmpty else { return }
        storage.toggleFavorite(team: team)
        favoriteTeams = storage.favoriteTeams()
        favoriteTeamIds = storage.favoriteTeamIds()
    }

    /// Android UI A: games with a starred team under the active filter.
    var myGamesPin: [Game] {
        guard !favoriteTeamIds.isEmpty else { return [] }
        return Self.pinFavoriteGames(
            filteredGames.filter { isFavorite($0) },
            favoriteTeamIds: favoriteTeamIds
        )
    }

    /// Horizontal rail with logos (meta first, enrich from board).
    var favoriteTeamsRail: [TeamInfo] {
        if !favoriteTeams.isEmpty {
            var board: [String: TeamInfo] = [:]
            for g in games {
                board[g.home.id] = g.home
                board[g.away.id] = g.away
            }
            return favoriteTeams.map { t in
                if (t.logoURL == nil || t.logoURL?.isEmpty == true),
                   let b = board[t.id], let logo = b.logoURL, !logo.isEmpty {
                    var enriched = t
                    enriched.logoURL = logo
                    if enriched.colorHex == nil { enriched.colorHex = b.colorHex }
                    return enriched
                }
                return t
            }
        }
        var byId: [String: TeamInfo] = [:]
        for g in games {
            if favoriteTeamIds.contains(g.home.id) { byId[g.home.id] = g.home }
            if favoriteTeamIds.contains(g.away.id) { byId[g.away.id] = g.away }
        }
        return favoriteTeamIds.compactMap { byId[$0] }
    }

    func sportGroupsForPicker() -> [(String, [SportLeague])] {
        let groups = Dictionary(grouping: Array(SportLeague.allCases)) { $0.sportSectionTitle }
        return groups.keys.sorted().map { key in
            (key, (groups[key] ?? []).sorted { $0.label < $1.label })
        }
    }

    func loadTeamsForLeague(_ league: SportLeague) async -> [TeamInfo] {
        await sportsAPI.fetchTeams(league: league)
    }

    /// Users favorite **teams**, not whole games (S-PARITY.FAV.3).
    func isTeamFavorite(_ teamId: String) -> Bool {
        !teamId.isEmpty && favoriteTeamIds.contains(teamId)
    }

    /// ESPN ids collide across sports (nfl:27 Bucs vs mlb:27 Rockies). Rewrite bare numeric ids.
    func migrateLegacyFavoriteTeamIds(using boardGames: [Game] = []) {
        let board = boardGames.isEmpty ? games : boardGames
        var byBare: [String: [TeamInfo]] = [:]
        for g in board {
            for t in [g.home, g.away] where t.id.contains(":") {
                let bare = String(t.id.split(separator: ":").last ?? "")
                guard !bare.isEmpty else { continue }
                byBare[bare, default: []].append(t)
            }
        }
        var next: [TeamInfo] = []
        var changed = false
        for t in favoriteTeams {
            if t.id.contains(":") {
                next.append(t)
                continue
            }
            let bare = t.id
            let candidates = byBare[bare] ?? []
            if let match = candidates.first(where: {
                $0.name.caseInsensitiveCompare(t.name) == .orderedSame
                    || $0.abbreviation.caseInsensitiveCompare(t.abbreviation) == .orderedSame
            }) ?? (candidates.count == 1 ? candidates.first : nil) {
                next.append(TeamInfo(
                    id: match.id,
                    name: t.name.isEmpty ? match.name : t.name,
                    abbreviation: t.abbreviation.isEmpty ? match.abbreviation : t.abbreviation,
                    score: nil,
                    logoURL: t.logoURL ?? match.logoURL,
                    colorHex: t.colorHex ?? match.colorHex,
                    alternateColorHex: t.alternateColorHex ?? match.alternateColorHex,
                    shortName: t.shortName ?? match.shortName
                ))
                changed = true
            } else if !t.name.isEmpty {
                // Drop ambiguous bare ids that we cannot prove — prevents Rockies star from Bucs.
                // Keep only if name uniquely appears on board with stable id.
                let nameHits = board.flatMap { [$0.home, $0.away] }.filter {
                    $0.id.contains(":") && $0.name.caseInsensitiveCompare(t.name) == .orderedSame
                }
                if let only = nameHits.first, Set(nameHits.map(\.id)).count == 1 {
                    var copy = t
                    copy.id = only.id
                    next.append(copy)
                    changed = true
                } else {
                    changed = true // drop unmigratable bare id
                }
            } else {
                changed = true
            }
        }
        // Dedupe
        var seen = Set<String>()
        next = next.filter { seen.insert($0.id).inserted }
        guard changed else { return }
        favoriteTeams = next
        favoriteTeamIds = Set(next.map(\.id))
        storage.setFavoriteTeams(next)
    }

    /// True when either side is a starred team (row chrome / pin sort).
    func isFavorite(_ game: Game) -> Bool {
        isTeamFavorite(game.home.id) || isTeamFavorite(game.away.id)
    }

    // MARK: - Channel favorites (Guide ★)

    static let favoritesChannelGroup = "★ Favorites"

    func isFavoriteChannel(_ channel: IptvChannel) -> Bool {
        favoriteChannelIds.contains(channel.id)
    }

    func toggleFavoriteChannel(_ channel: IptvChannel) {
        storage.toggleFavoriteChannel(id: channel.id)
        favoriteChannelIds = storage.favoriteChannelIds()
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

    /// Live / Upcoming / All — favorite-team games pin first (S-PARITY.FAV.2 / FAV.3).
    /// No separate "favorite games" filter or sticky list — teams only.
    var filteredGames: [Game] {
        let base: [Game]
        switch dashboardFilter {
        case .live:
            base = games.filter(\.isLive)
        case .upcoming:
            base = games.filter(\.isUpcoming)
        case .all:
            // Product label "Final" — completed slate (Android parity).
            base = games.filter(\.isFinal)
        }
        return Self.pinFavoriteGames(base, favoriteTeamIds: favoriteTeamIds)
    }

    /// Favorites first, then live over not-live, then earlier start (stable secondary).
    /// Implementation lives on `ScoreboardGrouping` (nonisolated) for Swift 6 / MainActor safety.
    static func pinFavoriteGames(_ games: [Game], favoriteTeamIds: Set<String>) -> [Game] {
        ScoreboardGrouping.pinFavoriteGames(games, favoriteTeamIds: favoriteTeamIds)
    }

    /// Compatibility: ordered groups from cached maps (O(groups), not O(channels) rebuild).
    var channelGroups: [(name: String, channels: [IptvChannel])] {
        channelGroupNames.map { (name: $0, channels: channelsByGroup[$0] ?? []) }
    }

    func channels(inGroup name: String) -> [IptvChannel] {
        if name == Self.favoritesChannelGroup {
            // Preserve playlist order among favorites.
            return channels.filter { favoriteChannelIds.contains($0.id) }
        }
        return channelsByGroup[name] ?? []
    }

}

