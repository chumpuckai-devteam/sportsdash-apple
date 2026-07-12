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
        guard let data = defaults.data(forKey: playerPrefsKey),
              let prefs = try? JSONDecoder().decode(PlayerPrefs.self, from: data) else {
            return PlayerPrefs()
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

    // MARK: - IPTV

    func loadIptvConfig() -> IptvConfig? {
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

    func saveIptvConfig(_ config: IptvConfig) {
        var toStore = config
        let password = config.xtreamPassword
        toStore.xtreamPassword = nil // never store password in JSON blob
        if let data = try? JSONEncoder().encode(toStore) {
            defaults.set(data, forKey: iptvMetaKey)
        }
        if let password, !password.isEmpty {
            KeychainStore.set(password, account: iptvPassAccount)
            defaults.set(password, forKey: "\(iptvPassAccount)_fallback")
        }
    }

    func clearIptvConfig() {
        defaults.removeObject(forKey: iptvMetaKey)
        defaults.removeObject(forKey: "\(iptvPassAccount)_fallback")
        KeychainStore.delete(account: iptvPassAccount)
    }
}
