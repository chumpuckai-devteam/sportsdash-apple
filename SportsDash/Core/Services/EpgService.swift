import Foundation
import zlib

/// Fast EPG loader: prefer **one bulk XMLTV download**, fall back to short EPG only when needed.
actor EpgService {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 180
            cfg.httpMaximumConnectionsPerHost = 16
            cfg.httpAdditionalHeaders = [
                "Accept": "*/*",
                "Accept-Encoding": "gzip, deflate",
                "User-Agent": "SportsDash/1.0",
            ]
            self.session = URLSession(configuration: cfg)
        }
    }

    /// Load EPG for channels. Strategy:
    /// 1) Bulk `xmltv.php` (Xtream) or M3U `url-tvg` — **one request, full guide**
    /// 2) Map listings onto channels by tvg/epg id
    /// 3) Optional short-EPG fill only for channels still missing (bounded)
    func loadForChannels(
        channels: [IptvChannel],
        config: IptvConfig?,
        limitPerChannel: Int = 24,
        batchSize: Int = 16,
        preferBulk: Bool = true,
        fillMissingWithShortEpg: Bool = false,
        onBatch: (@MainActor ([String: [EpgProgram]]) -> Void)? = nil,
        onStatus: (@MainActor (String) -> Void)? = nil
    ) async -> [String: [EpgProgram]] {
        guard !channels.isEmpty else { return [:] }

        var result: [String: [EpgProgram]] = [:]

        // --- Fast path: bulk XMLTV ---
        if preferBulk {
            if let config, config.type == .xtream, config.isConfigured {
                await status(onStatus, "Downloading full guide (XMLTV)…")
                if let bulk = await loadXtreamXmltv(config: config) {
                    result = mapXmltv(bulk, to: channels)
                    let hit = result.values.filter { !$0.isEmpty }.count
                    await status(onStatus, "Matched EPG for \(hit)/\(channels.count) channels")
                    if let onBatch { await MainActor.run { onBatch(result) } }
                    // Don't hammer the panel with thousands of short calls when bulk worked.
                    if !fillMissingWithShortEpg || hit > channels.count / 4 {
                        return result
                    }
                } else {
                    await status(onStatus, "Bulk XMLTV unavailable — using faster partial load…")
                }
            } else if let config, config.type == .m3u,
                      let xmltvURL = await discoverM3UXmltvURL(config: config) {
                await status(onStatus, "Downloading XMLTV guide…")
                if let bulk = await fetchAndParseXmltv(urlString: xmltvURL) {
                    result = mapXmltv(bulk, to: channels)
                    if let onBatch { await MainActor.run { onBatch(result) } }
                    return result
                }
            }
        }

        // --- Fallback: parallel short EPG (only missing / all if bulk failed) ---
        let need = channels.filter { result[$0.id]?.isEmpty != false }
        guard !need.isEmpty, let config, config.type == .xtream, config.isConfigured else {
            return result
        }

        await status(onStatus, "Loading short EPG for \(need.count) channels…")
        let short = await loadXtreamShortBatch(
            channels: need,
            config: config,
            limit: limitPerChannel,
            batchSize: batchSize,
            onBatch: { batch in
                if let onBatch {
                    await MainActor.run { onBatch(batch) }
                }
            }
        )
        for (k, v) in short where !v.isEmpty {
            result[k] = v
        }
        return result
    }

    // MARK: - Xtream bulk XMLTV

    /// Standard panel endpoint: `{host}/xmltv.php?username=&password=`
    private func loadXtreamXmltv(config: IptvConfig) async -> [String: [EpgProgram]]? {
        guard let rawHost = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let user = config.xtreamUsername,
              let pass = config.xtreamPassword else { return nil }
        let host = rawHost.hasPrefix("http") ? rawHost : "http://\(rawHost)"
        let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass

        // Try common bulk endpoints (first success wins).
        let candidates = [
            "\(host)/xmltv.php?username=\(userQ)&password=\(passQ)",
            "\(host)/xmltv.php?username=\(userQ)&password=\(passQ)&type=m3u_plus",
        ]
        for url in candidates {
            if let map = await fetchAndParseXmltv(urlString: url), !map.isEmpty {
                return map
            }
        }
        return nil
    }

    private func fetchAndParseXmltv(urlString: String) async -> [String: [EpgProgram]]? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let xmlData = Self.maybeGunzip(data)
            guard let xml = String(data: xmlData, encoding: .utf8)
                    ?? String(data: xmlData, encoding: .isoLatin1),
                  xml.contains("<programme") || xml.contains("<tv") else {
                return nil
            }
            return await Task.detached(priority: .userInitiated) {
                XMLTVParser.parse(xml: xml, windowHours: 36)
            }.value
        } catch {
            return nil
        }
    }

    // MARK: - Map XMLTV channel ids → app channel ids

    private func mapXmltv(
        _ byTvg: [String: [EpgProgram]],
        to channels: [IptvChannel]
    ) -> [String: [EpgProgram]] {
        // Lowercased index for fuzzy match.
        var lowerIndex: [String: String] = [:]
        for key in byTvg.keys {
            lowerIndex[key.lowercased()] = key
        }

        var result: [String: [EpgProgram]] = [:]
        for ch in channels {
            var programs: [EpgProgram] = []
            let keys = [
                ch.epgChannelId,
                ch.tvgId,
                Self.xtreamStreamId(ch),
                ch.name,
            ].compactMap { $0 }.filter { !$0.isEmpty }

            for k in keys {
                if let list = byTvg[k] {
                    programs = list
                    break
                }
                if let real = lowerIndex[k.lowercased()], let list = byTvg[real] {
                    programs = list
                    break
                }
            }
            // Remap channelKey to our channel id for Identifiable consistency.
            if !programs.isEmpty {
                result[ch.id] = programs.map {
                    EpgProgram(
                        channelKey: ch.id,
                        title: $0.title,
                        start: $0.start,
                        end: $0.end,
                        description: $0.description
                    )
                }
            } else {
                result[ch.id] = []
            }
        }
        return result
    }

    // MARK: - Short EPG fallback (bounded)

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
        // Cap short-EPG hammering — bulk path should handle the rest.
        let capped = Array(channels.prefix(400))
        var i = 0
        while i < capped.count {
            let end = min(i + batchSize, capped.count)
            let slice = Array(capped[i..<end])
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
                for await (id, programs) in group {
                    batch[id] = programs
                    result[id] = programs
                }
            }
            if let onBatch { await onBatch(batch) }
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
            let desc = Self.decodeBase64Maybe(item["description"] as? String)
            return EpgProgram(
                channelKey: channelKey,
                title: title,
                start: start,
                end: end,
                description: desc
            )
        }
        .sorted { $0.start < $1.start }
    }

    // MARK: - M3U url-tvg discovery

    private func discoverM3UXmltvURL(config: IptvConfig) async -> String? {
        guard let raw = config.m3uURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw) else { return nil }
        do {
            // Only need the header of the playlist.
            var req = URLRequest(url: url)
            req.setValue("bytes=0-8191", forHTTPHeaderField: "Range")
            let (data, _) = try await session.data(for: req)
            let text = String(data: data, encoding: .utf8) ?? ""
            // #EXTM3U url-tvg="http://..."
            if let re = try? NSRegularExpression(pattern: #"url-tvg="([^"]+)""#),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(m.range(at: 1), in: text) {
                return String(text[r])
            }
            if let re = try? NSRegularExpression(pattern: #"x-tvg-url="([^"]+)""#),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(m.range(at: 1), in: text) {
                return String(text[r])
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

    nonisolated static func demoPrograms(for channel: IptvChannel) -> [EpgProgram] {
        let now = Date()
        let cal = Calendar.current
        let hourStart = cal.dateInterval(of: .hour, for: now)?.start ?? now
        let base = cal.date(byAdding: .hour, value: -1, to: hourStart) ?? hourStart
        return (0..<8).map { i in
            let start = cal.date(byAdding: .hour, value: i, to: base) ?? base
            let end = cal.date(byAdding: .hour, value: i + 1, to: base) ?? start.addingTimeInterval(3600)
            return EpgProgram(
                channelKey: channel.id,
                title: i == 1 ? "Live: \(channel.name)" : channel.name,
                start: start,
                end: end,
                description: nil
            )
        }
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
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyyMMddHHmmss Z", "yyyyMMddHHmmss"] {
            f.dateFormat = format
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }

    /// Decompress gzip if the payload looks compressed (some panels don't set Content-Encoding).
    nonisolated private static func maybeGunzip(_ data: Data) -> Data {
        guard data.count > 2 else { return data }
        // gzip magic 1f 8b
        if data[0] == 0x1f && data[1] == 0x8b {
            return gunzip(data) ?? data
        }
        return data
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
            let chunk = 64 * 1024
            var buffer = [UInt8](repeating: 0, count: chunk)
            var status: Int32 = Z_OK
            while status == Z_OK {
                stream.next_out = UnsafeMutablePointer(&buffer)
                stream.avail_out = uInt(chunk)
                status = inflate(&stream, Z_NO_FLUSH)
                let produced = chunk - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
                if status == Z_STREAM_END { break }
                if status != Z_OK { return nil }
            }
            return output
        }
    }
}

