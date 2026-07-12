import Foundation

struct IptvChannel: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var url: String
    var group: String?
    var logoURL: String?
    var tvgId: String?
    var epgChannelId: String?
}

enum IptvSourceType: String, Codable, Sendable {
    case m3u
    case xtream
}

struct IptvConfig: Codable, Sendable, Equatable, Hashable {
    var type: IptvSourceType
    var m3uURL: String?
    var xtreamHost: String?
    var xtreamUsername: String?
    /// Loaded from Keychain; not encoded into UserDefaults JSON.
    var xtreamPassword: String?
    var displayName: String?

    var isConfigured: Bool {
        switch type {
        case .m3u:
            return !(m3uURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        case .xtream:
            return !(xtreamHost?.isEmpty ?? true)
                && !(xtreamUsername?.isEmpty ?? true)
                && !(xtreamPassword?.isEmpty ?? true)
        }
    }

    var summaryLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        switch type {
        case .m3u: return "M3U Playlist"
        case .xtream: return xtreamUsername.map { "Xtream · \($0)" } ?? "Xtream"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, m3uURL, xtreamHost, xtreamUsername, displayName
    }
}

/// A saved IPTV source the user can switch between.
struct IptvPlaylist: Identifiable, Codable, Sendable, Equatable, Hashable {
    var id: String
    var config: IptvConfig

    init(id: String = UUID().uuidString, config: IptvConfig) {
        self.id = id
        self.config = config
    }

    var name: String { config.summaryLabel }
}

/// Xtream `player_api.php` user_info payload.
struct XtreamAccountInfo: Sendable, Equatable {
    var username: String?
    var status: String?
    var expDate: Date?
    var isTrial: Bool
    var activeConnections: Int?
    var maxConnections: Int?
    var createdAt: Date?
    var message: String?

    var isActive: Bool {
        let s = (status ?? "").lowercased()
        return s == "active" || s == "true" || s == "1"
    }

    var expDateLabel: String {
        guard let expDate else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: expDate)
    }

    var connectionsLabel: String {
        let a = activeConnections.map(String.init) ?? "—"
        let m = maxConnections.map(String.init) ?? "—"
        return "\(a) / \(m)"
    }
}

struct ChannelMatch: Identifiable, Hashable, Sendable {
    var id: String { channel.id }
    var channel: IptvChannel
    var score: Double
    var reason: String
}
