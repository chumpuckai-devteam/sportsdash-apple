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

struct IptvConfig: Codable, Sendable, Equatable {
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

    enum CodingKeys: String, CodingKey {
        case type, m3uURL, xtreamHost, xtreamUsername, displayName
    }
}

struct ChannelMatch: Identifiable, Hashable, Sendable {
    var id: String { channel.id }
    var channel: IptvChannel
    var score: Double
    var reason: String
}
