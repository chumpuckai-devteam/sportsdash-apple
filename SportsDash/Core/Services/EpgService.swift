import Foundation

/// EPG loader: **download and parse at the same time** (true streaming).
///
/// Strategy used by fast IPTV apps:
/// 1. Open one bulk XMLTV URL (`xmltv.php` / M3U `url-tvg`)
/// 2. Read the HTTP body as a byte stream (URLSession decompresses gzip)
/// 3. Extract complete `<programme>…</programme>` blocks from a small rolling buffer
/// 4. Keep only playlist channels + a short time window (low memory)
/// 5. Push batches to the UI while the download is still running
actor EpgService {
    private let session: URLSession

    static let maxProgramsPerChannel = 12
    static let windowHoursAhead = 18
    static let windowHoursBehind = 1
    /// Max bytes kept for an incomplete trailing tag while streaming.
    private static let maxCarryBytes = 512 * 1024
    /// Flush UI at least this often while streaming.
    private static let flushInterval: TimeInterval = 0.35

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 120
            cfg.timeoutIntervalForResource = 300
            cfg.httpMaximumConnectionsPerHost = 6
            // Do NOT set Accept-Encoding manually — URLSession will negotiate gzip
            // and transparently decompress so we can stream plain XML.
            cfg.httpAdditionalHeaders = [
                "Accept": "application/xml, text/xml, */*",
                "User-Agent": "SportsDash/1.0",
            ]
            cfg.urlCache = nil
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: cfg)
        }
    }

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

        let interest = Self.interestKeys(for: channels)
        let keyToChannelId = Self.keyToChannelId(for: channels)
        var result: [String: [EpgProgram]] = [:]

        if preferBulk {
            var urls = bulkURLs(config: config)
            // M3U playlists often declare a bulk XMLTV URL in the header.
            if let config, config.type == .m3u,
               let tvg = await discoverM3UXmltvURL(config: config) {
                urls.insert(tvg, at: 0)
            }
            for urlString in urls {
                await status(onStatus, "Streaming guide…")
                if let streamed = await streamDownloadAndParse(
                    urlString: urlString,
                    interestKeys: interest,
                    keyToChannelId: keyToChannelId,
                    limitPerChannel: limitPerChannel,
                    onBatch: onBatch,
                    onStatus: onStatus
                ), !streamed.isEmpty {
                    result = streamed
                    await status(onStatus, "Guide ready · \(result.count) channels")
                    if !fillMissingWithShortEpg || result.count > max(20, channels.count / 10) {
                        return result
                    }
                    break
                }
            }
            if result.isEmpty {
                await status(onStatus, "Bulk stream failed — trying file parse…")
                // Fallback: download-to-disk + SAX (still lower peak than regex).
                if let config, config.type == .xtream, config.isConfigured,
                   let byTvg = await loadXtreamXmltvFile(config: config, interestKeys: interest, onStatus: onStatus) {
                    result = mapXmltv(byTvg, to: channels, limit: limitPerChannel)
                    if let onBatch { await MainActor.run { onBatch(result) } }
                    if !result.isEmpty {
                        await status(onStatus, "Guide ready · \(result.count) channels")
                        return result
                    }
                }
                await status(onStatus, "Bulk guide unavailable — short EPG fallback…")
            }
        }

        // Limited short-EPG fill (never full playlist hammer).
        let need = channels.filter { result[$0.id] == nil }.prefix(100)
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

    // MARK: - True streaming: download + process together

    /// Reads HTTP body as an async byte stream, extracts programmes as complete
    /// tags arrive, and flushes mapped batches to the UI continuously.
    private func streamDownloadAndParse(
        urlString: String,
        interestKeys: Set<String>,
        keyToChannelId: [String: String],
        limitPerChannel: Int,
        onBatch: (@MainActor ([String: [EpgProgram]]) -> Void)?,
        onStatus: (@MainActor (String) -> Void)?
    ) async -> [String: [EpgProgram]]? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }

            let now = Date()
            let windowStart = now.addingTimeInterval(TimeInterval(-Self.windowHoursBehind) * 3600)
            let windowEnd = now.addingTimeInterval(TimeInterval(Self.windowHoursAhead) * 3600)

            // channelId → programmes (already mapped to app ids)
            var byChannel: [String: [EpgProgram]] = [:]
            var dirty: [String: [EpgProgram]] = [:]
            var carry = Data()
            carry.reserveCapacity(64 * 1024)

            var bytesRead = 0
            var programmesSeen = 0
            var lastFlush = Date.distantPast
            var lastStatus = Date.distantPast

            let openToken = Data("<programme".utf8)
            let closeToken = Data("</programme>".utf8)

            // Batch bytes into 32KB chunks — single-byte Data.append is far too slow on multi‑MB EPG.
            var chunk = [UInt8]()
            chunk.reserveCapacity(32 * 1024)

            func processCarry() {
                if carry.count > Self.maxCarryBytes * 2 {
                    carry = Data(carry.suffix(Self.maxCarryBytes))
                }
                while let extracted = Self.popCompleteProgramme(
                    from: &carry,
                    openToken: openToken,
                    closeToken: closeToken
                ) {
                    programmesSeen += 1
                    guard let prog = Self.parseProgrammeXML(
                        extracted,
                        interestKeys: interestKeys,
                        keyToChannelId: keyToChannelId,
                        windowStart: windowStart,
                        windowEnd: windowEnd
                    ) else { continue }

                    let chId = prog.channelKey
                    var list = byChannel[chId] ?? []
                    if list.count < limitPerChannel {
                        list.append(prog)
                        byChannel[chId] = list
                        dirty[chId] = list
                    }
                }
            }

            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count >= 32 * 1024 {
                    carry.append(contentsOf: chunk)
                    bytesRead += chunk.count
                    chunk.removeAll(keepingCapacity: true)
                    processCarry()

                    let nowTick = Date()
                    if !dirty.isEmpty,
                       nowTick.timeIntervalSince(lastFlush) >= Self.flushInterval {
                        let batch = dirty
                        dirty.removeAll(keepingCapacity: true)
                        lastFlush = nowTick
                        if let onBatch {
                            await MainActor.run { onBatch(batch) }
                        }
                    }
                    if nowTick.timeIntervalSince(lastStatus) >= 1.2 {
                        lastStatus = nowTick
                        let mb = Double(bytesRead) / 1_048_576
                        await status(
                            onStatus,
                            String(format: "Streaming guide… %.1f MB · %d channels", mb, byChannel.count)
                        )
                    }
                }
            }
            // Remainder
            if !chunk.isEmpty {
                carry.append(contentsOf: chunk)
                bytesRead += chunk.count
                processCarry()
            }

            // Final flush of remaining dirty + any leftover (none expected).
            if !dirty.isEmpty, let onBatch {
                await MainActor.run { onBatch(dirty) }
            }

            // Sort lists once at end (cheap; already capped).
            for key in byChannel.keys {
                byChannel[key]?.sort { $0.start < $1.start }
            }

            return byChannel.isEmpty ? nil : byChannel
        } catch {
            return nil
        }
    }

    /// Pull one complete `<programme…>…</programme>` from the front of `carry`, if present.
    nonisolated private static func popCompleteProgramme(
        from carry: inout Data,
        openToken: Data,
        closeToken: Data
    ) -> Data? {
        guard let openRange = carry.range(of: openToken) else {
            // No open tag — discard most of the buffer (keep a small tail for partial matches).
            if carry.count > openToken.count {
                carry = carry.suffix(openToken.count - 1)
            }
            return nil
        }
        // Drop junk before the open tag.
        if openRange.lowerBound > 0 {
            carry.removeSubrange(0..<openRange.lowerBound)
        }
        guard let closeRange = carry.range(of: closeToken) else {
            // Incomplete programme — wait for more bytes.
            // Cap carry so one huge programme can't OOM us.
            if carry.count > maxCarryBytes {
                carry.removeAll(keepingCapacity: true)
            }
            return nil
        }
        let end = closeRange.upperBound
        let slice = carry.subdata(in: 0..<end)
        carry.removeSubrange(0..<end)
        return slice
    }

    /// Lightweight parse of a single programme element (no full DOM).
    nonisolated private static func parseProgrammeXML(
        _ data: Data,
        interestKeys: Set<String>,
        keyToChannelId: [String: String],
        windowStart: Date,
        windowEnd: Date
    ) -> EpgProgram? {
        guard let xml = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return nil }

        // channel="…"
        guard let channel = attr(xml, "channel"),
              let start = parseXmltvTime(attr(xml, "start")),
              let end = parseXmltvTime(attr(xml, "stop")),
              end > windowStart,
              start < windowEnd else { return nil }

        // Map to our channel id (skip unrelated XMLTV channels immediately).
        let chId: String
        if let id = keyToChannelId[channel] ?? keyToChannelId[channel.lowercased()] {
            chId = id
        } else if interestKeys.isEmpty {
            chId = channel
        } else {
            return nil
        }

        let title = tag(xml, "title") ?? "Program"
        return EpgProgram(
            channelKey: chId,
            title: unescape(title),
            start: start,
            end: end,
            description: nil
        )
    }

    nonisolated private static func attr(_ xml: String, _ name: String) -> String? {
        // channel="value"  (first match)
        guard let re = try? NSRegularExpression(
            pattern: #"\#(name)\s*=\s*"([^"]*)""#,
            options: [.caseInsensitive]
        ),
        let m = re.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
        m.numberOfRanges >= 3,
        let r = Range(m.range(at: 2), in: xml) else { return nil }
        return String(xml[r])
    }

    nonisolated private static func tag(_ xml: String, _ name: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"<\#(name)(?:\s[^>]*)?>([\s\S]*?)</\#(name)>"#,
            options: [.caseInsensitive]
        ),
        let m = re.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
        let r = Range(m.range(at: 1), in: xml) else { return nil }
        return String(xml[r])
    }

    nonisolated private static func parseXmltvTime(_ raw: String?) -> Date? {
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
        calendar.timeZone = TimeZone(secondsFromGMT: secondsFromGMT) ?? .gmt
        return calendar.date(from: DateComponents(
            year: y, month: mo, day: d, hour: h, minute: mi, second: s
        ))
    }

    nonisolated private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    // MARK: - Bulk URL candidates

    private func bulkURLs(config: IptvConfig?) -> [String] {
        guard let config else { return [] }
        if config.type == .xtream, config.isConfigured,
           let rawHost = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
           let user = config.xtreamUsername,
           let pass = config.xtreamPassword {
            let host = rawHost.hasPrefix("http") ? rawHost : "http://\(rawHost)"
            let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
            let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass
            return [
                "\(host)/xmltv.php?username=\(userQ)&password=\(passQ)",
                "\(host)/xmltv.php?username=\(userQ)&password=\(passQ)&type=m3u_plus",
            ]
        }
        return []
    }

    // MARK: - File fallback (download whole file, SAX parse)

    private func loadXtreamXmltvFile(
        config: IptvConfig,
        interestKeys: Set<String>,
        onStatus: (@MainActor (String) -> Void)?
    ) async -> [String: [EpgProgram]]? {
        for urlString in bulkURLs(config: config) {
            if let map = await downloadFileAndSAX(
                urlString: urlString,
                interestKeys: interestKeys,
                onStatus: onStatus
            ), !map.isEmpty {
                return map
            }
        }
        return nil
    }

    private func downloadFileAndSAX(
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
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.moveItem(at: tempURL, to: temp)

            let attrs = try FileManager.default.attributesOfItem(atPath: temp.path)
            if let size = attrs[.size] as? NSNumber, size.intValue > 100 * 1024 * 1024 {
                try? FileManager.default.removeItem(at: temp)
                await status(onStatus, "Guide file too large for device")
                return nil
            }

            await status(onStatus, "Parsing guide file…")
            let map = await Task.detached(priority: .utility) {
                StreamingXMLTVParser.parse(
                    fileURL: temp,
                    interestKeys: interestKeys,
                    maxPerChannel: EpgService.maxProgramsPerChannel,
                    hoursBehind: EpgService.windowHoursBehind,
                    hoursAhead: EpgService.windowHoursAhead
                )
            }.value
            try? FileManager.default.removeItem(at: temp)
            return map
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
    }

    // MARK: - Mapping helpers

    private func mapXmltv(
        _ byTvg: [String: [EpgProgram]],
        to channels: [IptvChannel],
        limit: Int
    ) -> [String: [EpgProgram]] {
        var lowerIndex: [String: String] = [:]
        for key in byTvg.keys { lowerIndex[key.lowercased()] = key }

        var result: [String: [EpgProgram]] = [:]
        for ch in channels {
            let candidates = [ch.epgChannelId, ch.tvgId, Self.xtreamStreamId(ch)]
                .compactMap { $0 }.filter { !$0.isEmpty }
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

    /// tvg/epg/stream key → SportsDash channel id (for progressive mapping during stream).
    nonisolated private static func keyToChannelId(for channels: [IptvChannel]) -> [String: String] {
        var map: [String: String] = [:]
        map.reserveCapacity(channels.count * 3)
        for ch in channels {
            if let e = ch.epgChannelId, !e.isEmpty {
                map[e] = ch.id
                map[e.lowercased()] = ch.id
            }
            if let t = ch.tvgId, !t.isEmpty {
                map[t] = ch.id
                map[t.lowercased()] = ch.id
            }
            if let sid = xtreamStreamId(ch) {
                map[sid] = ch.id
            }
        }
        return map
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

// MARK: - File SAX parser (fallback)

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
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(
            year: y, month: mo, day: d, hour: h, minute: mi, second: s
        ))
    }
}
