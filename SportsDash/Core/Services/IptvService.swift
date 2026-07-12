import Foundation

/// M3U / Xtream loaders — ported from Flutter `IptvService` (subset for v1).
actor IptvService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadChannels(config: IptvConfig) async throws -> [IptvChannel] {
        switch config.type {
        case .m3u:
            guard let raw = config.m3uURL, let url = URL(string: raw) else {
                throw IptvError.invalidConfig
            }
            let (data, _) = try await session.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            return parseM3U(text)
        case .xtream:
            return try await loadXtream(config: config)
        }
    }

    func parseM3U(_ content: String) -> [IptvChannel] {
        var channels: [IptvChannel] = []
        var pendingName = "Channel"
        var pendingGroup: String?
        var pendingLogo: String?
        var pendingTvg: String?
        var index = 0

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#EXTINF:") {
                pendingGroup = attr(trimmed, "group-title")
                pendingLogo = attr(trimmed, "tvg-logo")
                pendingTvg = attr(trimmed, "tvg-id")
                if let comma = trimmed.lastIndex(of: ",") {
                    pendingName = String(trimmed[trimmed.index(after: comma)...])
                        .trimmingCharacters(in: .whitespaces)
                }
            } else if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                index += 1
                channels.append(
                    IptvChannel(
                        id: "m3u-\(index)",
                        name: pendingName,
                        url: trimmed,
                        group: pendingGroup,
                        logoURL: pendingLogo,
                        tvgId: pendingTvg
                    )
                )
            }
        }
        return channels
    }

    private func loadXtream(config: IptvConfig) async throws -> [IptvChannel] {
        guard let host = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let user = config.xtreamUsername,
              let pass = config.xtreamPassword else {
            throw IptvError.invalidConfig
        }
        var base = host
        if !base.hasPrefix("http") { base = "http://\(base)" }

        // Categories
        let catURL = URL(string: "\(base)/player_api.php?username=\(user)&password=\(pass)&action=get_live_categories")!
        let (catData, _) = try await session.data(from: catURL)
        var categories: [String: String] = [:]
        if let arr = try? JSONSerialization.jsonObject(with: catData) as? [[String: Any]] {
            for c in arr {
                if let id = c["category_id"] as? String ?? (c["category_id"] as? Int).map(String.init),
                   let name = c["category_name"] as? String {
                    categories[id] = name
                }
            }
        }

        let streamsURL = URL(string: "\(base)/player_api.php?username=\(user)&password=\(pass)&action=get_live_streams")!
        let (data, _) = try await session.data(from: streamsURL)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var channels: [IptvChannel] = []
        for s in arr {
            let streamId = s["stream_id"] as? Int ?? Int("\(s["stream_id"] ?? "")") ?? 0
            let name = s["name"] as? String ?? "Stream \(streamId)"
            let catId = "\(s["category_id"] ?? "")"
            let group = categories[catId]
            let logo = s["stream_icon"] as? String
            // Prefer HLS container for iOS AVPlayer
            let url = "\(base)/live/\(user)/\(pass)/\(streamId).m3u8"
            channels.append(
                IptvChannel(
                    id: "xtream-\(streamId)",
                    name: name,
                    url: url,
                    group: group,
                    logoURL: logo
                )
            )
        }
        return channels
    }

    private func attr(_ line: String, _ key: String) -> String? {
        // group-title="Sports"
        let pattern = "\(key)=\"([^\"]*)\""
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let m = re.firstMatch(in: line, range: range),
              let r = Range(m.range(at: 1), in: line) else { return nil }
        return String(line[r])
    }
}

enum IptvError: LocalizedError {
    case invalidConfig
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfig: return "Invalid IPTV configuration"
        case .loadFailed(let m): return m
        }
    }
}
