import Foundation
import zlib

/// Memory-safe EPG loader.
/// Prefers **one bulk XMLTV download**, written to a temp file and parsed with a **streaming**
/// `XMLParser` so the full guide never sits in RAM as a giant String + regex match set.
actor EpgService {
    private let session: URLSession

    /// Max programmes retained per channel (now-focused window).
    static let maxProgramsPerChannel = 12
    /// Hours after "now" to keep (plus 1h before).
    static let windowHoursAhead = 18
    static let windowHoursBehind = 1

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 90
            cfg.timeoutIntervalForResource = 180
            cfg.httpMaximumConnectionsPerHost = 8
            cfg.httpAdditionalHeaders = [
                "Accept": "*/*",
                "Accept-Encoding": "gzip, deflate",
                "User-Agent": "SportsDash/1.0",
            ]
            // Avoid caching multi‑hundred‑MB XMLTV in URLCache.
            cfg.urlCache = nil
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: cfg)
        }
    }

    /// Load EPG for channels (bulk XMLTV first, short EPG only as limited fallback).
    func loadForChannels(
        channels: [IptvChannel],
        config: IptvConfig?,
        limitPerChannel: Int = maxProgramsPerChannel,
        batchSize: Int = 12,
        preferBulk: Bool = true,
        fillMissingWithShortEpg: Bool = false,
        onBatch: (@MainActor ([String: [EpgProgram]]) -> Void)? = nil,
        onStatus: (@MainActor (String) -> Void)? = nil
    ) async -> [String: [EpgProgram]] {
        guard !channels.isEmpty else { return [:] }

        // Keys we accept from XMLTV (keeps the parser from storing unrelated channels).
        let interest = Self.interestKeys(for: channels)
        var result: [String: [EpgProgram]] = [:]

        if preferBulk {
            if let config, config.type == .xtream, config.isConfigured {
                await status(onStatus, "Downloading guide (streaming)…")
                if let byTvg = await loadXtreamXmltv(config: config, interestKeys: interest, onStatus: onStatus) {
                    result = mapXmltv(byTvg, to: channels, limit: limitPerChannel)
                    let hit = result.count
                    await status(onStatus, "Guide ready · \(hit) channels")
                    if let onBatch { await MainActor.run { onBatch(result) } }
                    if !fillMissingWithShortEpg || hit > max(20, channels.count / 10) {
                        return result
                    }
                } else {
                    await status(onStatus, "Bulk guide unavailable — loading current category…")
                }
            } else if let config, config.type == .m3u,
                      let xmltvURL = await discoverM3UXmltvURL(config: config) {
                await status(onStatus, "Downloading XMLTV…")
                if let byTvg = await downloadAndStreamParse(
                    urlString: xmltvURL,
                    interestKeys: interest,
                    onStatus: onStatus
                ) {
                    result = mapXmltv(byTvg, to: channels, limit: limitPerChannel)
                    if let onBatch { await MainActor.run { onBatch(result) } }
                    return result
                }
            }
        }

        // Short EPG only for gaps, hard-capped to avoid memory + API storms.
        let need = channels.filter { result[$0.id] == nil }.prefix(80)
        guard !need.isEmpty,
              let config,
              config.type == .xtream,
              config.isConfigured else {
            return result
        }

        await status(onStatus, "Loading short EPG (\(need.count) channels)…")
        let short = await loadXtreamShortBatch(
            channels: Array(need),
            config: config,
            limit: min(limitPerChannel, 8),
            batchSize: batchSize,
            onBatch: { batch in
                if let onBatch { await MainActor.run { onBatch(batch) } }
            }
        )
        for (k, v) in short where !v.isEmpty {
            result[k] = v
        }
        return result
    }

    // MARK: - Bulk XMLTV (download → temp file → stream parse)

    private func loadXtreamXmltv(
        config: IptvConfig,
        interestKeys: Set<String>,
        onStatus: (@MainActor (String) -> Void)?
    ) async -> [String: [EpgProgram]]? {
        guard let rawHost = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let user = config.xtreamUsername,
              let pass = config.xtreamPassword else { return nil }
        let host = rawHost.hasPrefix("http") ? rawHost : "http://\(rawHost)"
        let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass

        let candidates = [
            "\(host)/xmltv.php?username=\(userQ)&password=\(passQ)",
            "\(host)/xmltv.php?username=\(userQ)&password=\(passQ)&type=m3u_plus",
        ]
        for url in candidates {
            if let map = await downloadAndStreamParse(
                urlString: url,
                interestKeys: interestKeys,
                onStatus: onStatus
            ), !map.isEmpty {
                return map
            }
        }
        return nil
    }

    private func downloadAndStreamParse(
        urlString: String,
        interestKeys: Set<String>,
        onStatus: (@MainActor (String) -> Void)?
    ) async -> [String: [EpgProgram]]? {
        guard let url = URL(string: urlString) else { return nil }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sportsdash-epg-\(UUID().uuidString).xml")

        do {
            let (tempURL, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            // Move into our temp path; gunzip if needed into a second file.
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.moveItem(at: tempURL, to: temp)

            let parseURL: URL
            if Self.fileLooksGzipped(temp) {
                await status(onStatus, "Decompressing guide…")
                let plain = temp.deletingPathExtension().appendingPathExtension("plain.xml")
                guard let data = try? Data(contentsOf: temp, options: [.mappedIfSafe]),
                      let inflated = Self.gunzip(data) else {
                    try? FileManager.default.removeItem(at: temp)
                    return nil
                }
                // Write inflated file in chunks already done — still one buffer for gunzip.
                // Cap inflated size to protect devices (~80MB plain XML max).
                guard inflated.count < 80 * 1024 * 1024 else {
                    try? FileManager.default.removeItem(at: temp)
                    await status(onStatus, "Guide file too large for device")
                    return nil
                }
                try inflated.write(to: plain, options: .atomic)
                try? FileManager.default.removeItem(at: temp)
                parseURL = plain
            } else {
                // Cap raw size too.
                let attrs = try FileManager.default.attributesOfItem(atPath: temp.path)
                let size = attrs[.size] as? NSNumber
                if let size, size.intValue > 80 * 1024 * 1024 {
                    try? FileManager.default.removeItem(at: temp)
                    await status(onStatus, "Guide file too large for device")
                    return nil
                }
                parseURL = temp
            }

            await status(onStatus, "Parsing guide…")
            let map = await Task.detached(priority: .utility) {
                StreamingXMLTVParser.parse(
                    fileURL: parseURL,
                    interestKeys: interestKeys,
                    maxPerChannel: EpgService.maxProgramsPerChannel,
                    hoursBehind: EpgService.windowHoursBehind,
                    hoursAhead: EpgService.windowHoursAhead
                )
            }.value

            try? FileManager.default.removeItem(at: parseURL)
            return map
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
    }

    // MARK: - Map XMLTV ids → app channel ids (non-empty only)

    private func mapXmltv(
        _ byTvg: [String: [EpgProgram]],
        to channels: [IptvChannel],
        limit: Int
    ) -> [String: [EpgProgram]] {
        var lowerIndex: [String: String] = [:]
        lowerIndex.reserveCapacity(byTvg.count)
        for key in byTvg.keys {
            lowerIndex[key.lowercased()] = key
        }

        var result: [String: [EpgProgram]] = [:]
        for ch in channels {
            let candidates = [
                ch.epgChannelId,
                ch.tvgId,
                Self.xtreamStreamId(ch),
            ].compactMap { $0 }.filter { !$0.isEmpty }

            var programs: [EpgProgram] = []
            for k in candidates {
                if let list = byTvg[k] {
                    programs = list
                    break
                }
                if let real = lowerIndex[k.lowercased()], let list = byTvg[real] {
                    programs = list
                    break
                }
            }
            guard !programs.isEmpty else { continue }
            let capped = Array(programs.prefix(limit))
            result[ch.id] = capped.map {
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
            if let sid = xtreamStreamId(ch) {
                keys.insert(sid)
            }
        }
        return keys
    }

    // MARK: - Short EPG fallback

    private func loadXtreamShortBatch(
        channels: [IptvChannel],
        config: IptvConfig,
        limit: Int,
        batchSize: Int,
        onBatch: (([String: [EpgProgram]]) async -> Void)?
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
            var batch: [String: [EpgProgram]] = [:]
            await withTaskGroup(of: (String, [EpgProgram]).self) { group in
                for ch in slice {
                    group.addTask {
                        guard let streamId = Self.xtreamStreamId(ch) else {
                            return (ch.id, [])
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
                            return (ch.id, programs)
                        } catch {
                            return (ch.id, [])
                        }
                    }
                }
                for await (id, programs) in group where !programs.isEmpty {
                    batch[id] = programs
                    result[id] = programs
                }
            }
            if let onBatch, !batch.isEmpty { await onBatch(batch) }
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
        // Reject huge unexpected payloads.
        guard data.count < 512_000 else { return [] }

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
            let start = Self.parseEpgDate(
                item["start_timestamp"] as? String ?? item["start"] as? String
            )
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

    // MARK: - M3U url-tvg

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
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Helpers

    private func status(
        _ onStatus: (@MainActor (String) -> Void)?,
        _ message: String
    ) async {
        guard let onStatus else { return }
        await MainActor.run { onStatus(message) }
    }

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
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            return str
        }
        let padded = s.padding(toLength: ((s.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        if let data = Data(base64Encoded: padded),
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
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

    nonisolated private static func fileLooksGzipped(_ url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let head = try? fh.read(upToCount: 2)
        guard let head, head.count == 2 else { return false }
        return head[0] == 0x1f && head[1] == 0x8b
    }

    nonisolated private static func gunzip(_ data: Data) -> Data? {
        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: base)
            stream.avail_in = uInt(data.count)
            guard inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                return nil
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            output.reserveCapacity(min(data.count * 4, 16 * 1024 * 1024))
            let chunk = 64 * 1024
            var buffer = [UInt8](repeating: 0, count: chunk)
            var status: Int32 = Z_OK
            while status == Z_OK {
                if output.count > 80 * 1024 * 1024 { return nil } // hard stop
                stream.next_out = UnsafeMutablePointer(&buffer)
                stream.avail_out = uInt(chunk)
                status = inflate(&stream, Z_NO_FLUSH)
                let produced = chunk - Int(stream.avail_out)
                if produced > 0 { output.append(buffer, count: produced) }
                if status == Z_STREAM_END { break }
                if status != Z_OK { return nil }
            }
            return output
        }
    }
}

// MARK: - Streaming XMLTV parser (low memory)

/// SAX-style parser: only programmes for `interestKeys` in a time window are kept.
final class StreamingXMLTVParser: NSObject, XMLParserDelegate {
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
    private var inProgramme = false
    private var captureTitle = false

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
        let delegate = StreamingXMLTVParser(
            interestKeys: interestKeys,
            maxPerChannel: maxPerChannel,
            hoursBehind: hoursBehind,
            hoursAhead: hoursAhead
        )
        guard let parser = XMLParser(contentsOf: fileURL) else { return [:] }
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.parse()
        // Sort + hard-cap each channel
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
            currentText = ""
            currentChannel = attributeDict["channel"]
            currentStart = Self.parseXmltvTime(attributeDict["start"])
            currentEnd = Self.parseXmltvTime(attributeDict["stop"])
        } else if inProgramme, name == "title" {
            captureTitle = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureTitle { currentText.append(string) }
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
        } else if name == "programme" {
            defer {
                inProgramme = false
                currentChannel = nil
                currentStart = nil
                currentEnd = nil
                currentTitle = nil
            }
            guard let channel = currentChannel,
                  let start = currentStart,
                  let end = currentEnd,
                  end > windowStart,
                  start < windowEnd else { return }

            // Only keep channels we actually have in the playlist.
            let interested = interestKeys.isEmpty
                || interestKeys.contains(channel)
                || interestKeys.contains(channel.lowercased())
            guard interested else { return }

            var list = map[channel] ?? []
            // Skip if already full for this channel.
            guard list.count < maxPerChannel else { return }

            list.append(
                EpgProgram(
                    channelKey: channel,
                    title: (currentTitle?.isEmpty == false ? currentTitle! : "Program"),
                    start: start,
                    end: end,
                    description: nil
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

        var calendar = Calendar(identifier: .gregorian)
        // Default UTC; adjust if offset present.
        var secondsFromGMT = 0
        if let plus = trimmed.range(of: "+", options: .backwards)
            ?? trimmed.range(of: "-", options: .backwards, range: trimmed.index(trimmed.startIndex, offsetBy: 14)..<trimmed.endIndex) {
            let sign: Int = trimmed[plus.lowerBound] == "+" ? 1 : -1
            let off = trimmed[plus.upperBound...]
            let digits = off.filter(\.isNumber)
            if digits.count >= 4 {
                let hh = Int(digits.prefix(2)) ?? 0
                let mm = Int(digits.dropFirst(2).prefix(2)) ?? 0
                secondsFromGMT = sign * (hh * 3600 + mm * 60)
            }
        }
        calendar.timeZone = TimeZone(secondsFromGMT: secondsFromGMT) ?? .gmt
        return calendar.date(from: DateComponents(
            year: y, month: mo, day: d, hour: h, minute: mi, second: s
        ))
    }
}
