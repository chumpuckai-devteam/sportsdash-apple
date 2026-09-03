import Foundation

/// Streaming EPG loader (what keeps other IPTV apps responsive).
///
/// **Pipeline**
/// 1. `URLSession` data task streams the XMLTV body chunk by chunk
/// 2. `XmltvStreamScanner` parses each chunk as it lands (parse overlaps download;
///    nothing is written to disk and only in-window programmes become Strings)
/// 3. Keep only playlist channels + short time window + max programmes / channel
/// 4. Hand a compact dictionary back to the UI **once** (or rare status ticks)
///
/// Avoids: full-file `String`, regex over multi‑MB XML, byte-by-byte MainActor work,
/// and any "file too large" ceiling — memory is bounded by the window, not the file.
actor EpgService {
    private let session: URLSession

    static let maxProgramsPerChannel = 12
    static let windowHoursAhead = 18
    static let windowHoursBehind = 1
    /// Abort guard only — streaming keeps memory flat, so this is about runaway
    /// endpoints, not device RAM. The old 120 MB ceiling rejected real guides
    /// after downloading them, once per URL variant.
    static let maxDownloadBytes: Int64 = 1024 * 1024 * 1024
    /// XMLParser fallback still needs the file on disk; cap that path.
    static let maxFallbackFileBytes: Int64 = 200 * 1024 * 1024

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
    /// Pipeline matches quality IPTV apps:
    /// 1. Bulk XMLTV download + full-window parse (all channel ids in file)
    /// 2. Map to playlist (id + slug + name)
    /// 3. Progressive Xtream short-EPG for **every** still-missing channel
    ///    with `onBatch` after each wave so UI fills in automatically.
    ///
    /// - `onStatus`: rare progress strings (download % / parse / short fill)
    /// - `onBatch`: progressive map merges (caller updates UI + cache)
    func loadForChannels(
        channels: [IptvChannel],
        config: IptvConfig?,
        limitPerChannel: Int = maxProgramsPerChannel,
        batchSize: Int = 16,
        preferBulk: Bool = true,
        fillMissingWithShortEpg: Bool = true,
        ignoreNegativeCache: Bool = false,
        onBatch: (@Sendable ([String: [EpgProgram]]) -> Void)? = nil,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async -> [String: [EpgProgram]] {
        await loadGuide(
            channels: channels,
            config: config,
            limitPerChannel: limitPerChannel,
            batchSize: batchSize,
            preferBulk: preferBulk,
            fillMissingWithShortEpg: fillMissingWithShortEpg,
            ignoreNegativeCache: ignoreNegativeCache,
            existing: [:],
            onBatch: onBatch,
            onStatus: onStatus
        ).map
    }

    struct LoadResult: Sendable {
        var map: [String: [EpgProgram]]
        /// Bulk guide answered 304 Not Modified: `map` is `existing` (+ short-EPG
        /// fills). The caller must keep the original build time — the map's
        /// window keeps aging and must eventually be rebuilt from a fresh file.
        var bulkUnchanged: Bool
    }

    /// `existing`: map the caller already holds, built from the same provider.
    /// Enables a conditional GET; on 304 it is returned as the bulk result.
    func loadGuide(
        channels: [IptvChannel],
        config: IptvConfig?,
        limitPerChannel: Int = maxProgramsPerChannel,
        batchSize: Int = 16,
        preferBulk: Bool = true,
        fillMissingWithShortEpg: Bool = true,
        ignoreNegativeCache: Bool = false,
        existing: [String: [EpgProgram]] = [:],
        onBatch: (@Sendable ([String: [EpgProgram]]) -> Void)? = nil,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async -> LoadResult {
        guard !channels.isEmpty else { return LoadResult(map: [:], bulkUnchanged: false) }
        defer { persistNegativeCacheIfNeeded() }
        var bulkUnchanged = false

        // Full bulk like other IPTV clients: keep all programmes in the time window.
        // Window + max-per-channel already bound memory; interest-key filtering was
        // dropping entire movie packs with empty epg_channel_id.
        let interest: Set<String> = preferBulk ? [] : Self.interestKeys(for: channels)
        var result: [String: [EpgProgram]] = [:]

        if preferBulk {
            let urls = await bulkURLs(config: config)
            for (index, urlString) in urls.enumerated() {
                onStatus?("Downloading guide… (\(index + 1)/\(urls.count))")
                let outcome = await streamAndParse(
                    urlString: urlString,
                    interestKeys: interest,
                    limitPerChannel: limitPerChannel,
                    allowConditional: !existing.isEmpty,
                    onStatus: onStatus
                )
                switch outcome {
                case .notModified:
                    // Provider's file has not changed since the map we already
                    // hold was built from it — skip the download and the mapping.
                    result = existing
                    bulkUnchanged = true
                    Self.rememberBulkURL(urlString)
                    onStatus?("Guide unchanged · \(result.count)/\(channels.count) channels")
                case .parsed(let byTvg) where !byTvg.isEmpty:
                    result = mapXmltv(byTvg, to: channels, limit: limitPerChannel)
                    Self.rememberBulkURL(urlString)
                    onStatus?("Guide mapped · \(result.count)/\(channels.count) channels")
                    onBatch?(result)
                case .parsed:
                    continue
                case .failed:
                    continue
                }
                break
            }
            if result.isEmpty {
                onStatus?("Bulk guide unavailable — loading per-channel EPG…")
            }
        }

        guard fillMissingWithShortEpg,
              let config,
              config.type == .xtream,
              config.isConfigured else {
            onStatus?("Guide ready · \(result.count) channels")
            return LoadResult(map: result, bulkUnchanged: bulkUnchanged)
        }

        // Progressive short-EPG until every missing channel has been attempted.
        // Cap total waves by channel count (never infinite).
        // Background gap-fill skips channels the provider answered "no listings"
        // for recently — re-asking thousands of them every launch was the request
        // storm behind the guide ticks. A user-driven reload asks everything again.
        let negativeHost = Self.shortEpgHost(config)
        var missing = channels.filter { ch in
            guard result[ch.id] == nil else { return false }
            if ignoreNegativeCache { return true }
            return !isRecentlyEmpty(Self.negativeKey(host: negativeHost, channelId: ch.id))
        }
        guard !missing.isEmpty else {
            onStatus?("Guide ready · \(result.count)/\(channels.count) channels")
            return LoadResult(map: result, bulkUnchanged: bulkUnchanged)
        }

        let waveSize = max(batchSize, 12)
        /// Waves that actually hit the network (a wave can be entirely in flight
        /// for another caller, which says nothing about the provider).
        var requestedWaves = 0
        let totalMissing = missing.count
        while !missing.isEmpty {
            let slice = Array(missing.prefix(waveSize * 4)) // 4 concurrent batches worth
            onStatus?("Auto-filling guide \(result.count)/\(channels.count) · \(totalMissing - missing.count + slice.count)/\(totalMissing) gaps…")
            let (short, requested) = await loadXtreamShortBatch(
                channels: slice,
                config: config,
                limit: min(limitPerChannel, 8),
                batchSize: waveSize
            )
            if requested > 0 { requestedWaves += 1 }
            if !short.isEmpty {
                for (k, v) in short where !v.isEmpty {
                    result[k] = v
                }
                // Delta only — sending the full map every wave froze the UI.
                onBatch?(short)
            }
            let attempted = Set(slice.map(\.id))
            missing = missing.filter { !attempted.contains($0.id) }
            // Bail if provider returns nothing for a full wave (dead EPG endpoint).
            if requested > 0, short.isEmpty, requestedWaves >= 2 {
                onStatus?("Guide partial · \(result.count)/\(channels.count) — provider has no listings for remaining channels")
                break
            }
        }
        // Callers apply the returned map; re-sending the whole guide here made
        // MainActor merge a full copy it was about to replace anyway.
        onStatus?("Guide ready · \(result.count)/\(channels.count) channels")
        return LoadResult(map: result, bulkUnchanged: bulkUnchanged)
    }

    // MARK: - Streaming download → chunk scan (primary) / disk + SAX parse (fallback)

    private enum BulkOutcome {
        case parsed([String: [EpgProgram]])
        case notModified
        case failed
    }

    private func streamAndParse(
        urlString: String,
        interestKeys: Set<String>,
        limitPerChannel: Int,
        allowConditional: Bool,
        onStatus: (@Sendable (String) -> Void)?
    ) async -> BulkOutcome {
        guard let url = URL(string: urlString) else { return .failed }

        var request = URLRequest(url: url)
        if allowConditional, let validators = Self.storedValidators(for: urlString) {
            if let etag = validators.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let lm = validators.lastModified { request.setValue(lm, forHTTPHeaderField: "If-Modified-Since") }
        }

        let scanner = XmltvStreamScanner(
            interestKeys: interestKeys,
            maxPerChannel: limitPerChannel,
            hoursBehind: Self.windowHoursBehind,
            hoursAhead: Self.windowHoursAhead
        )
        let delegate = StreamingXmltvDelegate(scanner: scanner, maxBytes: Self.maxDownloadBytes) { received, expected in
            let mb = Double(received) / 1_048_576
            if expected > 0 {
                let pct = Int(Double(received) * 100 / Double(expected))
                onStatus?(String(format: "Downloading guide… %.0f MB (%d%%)", mb, pct))
            } else {
                onStatus?(String(format: "Downloading guide… %.0f MB", mb))
            }
        }
        // Delegate sessions retain their delegate until invalidated.
        let streamSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        defer { streamSession.finishTasksAndInvalidate() }

        do {
            try await delegate.run(streamSession.dataTask(with: request))
        } catch {
            if delegate.tooLarge {
                onStatus?("Guide file too large for this device")
            }
            return .failed
        }

        if delegate.statusCode == 304 { return .notModified }
        guard (200...299).contains(delegate.statusCode), delegate.received > 0 else { return .failed }
        Self.storeValidators(etag: delegate.etag, lastModified: delegate.lastModified, for: urlString)

        let map = scanner.finish()
        if !map.isEmpty { return .parsed(map) }

        // Nothing recognised as lowercase XMLTV: let Foundation's XMLParser have a
        // go (odd encodings, uppercase tags). Needs the file on disk, so bounded.
        guard delegate.received <= Self.maxFallbackFileBytes else { return .failed }
        onStatus?("Guide format unusual — re-parsing on disk…")
        if let fallback = await downloadToDiskAndParseWithXMLParser(
            url: url, interestKeys: interestKeys, limitPerChannel: limitPerChannel
        ), !fallback.isEmpty {
            return .parsed(fallback)
        }
        return .failed
    }

    private func downloadToDiskAndParseWithXMLParser(
        url: URL,
        interestKeys: Set<String>,
        limitPerChannel: Int
    ) async -> [String: [EpgProgram]]? {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("sportsdash-epg-\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: dest) }
        do {
            let (fileURL, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: fileURL, to: dest)
            return await Task.detached(priority: .utility) {
                DiskXMLTVParser.parse(
                    fileURL: dest,
                    interestKeys: interestKeys,
                    maxPerChannel: limitPerChannel,
                    hoursBehind: EpgService.windowHoursBehind,
                    hoursAhead: EpgService.windowHoursAhead
                )
            }.value
        } catch {
            return nil
        }
    }

    // MARK: - Bulk URL memory + HTTP validators

    /// Bulk URLs embed the Xtream password, so UserDefaults only ever sees a
    /// digest of them (stable across launches, unlike `hashValue`).
    private static let lastBulkURLKey = "epg_last_bulk_url_digest"

    nonisolated static func stableDigest(_ text: String) -> String {
        // FNV-1a 64-bit
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    nonisolated private static func rememberBulkURL(_ url: String) {
        UserDefaults.standard.set(stableDigest(url), forKey: lastBulkURLKey)
    }

    private struct Validators: Codable {
        var etag: String?
        var lastModified: String?
    }

    nonisolated private static func validatorsKey(for url: String) -> String {
        "epg_validators_" + stableDigest(url)
    }

    nonisolated private static func storedValidators(for url: String) -> Validators? {
        guard let data = UserDefaults.standard.data(forKey: validatorsKey(for: url)),
              let v = try? JSONDecoder().decode(Validators.self, from: data),
              v.etag != nil || v.lastModified != nil else { return nil }
        return v
    }

    nonisolated private static func storeValidators(etag: String?, lastModified: String?, for url: String) {
        let key = validatorsKey(for: url)
        guard etag != nil || lastModified != nil else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(Validators(etag: etag, lastModified: lastModified)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - URLs

    /// Xtream bulk guide = same panel as get.php M3U, but `xmltv.php?username=&password=`.
    /// Example: `https://host/xmltv.php?username=USER&password=PASS`
    private func bulkURLs(config: IptvConfig?) async -> [String] {
        var urls: [String] = []
        guard let config else { return urls }

        if config.type == .m3u {
            if let tvg = await discoverM3UXmltvURL(config: config) {
                urls.append(tvg)
            }
            // M3U that is really Xtream get.php — derive xmltv.php on the same host.
            if let m3u = config.m3uURL, let derived = Self.xtreamXmltvURLs(fromAnyURL: m3u) {
                urls.append(contentsOf: derived)
            }
        }

        if config.type == .xtream, config.isConfigured,
           let rawHost = config.xtreamHost,
           let user = config.xtreamUsername,
           let pass = config.xtreamPassword {
            urls.append(contentsOf: Self.xtreamXmltvURLs(hostField: rawHost, user: user, pass: pass))
        }

        // Last URL that produced a guide goes first — no more re-downloading a
        // 100+ MB file per variant before landing on the one that works.
        if let lastDigest = UserDefaults.standard.string(forKey: Self.lastBulkURLKey),
           let last = urls.first(where: { Self.stableDigest($0) == lastDigest }) {
            urls.removeAll { $0 == last }
            urls.insert(last, at: 0)
        }
        // De-dupe preserving order
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    /// Build canonical Xtream XMLTV endpoints (https preferred, then http).
    nonisolated private static func xtreamXmltvURLs(hostField: String, user: String, pass: String) -> [String] {
        guard let base = normalizeXtreamBase(hostField) else { return [] }
        let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass
        let query = "username=\(userQ)&password=\(passQ)"
        // Prefer https (user example: Xtream panel) then http. (`type=m3u_plus`
        // is ignored by xmltv.php; keeping it as a variant only doubled downloads.)
        return httpsPreferredRoots(base).map { "\($0)/xmltv.php?\(query)" }
    }

    /// When M3U URL embeds user/pass (get.php?username=…), build xmltv.php siblings.
    nonisolated private static func xtreamXmltvURLs(fromAnyURL raw: String) -> [String]? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        let user = items.first(where: { $0.name == "username" })?.value
        let pass = items.first(where: { $0.name == "password" })?.value
        guard let user, let pass, !user.isEmpty, !pass.isEmpty else { return nil }
        // Only treat as Xtream-style if path looks like get.php / player_api / xmltv
        let path = (comps.path).lowercased()
        guard path.contains("get.php") || path.contains("player_api") || path.contains("xmltv")
                || raw.lowercased().contains("username=") else { return nil }
        var root = comps
        root.path = ""
        root.query = nil
        root.fragment = nil
        guard let base = root.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return nil }
        return xtreamXmltvURLs(hostField: base, user: user, pass: pass)
    }

    /// `your-xtream-host.com` | `https://your-xtream-host.com/` | `https://host/c/` → scheme+host(+port)
    nonisolated private static func normalizeXtreamBase(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            s = "https://\(s)" // default https (matches Xtream-style panels)
        }
        guard var comps = URLComponents(string: s) else { return nil }
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        guard let host = comps.host, !host.isEmpty else { return nil }
        let scheme = (comps.scheme?.isEmpty == false) ? comps.scheme! : "https"
        if let port = comps.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    nonisolated private static func httpsPreferredRoots(_ base: String) -> [String] {
        var roots: [String] = [base]
        if base.hasPrefix("http://") {
            roots.insert("https://" + base.dropFirst("http://".count), at: 0)
        } else if base.hasPrefix("https://") {
            roots.append("http://" + base.dropFirst("https://".count))
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0).inserted }
    }

    private func discoverM3UXmltvURL(config: IptvConfig) async -> String? {
        guard let raw = config.m3uURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw) else { return nil }
        // Direct xmltv.php already?
        if raw.lowercased().contains("xmltv.php") { return raw }
        do {
            var req = URLRequest(url: url)
            req.setValue("bytes=0-8191", forHTTPHeaderField: "Range")
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

    // Map XMLTV ids → app channels; also try stripped name tokens when IDs miss.
    private func mapXmltv(
        _ byTvg: [String: [EpgProgram]],
        to channels: [IptvChannel],
        limit: Int
    ) -> [String: [EpgProgram]] {
        var lowerIndex: [String: String] = [:]
        lowerIndex.reserveCapacity(byTvg.count)
        for key in byTvg.keys { lowerIndex[key.lowercased()] = key }

        // Secondary index: normalized slug of XMLTV channel id (showtime.us → showtime)
        var slugIndex: [String: String] = [:]
        for key in byTvg.keys {
            let slug = Self.epgSlug(key)
            if !slug.isEmpty, slugIndex[slug] == nil {
                slugIndex[slug] = key
            }
        }

        // Fuzzy fallback scans every slug per unmatched channel; build the
        // candidate list once instead of re-walking the dictionary (and re-counting
        // each key) per channel.
        let fuzzyPairs: [(slug: String, real: String)] = slugIndex.compactMap { entry in
            entry.key.count >= 4 ? (slug: entry.key, real: entry.value) : nil
        }

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
                let slug = Self.epgSlug(k)
                if !slug.isEmpty, let real = slugIndex[slug], let list = byTvg[real] {
                    programs = list
                    break
                }
            }

            // Name-based fallback: "US: Showtime" / "Showtime HD" → slug showtime
            if programs.isEmpty {
                let nameSlug = Self.epgSlug(ch.name)
                if !nameSlug.isEmpty, let real = slugIndex[nameSlug], let list = byTvg[real] {
                    programs = list
                } else if !nameSlug.isEmpty {
                    // Prefix match longest slug key contained in name (or vice versa)
                    for (slug, real) in fuzzyPairs {
                        if nameSlug.contains(slug) || slug.contains(nameSlug) {
                            if let list = byTvg[real], !list.isEmpty {
                                programs = list
                                break
                            }
                        }
                    }
                }
            }

            guard !programs.isEmpty else { continue }
            result[ch.id] = Array(programs.prefix(limit)).map { $0.remapped(toChannelKey: ch.id) }
        }
        return result
    }

    /// Normalize EPG / channel labels for fuzzy match: alphanumerics only, lowercased.
    nonisolated private static func epgSlug(_ raw: String) -> String {
        let lower = raw.lowercased()
        var out = ""
        out.reserveCapacity(lower.count)
        for ch in lower where ch.isLetter || ch.isNumber {
            out.append(ch)
        }
        // Drop common broadcast noise tokens from the slug ends if whole string still long
        let noise = ["hd", "uhd", "4k", "fhd", "sd", "us", "uk", "ca", "hevc", "h265"]
        for n in noise {
            if out.hasSuffix(n), out.count > n.count + 3 {
                out = String(out.dropLast(n.count))
            }
            if out.hasPrefix(n), out.count > n.count + 3 {
                out = String(out.dropFirst(n.count))
            }
        }
        return out
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

    /// Returns the listings found plus how many channels were actually requested
    /// (channels already in flight for another caller are skipped).
    private func loadXtreamShortBatch(
        channels: [IptvChannel],
        config: IptvConfig,
        limit: Int,
        batchSize: Int
    ) async -> (programs: [String: [EpgProgram]], requested: Int) {
        guard let rawHost = config.xtreamHost?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let user = config.xtreamUsername,
              let pass = config.xtreamPassword else { return ([:], 0) }
        let host = rawHost.hasPrefix("http") ? rawHost : "http://\(rawHost)"
        let userQ = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let passQ = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass
        let negativeHost = Self.shortEpgHost(config)

        // Category gap-fill and the launch auto-fill overlap; whoever asked first
        // owns the request and merges it, so the other caller skips it.
        let wanted = channels.filter { !shortEpgInFlight.contains($0.id) }
        for ch in wanted { shortEpgInFlight.insert(ch.id) }
        defer { for ch in wanted { shortEpgInFlight.remove(ch.id) } }

        var result: [String: [EpgProgram]] = [:]
        var i = 0
        while i < wanted.count {
            let end = min(i + batchSize, wanted.count)
            let slice = Array(wanted[i..<end])
            // nil = request failed (do not remember), [] = provider has no listings.
            let batch = await withTaskGroup(of: (String, [EpgProgram]?).self, returning: [(String, [EpgProgram]?)].self) { group in
                for ch in slice {
                    group.addTask {
                        guard let streamId = Self.xtreamStreamId(ch) else {
                            return (ch.id, nil)
                        }
                        do {
                            let programs = try await self.fetchShortEpg(
                                host: host, userQ: userQ, passQ: passQ,
                                streamId: streamId, limit: limit, channelKey: ch.id
                            )
                            return (ch.id, programs)
                        } catch {
                            return (ch.id, nil)
                        }
                    }
                }
                var out: [(String, [EpgProgram]?)] = []
                out.reserveCapacity(slice.count)
                for await item in group { out.append(item) }
                return out
            }
            for (id, programs) in batch {
                guard let programs else { continue }
                if programs.isEmpty {
                    markEmpty(Self.negativeKey(host: negativeHost, channelId: id))
                } else {
                    result[id] = programs
                }
            }
            i = end
        }
        return (result, wanted.count)
    }

    // MARK: - Short-EPG negative cache (channels the provider has no listings for)

    static let shortEpgNegativeTTL: TimeInterval = 6 * 3600

    /// channel key → unix time the provider last answered with no listings.
    private var shortEpgEmptyAt: [String: TimeInterval]?
    private var shortEpgInFlight: Set<String> = []
    private var negativeCacheDirty = false

    nonisolated private static var negativeCacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("sportsdash_epg_short_empty.json")
    }

    nonisolated private static func shortEpgHost(_ config: IptvConfig?) -> String {
        (config?.xtreamHost ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated private static func negativeKey(host: String, channelId: String) -> String {
        "\(host)|\(channelId)"
    }

    private func loadedNegativeCache() -> [String: TimeInterval] {
        if let shortEpgEmptyAt { return shortEpgEmptyAt }
        var map: [String: TimeInterval] = [:]
        if let data = try? Data(contentsOf: Self.negativeCacheURL),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            let floor = Date().timeIntervalSince1970 - Self.shortEpgNegativeTTL
            map = decoded.filter { $0.value > floor }
        }
        shortEpgEmptyAt = map
        return map
    }

    private func isRecentlyEmpty(_ key: String) -> Bool {
        guard let at = loadedNegativeCache()[key] else { return false }
        return Date().timeIntervalSince1970 - at < Self.shortEpgNegativeTTL
    }

    private func markEmpty(_ key: String) {
        if shortEpgEmptyAt == nil { _ = loadedNegativeCache() }
        shortEpgEmptyAt?[key] = Date().timeIntervalSince1970
        negativeCacheDirty = true
    }

    private func persistNegativeCacheIfNeeded() {
        guard negativeCacheDirty, let map = shortEpgEmptyAt else { return }
        negativeCacheDirty = false
        let url = Self.negativeCacheURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(map) else { return }
            try? data.write(to: url, options: .atomic)
        }
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

// MARK: - XMLTV timestamps ("20240102030405 +0100")

enum XmltvTime {
    /// Parse an XMLTV timestamp from UTF-8 bytes. Pure integer math — the previous
    /// `Calendar.date(from:)` per programme was ~10 µs × 2 × every programme in a
    /// multi-day guide, i.e. seconds of CPU before a single row could paint.
    static func parse(_ buf: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> TimeInterval? {
        var s = start
        var e = end
        while s < e, isSpace(buf[s]) { s += 1 }
        while e > s, isSpace(buf[e - 1]) { e -= 1 }
        guard e - s >= 14 else { return nil }

        func digits(_ at: Int, _ count: Int) -> Int? {
            var v = 0
            for k in 0..<count {
                let c = buf[at + k]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard let y = digits(s, 4),
              let mo = digits(s + 4, 2),
              let d = digits(s + 6, 2),
              let h = digits(s + 8, 2),
              let mi = digits(s + 10, 2),
              let sec = digits(s + 12, 2),
              (1...12).contains(mo), (1...31).contains(d) else { return nil }

        // Optional " +HHMM" / "-HH:MM" suffix; anything else is treated as GMT.
        var offset = 0
        var i = s + 14
        while i < e, isSpace(buf[i]) { i += 1 }
        if i < e, buf[i] == 43 || buf[i] == 45 { // + or -
            let sign = buf[i] == 43 ? 1 : -1
            var tz: [Int] = []
            var j = i + 1
            while j < e, tz.count < 4 {
                let c = buf[j]
                if c >= 48, c <= 57 { tz.append(Int(c - 48)) }
                j += 1
            }
            if tz.count == 4 {
                offset = sign * ((tz[0] * 10 + tz[1]) * 3600 + (tz[2] * 10 + tz[3]) * 60)
            }
        }
        let days = daysFromCivil(y, mo, d)
        return TimeInterval(days * 86_400 + h * 3600 + mi * 60 + sec - offset)
    }

    static func parse(_ raw: String) -> Date? {
        let bytes = Array(raw.utf8)
        let interval: TimeInterval? = bytes.withUnsafeBufferPointer { buf in
            parse(buf, from: 0, to: buf.count)
        }
        return interval.map { Date(timeIntervalSince1970: $0) }
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    @inline(__always)
    static func isSpace(_ c: UInt8) -> Bool {
        c == 32 || c == 9 || c == 10 || c == 13
    }
}

// MARK: - Byte-level XMLTV scanner (primary)

/// XMLTV is machine-generated and regular, so a byte scan over the memory-mapped
/// file finds `<programme start stop channel>` blocks directly. Foundation's
/// `XMLParser` bridges every element name, attribute dictionary and text run
/// (including multi-KB `<desc>` bodies we throw away) into Swift Strings — that
/// bridging was most of the parse time on a 30–100 MB guide. Here only in-window
/// programmes for wanted channels ever become Strings.
enum XmltvByteScanner {
    static func parse(
        fileURL: URL,
        interestKeys: Set<String>,
        maxPerChannel: Int,
        hoursBehind: Int,
        hoursAhead: Int
    ) -> [String: [EpgProgram]] {
        // Mapped, not read: the kernel pages the file in as the scan advances and
        // can drop clean pages under pressure.
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else { return [:] }
        let now = Date().timeIntervalSince1970
        let windowStart = now - TimeInterval(hoursBehind) * 3600
        let windowEnd = now + TimeInterval(hoursAhead) * 3600

        var map: [String: [EpgProgram]] = [:]
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count > 0 else { return }
            let buf = UnsafeBufferPointer(start: base, count: raw.count)
            _ = scan(
                buf,
                from: 0,
                to: buf.count,
                interestKeys: interestKeys,
                maxPerChannel: maxPerChannel,
                windowStart: windowStart,
                windowEnd: windowEnd,
                into: &map
            )
        }

        for key in map.keys {
            map[key]?.sort { $0.start < $1.start }
        }
        return map
    }

    private static let programmeOpen = Array("<programme".utf8)
    private static let programmeClose = Array("</programme>".utf8)
    private static let titleOpen = Array("<title".utf8)
    private static let titleClose = Array("</title>".utf8)
    private static let categoryOpen = Array("<category".utf8)
    private static let categoryClose = Array("</category>".utf8)
    private static let attrChannel = Array("channel=".utf8)
    private static let attrStart = Array("start=".utf8)
    private static let attrStop = Array("stop=".utf8)
    private static let cdataOpen = Array("<![CDATA[".utf8)
    private static let cdataClose = Array("]]>".utf8)
    private static let maxTextBytes = 400
    private static let maxCategories = 8

    /// Parse every complete `<programme>…</programme>` in `buf[from..<end]`.
    /// Returns the offset up to which bytes are fully consumed; anything after it
    /// (an unterminated programme, or a tag split across a chunk boundary) must be
    /// carried into the next call.
    static func scan(
        _ buf: UnsafeBufferPointer<UInt8>,
        from: Int,
        to end: Int,
        interestKeys: Set<String>,
        maxPerChannel: Int,
        windowStart: TimeInterval,
        windowEnd: TimeInterval,
        into map: inout [String: [EpgProgram]]
    ) -> Int {
        let n = end
        var cursor = from
        while let open = findTag(programmeOpen, in: buf, from: cursor, to: n) {
            guard let tagEnd = indexOf(62, in: buf, from: open + programmeOpen.count, to: n) else { return open } // '>'
            let attrsFrom = open + programmeOpen.count
            let selfClosing = buf[tagEnd - 1] == 47 // '/'
            let bodyStart = tagEnd + 1
            var bodyEnd = bodyStart
            if selfClosing {
                cursor = bodyStart
            } else {
                guard let close = find(programmeClose, in: buf, from: bodyStart, to: n) else { return open }
                bodyEnd = close
                cursor = close + programmeClose.count
            }

            // Cheap numeric gates first — most of a 7-day file is outside the window.
            guard let startRange = attributeValue(attrStart, in: buf, from: attrsFrom, to: tagEnd),
                  let stopRange = attributeValue(attrStop, in: buf, from: attrsFrom, to: tagEnd),
                  let start = XmltvTime.parse(buf, from: startRange.0, to: startRange.1),
                  let end = XmltvTime.parse(buf, from: stopRange.0, to: stopRange.1),
                  end > windowStart, start < windowEnd else { continue }

            guard let channelRange = attributeValue(attrChannel, in: buf, from: attrsFrom, to: tagEnd) else { continue }
            let channel = decodeText(buf, channelRange.0, channelRange.1, trim: false)
            guard !channel.isEmpty else { continue }
            if let existing = map[channel], existing.count >= maxPerChannel { continue }
            if !interestKeys.isEmpty,
               !interestKeys.contains(channel),
               !interestKeys.contains(channel.lowercased()) { continue }

            var title = ""
            if let t = elementText(titleOpen, titleClose, in: buf, from: bodyStart, to: bodyEnd) {
                title = decodeText(buf, t.0, t.1, trim: true)
            }
            var categories: [String] = []
            var catCursor = bodyStart
            while categories.count < maxCategories,
                  let c = elementText(categoryOpen, categoryClose, in: buf, from: catCursor, to: bodyEnd) {
                let cat = decodeText(buf, c.0, c.1, trim: true)
                if !cat.isEmpty { categories.append(cat) }
                catCursor = c.2
            }

            map[channel, default: []].append(
                EpgProgram(
                    channelKey: channel,
                    title: title.isEmpty ? "Program" : title,
                    start: Date(timeIntervalSince1970: start),
                    end: Date(timeIntervalSince1970: end),
                    description: nil,
                    categories: categories
                )
            )
        }
        // No further complete programme. Keep a tag's worth of tail in case
        // "<programme" itself straddles the boundary.
        return max(cursor, n - programmeOpen.count)
    }

    // MARK: Byte helpers

    @inline(__always)
    private static func indexOf(_ byte: UInt8, in buf: UnsafeBufferPointer<UInt8>, from: Int, to end: Int) -> Int? {
        guard from < end, let base = buf.baseAddress else { return nil }
        guard let hit = memchr(base + from, Int32(byte), end - from) else { return nil }
        return UnsafeRawPointer(hit) - UnsafeRawPointer(base)
    }

    /// First occurrence of `needle` in `buf[from..<end]`.
    private static func find(_ needle: [UInt8], in buf: UnsafeBufferPointer<UInt8>, from: Int, to end: Int) -> Int? {
        let m = needle.count
        guard m > 0, end - from >= m else { return nil }
        let first = needle[0]
        var i = from
        let last = end - m
        while i <= last {
            guard let hit = indexOf(first, in: buf, from: i, to: last + 1) else { return nil }
            var j = 1
            while j < m, buf[hit + j] == needle[j] { j += 1 }
            if j == m { return hit }
            i = hit + 1
        }
        return nil
    }

    /// Like `find`, but the byte after the tag name must end the name
    /// (`<programme ` not `<programmes`).
    private static func findTag(_ needle: [UInt8], in buf: UnsafeBufferPointer<UInt8>, from: Int, to end: Int) -> Int? {
        var i = from
        while let hit = find(needle, in: buf, from: i, to: end) {
            let after = hit + needle.count
            if after >= end { return nil }
            let c = buf[after]
            if XmltvTime.isSpace(c) || c == 62 || c == 47 { return hit } // '>' or '/'
            i = hit + 1
        }
        return nil
    }

    /// Byte range of a quoted attribute value inside a start tag.
    private static func attributeValue(
        _ name: [UInt8],
        in buf: UnsafeBufferPointer<UInt8>,
        from: Int,
        to end: Int
    ) -> (Int, Int)? {
        var i = from
        while let hit = find(name, in: buf, from: i, to: end) {
            let quotePos = hit + name.count
            // Must be a whole attribute name (preceded by whitespace) and quoted.
            if hit > 0, XmltvTime.isSpace(buf[hit - 1]), quotePos < end {
                let quote = buf[quotePos]
                if quote == 34 || quote == 39, // " or '
                   let close = indexOf(quote, in: buf, from: quotePos + 1, to: end) {
                    return (quotePos + 1, close)
                }
            }
            i = hit + 1
        }
        return nil
    }

    /// Text range of the first `<open …>text</close>` in `buf[from..<end]`, plus the
    /// index just past the closing tag so callers can continue scanning.
    private static func elementText(
        _ open: [UInt8],
        _ close: [UInt8],
        in buf: UnsafeBufferPointer<UInt8>,
        from: Int,
        to end: Int
    ) -> (Int, Int, Int)? {
        guard let tag = findTag(open, in: buf, from: from, to: end),
              let gt = indexOf(62, in: buf, from: tag + open.count, to: end) else { return nil }
        if buf[gt - 1] == 47 { // <title/>
            return (gt, gt, gt + 1)
        }
        guard let closeAt = find(close, in: buf, from: gt + 1, to: end) else { return nil }
        return (gt + 1, closeAt, closeAt + close.count)
    }

    /// Bytes → String with optional trim, CDATA unwrap, length cap and XML entity decoding.
    private static func decodeText(_ buf: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, trim: Bool) -> String {
        var s = start
        var e = end
        if trim {
            while s < e, XmltvTime.isSpace(buf[s]) { s += 1 }
            while e > s, XmltvTime.isSpace(buf[e - 1]) { e -= 1 }
        }
        if e - s >= cdataOpen.count + cdataClose.count,
           matches(cdataOpen, in: buf, at: s),
           matches(cdataClose, in: buf, at: e - cdataClose.count) {
            s += cdataOpen.count
            e -= cdataClose.count
            if trim {
                while s < e, XmltvTime.isSpace(buf[s]) { s += 1 }
                while e > s, XmltvTime.isSpace(buf[e - 1]) { e -= 1 }
            }
        }
        if e - s > maxTextBytes {
            e = s + maxTextBytes
            // Do not cut a multi-byte UTF-8 sequence in half.
            while e > s, buf[e] & 0xC0 == 0x80 { e -= 1 }
        }
        guard e > s else { return "" }
        if indexOf(38, in: buf, from: s, to: e) == nil { // '&'
            return String(decoding: UnsafeBufferPointer(rebasing: buf[s..<e]), as: UTF8.self)
        }
        return unescape(buf, s, e)
    }

    @inline(__always)
    private static func matches(_ needle: [UInt8], in buf: UnsafeBufferPointer<UInt8>, at: Int) -> Bool {
        guard at >= 0, at + needle.count <= buf.count else { return false }
        for k in 0..<needle.count where buf[at + k] != needle[k] { return false }
        return true
    }

    private static func unescape(_ buf: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(end - start)
        var i = start
        while i < end {
            let c = buf[i]
            guard c == 38, let semi = indexOf(59, in: buf, from: i + 1, to: min(end, i + 12)) else { // '&' … ';'
                out.append(c)
                i += 1
                continue
            }
            let name = UnsafeBufferPointer(rebasing: buf[(i + 1)..<semi])
            switch String(decoding: name, as: UTF8.self) {
            case "amp": out.append(38)
            case "lt": out.append(60)
            case "gt": out.append(62)
            case "quot": out.append(34)
            case "apos": out.append(39)
            case let ref where ref.hasPrefix("#"):
                let digits = ref.dropFirst()
                let value: UInt32?
                if digits.hasPrefix("x") || digits.hasPrefix("X") {
                    value = UInt32(digits.dropFirst(), radix: 16)
                } else {
                    value = UInt32(digits)
                }
                if let value, let scalar = Unicode.Scalar(value) {
                    out.append(contentsOf: Array(String(Character(scalar)).utf8))
                } else {
                    out.append(contentsOf: buf[i...semi])
                }
            default:
                out.append(contentsOf: buf[i...semi])
            }
            i = semi + 1
        }
        return String(decoding: out, as: UTF8.self)
    }
}

// MARK: - Chunked scanner (download and parse overlap)

/// Feeds network chunks through `XmltvByteScanner` as they arrive. Only the
/// unconsumed tail (a partial programme, typically well under a page) is copied
/// between chunks, so RAM stays flat however large the guide is.
final class XmltvStreamScanner: @unchecked Sendable {
    private let interestKeys: Set<String>
    private let maxPerChannel: Int
    private let windowStart: TimeInterval
    private let windowEnd: TimeInterval
    private var map: [String: [EpgProgram]] = [:]
    private var carry: [UInt8] = []
    private(set) var bytesScanned = 0

    init(interestKeys: Set<String>, maxPerChannel: Int, hoursBehind: Int, hoursAhead: Int) {
        self.interestKeys = interestKeys
        self.maxPerChannel = maxPerChannel
        let now = Date().timeIntervalSince1970
        self.windowStart = now - TimeInterval(hoursBehind) * 3600
        self.windowEnd = now + TimeInterval(hoursAhead) * 3600
    }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        bytesScanned += data.count
        if carry.isEmpty {
            // Common case: scan the chunk in place, copy only the tail.
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                let buf = UnsafeBufferPointer(start: base, count: raw.count)
                let consumed = scan(buf, from: 0, to: buf.count)
                if consumed < buf.count {
                    carry.append(contentsOf: buf[consumed..<buf.count])
                }
            }
        } else {
            carry.append(contentsOf: data)
            let consumed = carry.withUnsafeBufferPointer { buf in
                scan(buf, from: 0, to: buf.count)
            }
            if consumed >= carry.count {
                carry.removeAll(keepingCapacity: true)
            } else if consumed > 0 {
                carry.removeFirst(consumed)
            }
        }
    }

    func finish() -> [String: [EpgProgram]] {
        if !carry.isEmpty {
            // A final self-closing programme can sit in the tail; give it one last pass.
            _ = carry.withUnsafeBufferPointer { buf in
                scan(buf, from: 0, to: buf.count)
            }
            carry.removeAll()
        }
        for key in map.keys {
            map[key]?.sort { $0.start < $1.start }
        }
        return map
    }

    private func scan(_ buf: UnsafeBufferPointer<UInt8>, from: Int, to end: Int) -> Int {
        XmltvByteScanner.scan(
            buf,
            from: from,
            to: end,
            interestKeys: interestKeys,
            maxPerChannel: maxPerChannel,
            windowStart: windowStart,
            windowEnd: windowEnd,
            into: &map
        )
    }
}

/// URLSession delegate that streams the response body straight into an
/// `XmltvStreamScanner` on the session's delegate queue (never the main thread).
final class StreamingXmltvDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let scanner: XmltvStreamScanner
    private let maxBytes: Int64
    private let onProgress: (@Sendable (Int64, Int64) -> Void)?
    private let progressEvery: Int64 = 4 * 1024 * 1024
    private var nextProgressAt: Int64

    private(set) var statusCode = 0
    private(set) var received: Int64 = 0
    private(set) var expected: Int64 = -1
    private(set) var etag: String?
    private(set) var lastModified: String?
    private(set) var tooLarge = false

    private var continuation: CheckedContinuation<Void, Error>?
    private weak var task: URLSessionTask?

    init(
        scanner: XmltvStreamScanner,
        maxBytes: Int64,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) {
        self.scanner = scanner
        self.maxBytes = maxBytes
        self.onProgress = onProgress
        self.nextProgressAt = progressEvery
    }

    /// Resume the task and wait for completion. Task cancellation cancels the download.
    func run(_ dataTask: URLSessionDataTask) async throws {
        task = dataTask
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                continuation = cont
                dataTask.resume()
            }
        } onCancel: {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            statusCode = http.statusCode
            etag = http.value(forHTTPHeaderField: "ETag")
            lastModified = http.value(forHTTPHeaderField: "Last-Modified")
        }
        expected = response.expectedContentLength
        if expected > maxBytes {
            tooLarge = true
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard (200...299).contains(statusCode) else { return }
        received += Int64(data.count)
        if received > maxBytes {
            tooLarge = true
            dataTask.cancel()
            return
        }
        scanner.feed(data)
        if received >= nextProgressAt {
            nextProgressAt = received + progressEvery
            onProgress?(received, expected)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let cont = continuation
        continuation = nil
        if let error {
            cont?.resume(throwing: error)
        } else {
            cont?.resume()
        }
    }
}

// MARK: - Disk SAX parser (fallback, low RAM)

/// Streams the XMLTV **file** with Foundation's `XMLParser` — never loads the full document as a String.
/// Used only when `XmltvByteScanner` finds no programmes.
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
    /// Programme is outside the window / not wanted: skip text capture entirely.
    private var skipProgramme = false
    private var captureTitle = false
    private var captureCategory = false

    private enum Element {
        case programme, title, category
    }

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
            delegate.map[key]?.sort { $0.start < $1.start }
        }
        return delegate.map
    }

    /// Element classification without lowercasing every name (`desc`, `icon`, … are the bulk).
    private static func element(_ name: String) -> Element? {
        guard let first = name.utf8.first else { return nil }
        switch first {
        case UInt8(ascii: "p"), UInt8(ascii: "P"):
            return name == "programme" || name.lowercased() == "programme" ? .programme : nil
        case UInt8(ascii: "t"), UInt8(ascii: "T"):
            return name == "title" || name.lowercased() == "title" ? .title : nil
        case UInt8(ascii: "c"), UInt8(ascii: "C"):
            return name == "category" || name.lowercased() == "category" ? .category : nil
        default:
            return nil
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard let element = Self.element(elementName) else { return }
        switch element {
        case .programme:
            inProgramme = true
            currentTitle = nil
            currentCategories = []
            currentText = ""
            currentChannel = attributeDict["channel"]
            currentStart = attributeDict["start"].flatMap { XmltvTime.parse($0) }
            currentEnd = attributeDict["stop"].flatMap { XmltvTime.parse($0) }
            // Decide now so out-of-window programmes never accumulate text.
            skipProgramme = true
            if let channel = currentChannel, let start = currentStart, let end = currentEnd,
               end > windowStart, start < windowEnd,
               (map[channel]?.count ?? 0) < maxPerChannel {
                skipProgramme = !(interestKeys.isEmpty
                    || interestKeys.contains(channel)
                    || interestKeys.contains(channel.lowercased()))
            }
        case .title:
            if inProgramme, !skipProgramme {
                captureTitle = true
                currentText = ""
            }
        case .category:
            if inProgramme, !skipProgramme {
                captureCategory = true
                currentText = ""
            }
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
        guard let element = Self.element(elementName) else { return }
        switch element {
        case .title:
            guard captureTitle else { return }
            currentTitle = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            captureTitle = false
            currentText = ""
        case .category:
            guard captureCategory else { return }
            let cat = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cat.isEmpty, currentCategories.count < 8 {
                currentCategories.append(cat)
            }
            captureCategory = false
            currentText = ""
        case .programme:
            defer {
                inProgramme = false
                skipProgramme = false
                currentChannel = nil
                currentStart = nil
                currentEnd = nil
                currentTitle = nil
                currentCategories = []
            }
            guard !skipProgramme,
                  let channel = currentChannel,
                  let start = currentStart,
                  let end = currentEnd else { return }
            map[channel, default: []].append(
                EpgProgram(
                    channelKey: channel,
                    title: (currentTitle?.isEmpty == false ? currentTitle! : "Program"),
                    start: start,
                    end: end,
                    description: nil,
                    categories: currentCategories
                )
            )
        }
    }
}
