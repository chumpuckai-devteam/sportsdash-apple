import Foundation

/// M3U / Xtream loaders — parity with Flutter `IptvService`.
actor IptvService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadChannels(config: IptvConfig) async throws -> [IptvChannel] {
        switch config.type {
        case .m3u:
            guard let raw = config.m3uURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: raw) else {
                throw IptvError.invalidConfig
            }
            let (data, _) = try await session.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            return parseM3U(text)
        case .xtream:
            return try await loadXtream(config: config)
        }
    }

    /// Xtream account status: `player_api.php` with no action returns `user_info`.
    func fetchXtreamAccountInfo(config: IptvConfig) async throws -> XtreamAccountInfo {
        guard config.type == .xtream,
              let rawHost = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let user = config.xtreamUsername,
              let pass = config.xtreamPassword else {
            throw IptvError.invalidConfig
        }
        let host = rawHost.hasPrefix("http") ? rawHost : "http://\(rawHost)"
        let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass
        guard let url = URL(string: "\(host)/player_api.php?username=\(userQ)&password=\(passQ)") else {
            throw IptvError.invalidConfig
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw IptvError.loadFailed("Account check failed (\(http.statusCode))")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IptvError.loadFailed("Invalid account response")
        }
        let info = (root["user_info"] as? [String: Any]) ?? root
        return XtreamAccountInfo(
            username: info["username"] as? String ?? user,
            status: stringValue(info["status"]),
            expDate: parseUnixDate(info["exp_date"]),
            isTrial: boolish(info["is_trial"]),
            activeConnections: intValue(info["active_cons"]),
            maxConnections: intValue(info["max_connections"]),
            createdAt: parseUnixDate(info["created_at"]),
            message: stringValue(info["message"])
        )
    }

    private func stringValue(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let s = any as? String { return Int(s) }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    private func boolish(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let i = any as? Int { return i != 0 }
        if let s = any as? String {
            return s == "1" || s.lowercased() == "true" || s.lowercased() == "yes"
        }
        return false
    }

    private func parseUnixDate(_ any: Any?) -> Date? {
        if let s = any as? String, let t = TimeInterval(s), t > 0 {
            return Date(timeIntervalSince1970: t)
        }
        if let i = any as? Int, i > 0 {
            return Date(timeIntervalSince1970: TimeInterval(i))
        }
        if let n = any as? NSNumber, n.doubleValue > 0 {
            return Date(timeIntervalSince1970: n.doubleValue)
        }
        return nil
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
                        tvgId: pendingTvg,
                        epgChannelId: pendingTvg
                    )
                )
            }
        }
        return channels
    }

    private func loadXtream(config: IptvConfig) async throws -> [IptvChannel] {
        guard let rawHost = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let user = config.xtreamUsername,
              let pass = config.xtreamPassword else {
            throw IptvError.invalidConfig
        }
        // Immutable base URL — must not be a `var` captured by concurrent `async let` (Swift 6).
        let host = rawHost.hasPrefix("http") ? rawHost : "http://\(rawHost)"
        let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass
        let categoriesURL = URL(string: "\(host)/player_api.php?username=\(userQ)&password=\(passQ)&action=get_live_categories")!
        let streamsURL = URL(string: "\(host)/player_api.php?username=\(userQ)&password=\(passQ)&action=get_live_streams")!

        async let catDataTask = session.data(from: categoriesURL)
        async let streamsDataTask = session.data(from: streamsURL)

        let (catData, _) = try await catDataTask
        let (streamData, streamResp) = try await streamsDataTask
        if let http = streamResp as? HTTPURLResponse, http.statusCode != 200 {
            throw IptvError.loadFailed("Xtream live streams failed (\(http.statusCode))")
        }

        // Preserve provider category order
        var categories: [String: String] = [:]
        var categoryOrder: [String] = []
        if let arr = try? JSONSerialization.jsonObject(with: catData) as? [[String: Any]] {
            for c in arr {
                let id = "\(c["category_id"] ?? "")"
                let name = c["category_name"] as? String ?? "Other"
                if !id.isEmpty {
                    categories[id] = name
                    categoryOrder.append(id)
                }
            }
        }

        guard let arr = try JSONSerialization.jsonObject(with: streamData) as? [[String: Any]] else {
            throw IptvError.loadFailed("Invalid Xtream response — check credentials")
        }

        var byCategory: [String: [IptvChannel]] = [:]
        var uncategorized: [IptvChannel] = []

        // Encode path segments — passwords often contain @ : / etc.
        let userPath = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        let passPath = pass.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pass

        for s in arr {
            let streamId = s["stream_id"] as? Int ?? Int("\(s["stream_id"] ?? "")") ?? 0
            let name = s["name"] as? String ?? "Stream \(streamId)"
            let catId = "\(s["category_id"] ?? "")"
            let group = categories[catId]
            let logo = s["stream_icon"] as? String
            let epgId = s["epg_channel_id"] as? String
            // Prefer HLS for AVPlayer; fallback handled at play time
            let url = "\(host)/live/\(userPath)/\(passPath)/\(streamId).m3u8"
            let channel = IptvChannel(
                id: "xtream-\(streamId)",
                name: name,
                url: url,
                group: group ?? "Live",
                logoURL: logo,
                tvgId: epgId,
                epgChannelId: epgId
            )
            if group != nil {
                byCategory[catId, default: []].append(channel)
            } else {
                uncategorized.append(channel)
            }
        }

        var ordered: [IptvChannel] = []
        for catId in categoryOrder {
            ordered.append(contentsOf: byCategory[catId] ?? [])
        }
        ordered.append(contentsOf: uncategorized)
        return ordered
    }

    /// Alternate Xtream container (.m3u8 ↔ .ts) for playback fallback.
    nonisolated static func alternateXtreamContainer(_ url: String) -> String? {
        let candidates = playbackURLCandidates(from: url, preferredFormat: .ts)
        guard candidates.count > 1 else { return nil }
        return candidates.dropFirst().first
    }

    /// Ordered play attempts. Preferred format is tried first when the URL can be rewritten.
    nonisolated static func playbackURLCandidates(
        from url: String,
        preferredFormat: LiveStreamFormat = .ts
    ) -> [String] {
        var variants: [String] = []
        func add(_ u: String) {
            if !variants.contains(u) { variants.append(u) }
        }

        add(url)
        let lower = url.lowercased()

        if lower.contains(".m3u8") {
            add(url.replacingOccurrences(of: ".m3u8", with: ".ts", options: [.caseInsensitive, .backwards]))
            if let bare = url.range(of: ".m3u8", options: [.caseInsensitive, .backwards]) {
                add(String(url[..<bare.lowerBound]))
            }
        } else if lower.hasSuffix(".ts") || lower.contains(".ts?") {
            add(url.replacingOccurrences(of: ".ts", with: ".m3u8", options: [.caseInsensitive, .backwards]))
        } else if !lower.contains(".m3u8") && !lower.contains(".ts") && !lower.contains(".mp4") {
            if url.hasSuffix("/") {
                add(String(url.dropLast()) + ".m3u8")
                add(String(url.dropLast()) + ".ts")
            } else {
                add(url + ".m3u8")
                add(url + ".ts")
            }
        }

        // Prefer user-selected container at the front when present.
        let preferredExt = preferredFormat == .ts ? ".ts" : ".m3u8"
        let preferred = variants.filter { $0.lowercased().contains(preferredExt) }
        let rest = variants.filter { !$0.lowercased().contains(preferredExt) }
        return preferred + rest
    }

    private func attr(_ line: String, _ key: String) -> String? {
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
