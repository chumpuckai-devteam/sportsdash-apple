import Foundation

actor EpgService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadForChannels(
        channels: [IptvChannel],
        config: IptvConfig?,
        limitPerChannel: Int = 6
    ) async -> [String: [EpgProgram]] {
        guard !channels.isEmpty else { return [:] }

        if let config, config.type == .xtream, config.isConfigured {
            return await loadXtreamBatch(
                channels: channels,
                config: config,
                limit: limitPerChannel
            )
        }

        var result: [String: [EpgProgram]] = [:]
        for ch in channels {
            result[ch.id] = demoPrograms(for: ch)
        }
        return result
    }

    private func loadXtreamBatch(
        channels: [IptvChannel],
        config: IptvConfig,
        limit: Int
    ) async -> [String: [EpgProgram]] {
        guard var host = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let user = config.xtreamUsername,
              let pass = config.xtreamPassword else { return [:] }
        if !host.hasPrefix("http") { host = "http://\(host)" }

        let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass

        var result: [String: [EpgProgram]] = [:]
        let batchSize = 6
        var i = 0
        while i < channels.count {
            let end = min(i + batchSize, channels.count)
            let slice = Array(channels[i..<end])
            await withTaskGroup(of: (String, [EpgProgram]).self) { group in
                for ch in slice {
                    group.addTask {
                        guard let streamId = Self.xtreamStreamId(ch) else {
                            return (ch.id, self.demoPrograms(for: ch))
                        }
                        do {
                            let programs = try await self.fetchShortEpg(
                                host: host,
                                userQ: userQ,
                                passQ: passQ,
                                streamId: streamId,
                                limit: limit,
                                channelKey: ch.id
                            )
                            return (ch.id, programs.isEmpty ? self.demoPrograms(for: ch) : programs)
                        } catch {
                            return (ch.id, [])
                        }
                    }
                }
                for await (id, programs) in group {
                    result[id] = programs
                }
            }
            i = end
        }
        return result
    }

    private func fetchShortEpg(
        host: String,
        userQ: String,
        passQ: String,
        streamId: String,
        limit: Int,
        channelKey: String
    ) async throws -> [EpgProgram] {
        let url = URL(string:
            "\(host)/player_api.php?username=\(userQ)&password=\(passQ)"
            + "&action=get_short_epg&stream_id=\(streamId)&limit=\(limit)"
        )!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

        let obj = try JSONSerialization.jsonObject(with: data)
        let listings: [[String: Any]]
        if let map = obj as? [String: Any], let list = map["epg_listings"] as? [[String: Any]] {
            listings = list
        } else if let list = obj as? [[String: Any]] {
            listings = list
        } else {
            return []
        }

        return listings.compactMap { item -> EpgProgram? in
            let title = decodeBase64Maybe(item["title"] as? String) ?? "Program"
            let start = parseEpgDate(item["start"] as? String ?? item["start_timestamp"] as? String)
            let end = parseEpgDate(item["end"] as? String ?? item["stop"] as? String ?? item["end_timestamp"] as? String)
            guard let start, let end else { return nil }
            let desc = decodeBase64Maybe(item["description"] as? String)
            return EpgProgram(
                channelKey: channelKey,
                title: title,
                start: start,
                end: end,
                description: desc
            )
        }
    }

    nonisolated private func demoPrograms(for channel: IptvChannel) -> [EpgProgram] {
        let now = Date()
        return [
            EpgProgram(
                channelKey: channel.id,
                title: "Live: \(channel.name)",
                start: now.addingTimeInterval(-1800),
                end: now.addingTimeInterval(3600),
                description: nil
            ),
        ]
    }

    nonisolated static func xtreamStreamId(_ ch: IptvChannel) -> String? {
        // xtream-12345 or .../live/u/p/12345.m3u8
        if ch.id.hasPrefix("xtream-") {
            return String(ch.id.dropFirst("xtream-".count))
        }
        let parts = ch.url.split(separator: "/")
        if let last = parts.last {
            let id = last.replacingOccurrences(of: ".m3u8", with: "")
                .replacingOccurrences(of: ".ts", with: "")
            if Int(id) != nil { return id }
        }
        return nil
    }

    nonisolated private func decodeBase64Maybe(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        if let data = Data(base64Encoded: s), let str = String(data: data, encoding: .utf8), !str.isEmpty {
            return str
        }
        return s
    }

    nonisolated private func parseEpgDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let ts = TimeInterval(raw) {
            // Xtream often uses seconds
            if ts > 1_000_000_000_000 { return Date(timeIntervalSince1970: ts / 1000) }
            return Date(timeIntervalSince1970: ts)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = f.date(from: raw) { return d }
        f.dateFormat = "yyyyMMddHHmmss Z"
        return f.date(from: raw)
    }
}
