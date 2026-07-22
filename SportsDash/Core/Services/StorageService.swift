import Foundation

/// UserDefaults + Keychain persistence (Flutter StorageService parity).
@MainActor
final class StorageService {
    static let shared = StorageService()

    private let defaults = UserDefaults.standard
    private let iptvMetaKey = "iptv_config_meta"
    private let iptvPassAccount = "iptv_xtream_password"
    private let favoritesKey = "favorite_team_ids"
    private let lastPlayedKey = "last_played_game_ids"
    private let playerPrefsKey = "player_prefs_json"
    /// Bump when we need a one-shot prefs migration on existing installs.
    private let playerPrefsMigrationKey = "player_prefs_migration_v"
    private let playerPrefsMigrationVersion = 2
    private let selectedLeaguesKey = "selected_leagues"
    private let maxLastPlayed = 30

    // MARK: - Favorites

    func favoriteTeamIds() -> Set<String> {
        Set(defaults.stringArray(forKey: favoritesKey) ?? [])
    }

    func setFavoriteTeamIds(_ ids: Set<String>) {
        defaults.set(Array(ids), forKey: favoritesKey)
    }

    func toggleFavorite(teamId: String) {
        var ids = favoriteTeamIds()
        if ids.contains(teamId) { ids.remove(teamId) } else { ids.insert(teamId) }
        setFavoriteTeamIds(ids)
    }

    // MARK: - Last played

    func lastPlayedGameIds() -> [String] {
        defaults.stringArray(forKey: lastPlayedKey) ?? []
    }

    @discardableResult
    func recordLastPlayed(gameId: String) -> [String] {
        guard !gameId.isEmpty else { return lastPlayedGameIds() }
        var next = [gameId]
        for id in lastPlayedGameIds() where id != gameId {
            next.append(id)
            if next.count >= maxLastPlayed { break }
        }
        defaults.set(next, forKey: lastPlayedKey)
        return next
    }

    // MARK: - Player prefs

    func playerPrefs() -> PlayerPrefs {
        var prefs: PlayerPrefs = {
            guard let data = defaults.data(forKey: playerPrefsKey),
                  let decoded = try? JSONDecoder().decode(PlayerPrefs.self, from: data) else {
                return PlayerPrefs()
            }
            return decoded
        }()

        // One-shot: force KSPlayer as default after VLC experiments left AVKit selected.
        let migrated = defaults.integer(forKey: playerPrefsMigrationKey)
        if migrated < playerPrefsMigrationVersion {
            prefs.primaryPlayer = .ksPlayer
            // Keep fallback on so AV can still try if KS fails a stream.
            if migrated < 2 {
                prefs.fallbackPlayers = true
            }
            setPlayerPrefs(prefs)
            defaults.set(playerPrefsMigrationVersion, forKey: playerPrefsMigrationKey)
        }
        return prefs
    }