// MARK: - Streaming-ish XMLTV parse (regex, off main thread)

/// Lightweight XMLTV programme extractor. Keeps only a rolling time window to limit memory.
enum XMLTVParser {
    /// - Parameter windowHours: keep programmes from now−2h through now+windowHours.
    static func parse(xml: String, windowHours: Int = 36) -> [String: [EpgProgram]] {
        let now = Date()
        let windowStart = now.addingTimeInterval(-2 * 3600)
        let windowEnd = now.addingTimeInterval(TimeInterval(windowHours) * 3600)

        var map: [String: [EpgProgram]] = [:]
        // Match programme tags; inner content for title/desc.
        guard let progRe = try? NSRegularExpression(
            pattern: #"<programme\s+([^>]+)>([\s\S]*?)</programme>"#,
            options: [.caseInsensitive]
        ) else { return [:] }

        let full = NSRange(xml.startIndex..., in: xml)
        progRe.enumerateMatches(in: xml, options: [], range: full) { match, _, _ in
            guard let match,
                  let attrsRange = Range(match.range(at: 1), in: xml),
                  let innerRange = Range(match.range(at: 2), in: xml) else { return }
            let attrs = String(xml[attrsRange])
            let inner = String(xml[innerRange])
            guard let channel = xmlAttr(attrs, "channel"),
                  let startRaw = xmlAttr(attrs, "start"),
                  let stopRaw = xmlAttr(attrs, "stop"),
                  let start = parseXmltvTime(startRaw),
                  let end = parseXmltvTime(stopRaw),
                  end > windowStart, start < windowEnd else { return }

            let title = unescape(xmlTag(inner, "title") ?? "Program")
            let desc = xmlTag(inner, "desc").map(unescape)
            map[channel, default: []].append(
                EpgProgram(
                    channelKey: channel,
                    title: title,
                    start: start,
                    end: end,
                    description: desc
                )
            )
        }

        for key in map.keys {
            map[key]?.sort { $0.start < $1.start }
        }
        return map
    }

