import Foundation

/// Disk-first EPG loader (what keeps other IPTV apps responsive).
///
/// **Pipeline**
/// 1. `URLSession.download` → temp file on disk (not held in RAM)
/// 2. Background `XMLParser` over the file (SAX / streaming)
/// 3. Keep only playlist channels + short time window + max programmes / channel
/// 4. Hand a compact dictionary back to the UI **once** (or rare status ticks)
///
/// Avoids: full-file `String`, regex over multi‑MB XML, byte-by-byte MainActor work.
actor EpgService {
    private let session: URLSession

    static let maxProgramsPerChannel = 12
    static let windowHoursAhead = 18
    static let windowHoursBehind = 1
    /// Refuse downloads larger than this (protects device storage + parse time).
    static let maxDownloadBytes = 120 * 1024 * 1024

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 120
            cfg.timeoutIntervalForResource = 300
            cfg.httpMaximumConnectionsPerHost = 4
            // Let URLSession negotiate gzip and write **decoded** body to the temp file.
            cfg.httpAdditionalHeaders = [
                "Accept": "application/xml, text/xml, */*",
                "User-Agent": "SportsDash/1.0",
            ]
            cfg.urlCache = nil
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: cfg)
        }
    }

    /// Load EPG for channels. Heavy work never touches the main actor.
    ///
    /// - `onStatus`: rare progress strings (download % / parse)
    /// - `onBatch`: optional mid-parse updates (throttled by caller); final map is returned
    func loadForChannels(
        channels: [IptvChannel],
        config: IptvConfig?,
        limitPerChannel: Int = maxProgramsPerChannel,
        batchSize: Int = 12,
        preferBulk: Bool = true,
        fillMissingWithShortEpg: Bool = false,
        onBatch: (@Sendable ([String: [EpgProgram]]) -> Void)? = nil,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async -> [String: [EpgProgram]] {
        guard !channels.isEmpty else { return [:] }

        let interest = Self.interestKeys(for: channels)
        var result: [String: [EpgProgram]] = [:]

        if preferBulk {
            let urls = await bulkURLs(config: config)
            for (index, urlString) in urls.enumerated() {
                onStatus?("Downloading guide… (\(index + 1)/\(urls.count))")
                if let byTvg = await downloadToDiskAndParse(
                    urlString: urlString,
                    interestKeys: interest,
                    limitPerChannel: limitPerChannel,
                    onStatus: onStatus
                ), !byTvg.isEmpty {
                    result = mapXmltv(byTvg, to: channels, limit: limitPerChannel)
                    onStatus?("Guide ready · \(result.count) channels")
                    onBatch?(result)
                    if !fillMissingWithShortEpg || result.count > max(20, channels.count / 10) {
                        return result
                    }
                    break
                }
            }
            if result.isEmpty {
                onStatus?("Bulk guide unavailable — short EPG for open category…")
            }
        }

        // Short EPG only for a small gap set (never full playlist).
        let need = Array(channels.filter { result[$0.id] == nil }.prefix(80))
        guard !need.isEmpty,
              let config,
              config.type == .xtream,
              config.isConfigured else {
            return result
        }

        onStatus?("Loading short EPG (\(need.count) channels)…")
        let short = await loadXtreamShortBatch(
            channels: need,
            config: config,
            limit: min(limitPerChannel, 8),
            batchSize: batchSize
        )
        for (k, v) in short where !v.isEmpty {
            result[k] = v
        }
        if !short.isEmpty {
            onBatch?(short)
        }
        return result
    }

    // MARK: - Download to disk → SAX parse (primary path)

    private func downloadToDiskAndParse(
        urlString: String,
        interestKeys: Set<String>,
        limitPerChannel: Int,
        onStatus: (@Sendable (String) -> Void)?
    ) async -> [String: [EpgProgram]]? {
        guard let url = URL(string: urlString) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let dest = tempDir.appendingPathComponent("sportsdash-epg-\(UUID().uuidString).xml")

        do {
            // Streams response body straight to a temp file — OS handles buffering.
            let (fileURL, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: fileURL, to: dest)

            let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            if size <= 0 || size > Self.maxDownloadBytes {
                try? FileManager.default.removeItem(at: dest)
                onStatus?(size > Self.maxDownloadBytes
                    ? "Guide file too large for this device"
                    : "Empty guide file")
                return nil
            }

            let mb = Double(size) / 1_048_576
            onStatus?(String(format: "Downloaded %.1f MB — parsing on disk…", mb))

            // Parse off the EpgService actor executor (true background).
            let map = await Task.detached(priority: .utility) {
                DiskXMLTVParser.parse(
                    fileURL: dest,
                    interestKeys: interestKeys,
                    maxPerChannel: limitPerChannel,
                    hoursBehind: EpgService.windowHoursBehind,
                    hoursAhead: EpgService.windowHoursAhead
                )
            }.value

            try? FileManager.default.removeItem(at: dest)
            return map.isEmpty ? nil : map
        } catch {
            try? FileManager.default.removeItem(at: dest)
            return nil
        }
    }

    // MARK: - URLs

    private func bulkURLs(config: IptvConfig?) async -> [String] {
        var urls: [String] = []
        guard let config else { return urls }

        if config.type == .m3u, let tvg = await discoverM3UXmltvURL(config: config) {
            urls.append(tvg)
        }

        if config.type == .xtream, config.isConfigured,
           let rawHost = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
           let user = config.xtreamUsername,
           let pass = config.xtreamPassword {
            let host = rawHost.hasPrefix("http") ? rawHost : "http://\(rawHost)"
            let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
            let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass
            urls.append(contentsOf: [
                "\(host)/xmltv.php?username=\(userQ)&password=\(passQ)",
                "\(host)/xmltv.php?username=\(userQ)&password=\(passQ)&type=m3u_plus",
            ])
        }
        return urls
    }

    private func discoverM3UXmltvURL(config: IptvConfig) async -> String? {
        guard let raw = config.m3uURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw) else { return nil }
        do {
            var req = URLRequest(url: url)
            req.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
            let (data, _) = try await session.data(for: req)
            let text = String(data: data, encoding: .utf8) ?? ""
            for pattern in [#"url-tvg="([^"]+)""#, #"x-tvg-url="([^"]+)""#] {
                if let re = try? NSRegularExpression(pattern: pattern),
                   let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let r = Range(m.range(at: 1), in: text) {
                    return String(text[r])
                }
            }
        } catch { return nil }
        return nil
    }

    // MARK: - Map XMLTV channel id → app channel id

    private func mapXmltv(
        _ byTvg: [String: [EpgProgram]],
        to channels: [IptvChannel],
        limit: Int
    ) -> [String: [EpgProgram]] {
        var lowerIndex: [String: String] = [:]
        lowerIndex.reserveCapacity(byTvg.count)
        for key in byTvg.keys { lowerIndex[key.lowercased()] = key }

        var result: [String: [EpgProgram]] = [:]
        result.reserveCapacity(min(channels.count, byTvg.count))

        for ch in channels {
            let candidates = [ch.epgChannelId, ch.tvgId, Self.xtreamStreamId(ch)]
                .compactMap { $0 }
                .filter { !$0.isEmpty }

            var programs: [EpgProgram] = []
            for k in candidates {
                if let list = byTvg[k] { programs = list; break }
                if let real = lowerIndex[k.lowercased()], let list = byTvg[real] {
                    programs = list
                    break
                }
            }
            guard !programs.isEmpty else { continue }
            result[ch.id] = Array(programs.prefix(limit)).map {
                EpgProgram(
                    channelKey: ch.id,
                    title: $0.title,
                    start: $0.start,
                    end: $0.end,
                    description: $0.description
                )
            }
        }
        return result
    }

    nonisolated private static func interestKeys(for channels: [IptvChannel]) -> Set<String> {
        var keys = Set<String>()
        keys.reserveCapacity(channels.count * 2)
        for ch in channels {
            if let e = ch.epgChannelId, !e.isEmpty {
                keys.insert(e)
                keys.insert(e.lowercased())
            }
            if let t = ch.tvgId, !t.isEmpty {
                keys.insert(t)
                keys.insert(t.lowercased())
            }
            if let sid = xtreamStreamId(ch) { keys.insert(sid) }
        }
        return keys
    }

    // MARK: - Short EPG fallback (bounded)

    private func loadXtreamShortBatch(
        channels: [IptvChannel],
        config: IptvConfig,
        limit: Int,
        batchSize: Int
    ) async -> [String: [EpgProgram]] {
        guard let rawHost = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let user = config.xtreamUsername,
              let pass = config.xtreamPassword else { return [:] }
        let host = rawHost.hasPrefix("http") ? rawHost : "http://\(rawHost)"
        let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass

        var result: [String: [EpgProgram]] = [:]
        var i = 0
        while i < channels.count {
            let end = min(i + batchSize, channels.count)
            let slice = Array(channels[i..<end])
            await withTaskGroup(of: (String, [EpgProgram]).self) { group in
                for ch in slice {
                    group.addTask {
                        guard let streamId = Self.xtreamStreamId(ch) else {
                            return (ch.id, [])
                        }
                        do {
                            let programs = try await self.fetchShortEpg(
                                host: host, userQ: userQ, passQ: passQ,
                                streamId: streamId, limit: limit, channelKey: ch.id
                            )
                            return (ch.id, programs)
                        } catch {
                            return (ch.id, [])
                        }
                    }
                }
                for await (id, programs) in group where !programs.isEmpty {
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
        guard data.count < 256_000 else { return [] }

        let obj = try JSONSerialization.jsonObject(with: data)
        let listings: [[String: Any]]
        if let map = obj as? [String: Any], let list = map["epg_listings"] as? [[String: Any]] {
            listings = list
        } else if let list = obj as? [[String: Any]] {
            listings = list
        } else {
            return []
        }

        return listings.prefix(limit).compactMap { item -> EpgProgram? in
            let title = Self.decodeBase64Maybe(item["title"] as? String) ?? "Program"
            let start = Self.parseEpgDate(item["start_timestamp"] as? String ?? item["start"] as? String)
            let end = Self.parseEpgDate(
                item["end_timestamp"] as? String
                    ?? item["stop_timestamp"] as? String
                    ?? item["stop"] as? String
                    ?? item["end"] as? String
            )
            guard let start, let end, end > start else { return nil }
            return EpgProgram(
                channelKey: channelKey,
                title: title,
                start: start,
                end: end,
                description: Self.decodeBase64Maybe(item["description"] as? String)
            )
        }
        .sorted { $0.start < $1.start }
    }

    // MARK: - Helpers

    nonisolated static func xtreamStreamId(_ ch: IptvChannel) -> String? {
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

    nonisolated private static func decodeBase64Maybe(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        if let data = Data(base64Encoded: s),
           let str = String(data: data, encoding: .utf8), !str.isEmpty {
            return str
        }
        let padded = s.padding(toLength: ((s.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        if let data = Data(base64Encoded: padded),
           let str = String(data: data, encoding: .utf8), !str.isEmpty {
            return str
        }
        return s
    }

    nonisolated private static func parseEpgDate(_ raw: String?) -> Date? {
        guard var raw, !raw.isEmpty else { return nil }
        if let decoded = decodeBase64Maybe(raw), decoded != raw { raw = decoded }
        if let ts = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            if ts > 1_000_000_000_000 { return Date(timeIntervalSince1970: ts / 1000) }
            if ts > 1_000_000_000 { return Date(timeIntervalSince1970: ts) }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: raw)
    }
}

// MARK: - Disk SAX parser (low RAM)

/// Streams the XMLTV **file** with Foundation's `XMLParser` — never loads the full document as a String.
final class DiskXMLTVParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private let interestKeys: Set<String>
    private let maxPerChannel: Int
    private let windowStart: Date
    private let windowEnd: Date

    private var map: [String: [EpgProgram]] = [:]
    private var currentChannel: String?
    private var currentStart: Date?
    private var currentEnd: Date?
    private var currentText = ""
    private var currentTitle: String?
    private var currentCategories: [String] = []
    private var inProgramme = false
    private var captureTitle = false
    private var captureCategory = false

    private init(
        interestKeys: Set<String>,
        maxPerChannel: Int,
        hoursBehind: Int,
        hoursAhead: Int
    ) {
        self.interestKeys = interestKeys
        self.maxPerChannel = maxPerChannel
        let now = Date()
        self.windowStart = now.addingTimeInterval(TimeInterval(-hoursBehind) * 3600)
        self.windowEnd = now.addingTimeInterval(TimeInterval(hoursAhead) * 3600)
        super.init()
    }

    static func parse(
        fileURL: URL,
        interestKeys: Set<String>,
        maxPerChannel: Int,
        hoursBehind: Int,
        hoursAhead: Int
    ) -> [String: [EpgProgram]] {
        let delegate = DiskXMLTVParser(
            interestKeys: interestKeys,
            maxPerChannel: maxPerChannel,
            hoursBehind: hoursBehind,
            hoursAhead: hoursAhead
        )
        // XMLParser streams from the file path; peak RAM ≈ parser state, not file size.
        guard let parser = XMLParser(contentsOf: fileURL) else { return [:] }
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.parse()

        for key in delegate.map.keys {
            var list = delegate.map[key] ?? []
            list.sort { $0.start < $1.start }
            if list.count > maxPerChannel {
                list = Array(list.prefix(maxPerChannel))
            }
            delegate.map[key] = list
        }
        return delegate.map
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        if name == "programme" {
            inProgramme = true
            currentTitle = nil
            currentCategories = []
            currentText = ""
            currentChannel = attributeDict["channel"]
            currentStart = Self.parseXmltvTime(attributeDict["start"])
            currentEnd = Self.parseXmltvTime(attributeDict["stop"])
        } else if inProgramme, name == "title" {
            captureTitle = true
            currentText = ""
        } else if inProgramme, name == "category" {
            captureCategory = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureTitle || captureCategory {
            // Titles/categories are short; hard-cap to avoid pathological payloads.
            if currentText.count < 200 {
                currentText.append(string)
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        let name = elementName.lowercased()
        if name == "title", captureTitle {
            currentTitle = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            captureTitle = false
            currentText = ""
        } else if name == "category", captureCategory {
            let cat = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cat.isEmpty, currentCategories.count < 8 {
                currentCategories.append(cat)
            }
            captureCategory = false
            currentText = ""
        } else if name == "programme" {
            defer {
                inProgramme = false
                currentChannel = nil
                currentStart = nil
                currentEnd = nil
                currentTitle = nil
                currentCategories = []
            }
            guard let channel = currentChannel,
                  let start = currentStart,
                  let end = currentEnd,
                  end > windowStart,
                  start < windowEnd else { return }

            let interested = interestKeys.isEmpty
                || interestKeys.contains(channel)
                || interestKeys.contains(channel.lowercased())
            guard interested else { return }

            var list = map[channel] ?? []
            guard list.count < maxPerChannel else { return }
            list.append(
                EpgProgram(
                    channelKey: channel,
                    title: (currentTitle?.isEmpty == false ? currentTitle! : "Program"),
                    start: start,
                    end: end,
                    description: nil,
                    categories: currentCategories
                )
            )
            map[channel] = list
        }
    }

    private static func parseXmltvTime(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 14 else { return nil }
        let y = Int(trimmed.prefix(4)) ?? 0
        let mo = Int(trimmed.dropFirst(4).prefix(2)) ?? 0
        let d = Int(trimmed.dropFirst(6).prefix(2)) ?? 0
        let h = Int(trimmed.dropFirst(8).prefix(2)) ?? 0
        let mi = Int(trimmed.dropFirst(10).prefix(2)) ?? 0
        let s = Int(trimmed.dropFirst(12).prefix(2)) ?? 0

        var secondsFromGMT = 0
        if trimmed.count > 15 {
            let tail = trimmed.dropFirst(14)
            if let idx = tail.firstIndex(where: { $0 == "+" || $0 == "-" }) {
                let sign: Int = tail[idx] == "+" ? 1 : -1
                let digits = tail[idx...].filter(\.isNumber)
                if digits.count >= 4 {
                    let hh = Int(digits.prefix(2)) ?? 0
                    let mm = Int(digits.dropFirst(2).prefix(2)) ?? 0
                    secondsFromGMT = sign * (hh * 3600 + mm * 60)
                }
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: secondsFromGMT) ?? .gmt
        return calendar.date(from: DateComponents(
            year: y, month: mo, day: d, hour: h, minute: mi, second: s
        ))
    }
}