    func setPlayerPrefs(_ prefs: PlayerPrefs) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: playerPrefsKey)
        }
    }

    // MARK: - Selected leagues

    func selectedLeagues() -> [SportLeague] {
        guard let raw = defaults.stringArray(forKey: selectedLeaguesKey), !raw.isEmpty else {
            return SportLeague.defaults
        }
        let leagues = raw.compactMap { SportLeague(rawValue: $0) }
        return leagues.isEmpty ? SportLeague.defaults : leagues
    }

    func setSelectedLeagues(_ leagues: [SportLeague]) {
        defaults.set(leagues.map(\.rawValue), forKey: selectedLeaguesKey)
    }

    // MARK: - IPTV (multi-playlist)

    private let playlistsKey = "iptv_playlists_v1"
    private let activePlaylistKey = "iptv_active_playlist_id"

    private func passwordAccount(for playlistId: String) -> String {
        "iptv_pass_\(playlistId)"
    }

    /// All saved playlists with passwords hydrated from Keychain.
    func loadPlaylists() -> [IptvPlaylist] {
        // Migrate legacy single-config store once.
        if defaults.data(forKey: playlistsKey) == nil,
           let legacy = loadLegacyIptvConfig() {
            let pl = IptvPlaylist(config: legacy)
            savePlaylists([pl], activeId: pl.id)
            clearLegacyIptvConfig()
        }

        guard let data = defaults.data(forKey: playlistsKey),
              var list = try? JSONDecoder().decode([IptvPlaylist].self, from: data) else {
            return []
        }
        for i in list.indices {
            let id = list[i].id
            if list[i].config.type == .xtream {
                list[i].config.xtreamPassword =
                    KeychainStore.get(account: passwordAccount(for: id))
                    ?? KeychainStore.get(account: iptvPassAccount) // legacy fallback
            }
        }
        return list
    }

    func activePlaylistId() -> String? {
        defaults.string(forKey: activePlaylistKey)
    }

    func savePlaylists(_ playlists: [IptvPlaylist], activeId: String?) {
        // Strip passwords from JSON; store each in Keychain by playlist id.
        var encoded: [IptvPlaylist] = []
        for pl in playlists {
            var copy = pl
            let password = copy.config.xtreamPassword
            copy.config.xtreamPassword = nil
            encoded.append(copy)
            if let password, !password.isEmpty {
                KeychainStore.set(password, account: passwordAccount(for: pl.id))
            }
        }
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: playlistsKey)
        }
        if let activeId {
            defaults.set(activeId, forKey: activePlaylistKey)
        } else {
            defaults.removeObject(forKey: activePlaylistKey)
        }
    }

    func loadActiveConfig() -> IptvConfig? {
        let list = loadPlaylists()
        guard !list.isEmpty else { return nil }
        let active = activePlaylistId()
        if let active, let match = list.first(where: { $0.id == active }) {
            return match.config
        }
        return list.first?.config
    }

    /// Legacy single-config API used during migration.
    func loadIptvConfig() -> IptvConfig? {
        loadActiveConfig()
    }

    func saveIptvConfig(_ config: IptvConfig) {
        var list = loadPlaylists()
        if let active = activePlaylistId(),
           let idx = list.firstIndex(where: { $0.id == active }) {
            list[idx].config = config
            savePlaylists(list, activeId: active)
        } else if list.isEmpty {
            let pl = IptvPlaylist(config: config)
            savePlaylists([pl], activeId: pl.id)
        } else {
            list[0].config = config
            savePlaylists(list, activeId: list[0].id)
        }
    }

    func clearIptvConfig() {
        let list = loadPlaylists()
        for pl in list {
            KeychainStore.delete(account: passwordAccount(for: pl.id))
        }
        defaults.removeObject(forKey: playlistsKey)
        defaults.removeObject(forKey: activePlaylistKey)
        clearLegacyIptvConfig()
        clearEpgCache()
    }

    private func loadLegacyIptvConfig() -> IptvConfig? {
        guard let data = defaults.data(forKey: iptvMetaKey),
              var config = try? JSONDecoder().decode(IptvConfig.self, from: data) else {
            return nil
        }
        if config.type == .xtream {
            config.xtreamPassword = KeychainStore.get(account: iptvPassAccount)
                ?? defaults.string(forKey: "\(iptvPassAccount)_fallback")
        }
        return config
    }

    private func clearLegacyIptvConfig() {
        defaults.removeObject(forKey: iptvMetaKey)
        defaults.removeObject(forKey: "\(iptvPassAccount)_fallback")
        KeychainStore.delete(account: iptvPassAccount)
    }

    // MARK: - EPG disk cache (keeps RAM free; next launch is instant)

    private var epgCacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("sportsdash_epg_cache.json")
    }

    private let epgCacheDateKey = "epg_cache_saved_at"

    /// Cached guide listings (compact JSON on disk). Max age ~12 hours.
    func loadEpgCache(maxAge: TimeInterval = 12 * 3600) -> [String: [EpgProgram]]? {
        guard let saved = defaults.object(forKey: epgCacheDateKey) as? Date,
              Date().timeIntervalSince(saved) < maxAge,
              let data = try? Data(contentsOf: epgCacheURL),
              !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode([String: [EpgProgram]].self, from: data)
    }

    func saveEpgCache(_ map: [String: [EpgProgram]]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        // Cap payload: drop empty lists
        let compact = map.filter { !$0.value.isEmpty }
        guard let data = try? encoder.encode(compact) else { return }
        try? data.write(to: epgCacheURL, options: .atomic)
        defaults.set(Date(), forKey: epgCacheDateKey)
    }

    func clearEpgCache() {
        try? FileManager.default.removeItem(at: epgCacheURL)
        defaults.removeObject(forKey: epgCacheDateKey)
    }

    var epgCacheSavedAt: Date? {
        defaults.object(forKey: epgCacheDateKey) as? Date
    }
}