    private static func xmlAttr(_ attrs: String, _ name: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"\#(name)\s*=\s*"([^"]+)""#,
            options: [.caseInsensitive]
        ),
        let m = re.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
        let r = Range(m.range(at: 1), in: attrs) else { return nil }
        // Actually group 1 is name, group 2 is value — fix:
        if m.numberOfRanges >= 3, let vr = Range(m.range(at: 2), in: attrs) {
            return String(attrs[vr])
        }
        return String(attrs[r])
    }

    private static func xmlTag(_ inner: String, _ tag: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"<\#(tag)(?:\s[^>]*)?>([\s\S]*?)</\#(tag)>"#,
            options: [.caseInsensitive]
        ),
        let m = re.firstMatch(in: inner, range: NSRange(inner.startIndex..., in: inner)),
        let r = Range(m.range(at: 1), in: inner) else { return nil }
        return String(inner[r])
    }

    private static func parseXmltvTime(_ raw: String) -> Date? {
        // 20241114103000 +0000  or  20241114103000+0000
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let re = try? NSRegularExpression(pattern: #"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})"#),
              let m = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              m.numberOfRanges >= 7 else {
            return ISO8601DateFormatter().date(from: trimmed)
        }
        func g(_ i: Int) -> Int {
            guard let r = Range(m.range(at: i), in: trimmed) else { return 0 }
            return Int(trimmed[r]) ?? 0
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var comps = DateComponents()
        comps.year = g(1)
        comps.month = g(2)
        comps.day = g(3)
        comps.hour = g(4)
        comps.minute = g(5)
        comps.second = g(6)

        // Offset e.g. +0000 / -0500
        if let offRe = try? NSRegularExpression(pattern: #"([+-])(\d{2})(\d{2})\s*$"#),
           let om = offRe.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let sr = Range(om.range(at: 1), in: trimmed),
           let hr = Range(om.range(at: 2), in: trimmed),
           let mr = Range(om.range(at: 3), in: trimmed) {
            let sign = trimmed[sr] == "+" ? 1 : -1
            let hours = Int(trimmed[hr]) ?? 0
            let mins = Int(trimmed[mr]) ?? 0
            let seconds = sign * (hours * 3600 + mins * 60)
            calendar.timeZone = TimeZone(secondsFromGMT: seconds) ?? .gmt
        }

        return calendar.date(from: comps)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
