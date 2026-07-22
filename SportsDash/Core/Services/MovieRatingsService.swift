import Foundation

/// Non-blocking movie ratings lookup (OMDb primary for RT-style critic %, TMDB fallback).
/// Never throws into UI — failures return nil. Results cached on disk with TTL.
actor MovieRatingsService {
    static let shared = MovieRatingsService()

    static let omdbKeyAccount = "omdb_api_key"
    static let tmdbKeyAccount = "tmdb_api_key"
    private static let cacheFileName = "movie_ratings_cache.json"
    private static let cacheTTL: TimeInterval = 7 * 24 * 3600

    private var memory: [String: MovieRating] = [:]
    private var negativeCache: [String: Date] = [:]
    private var loadedDisk = false

    // MARK: - Public

    func rating(
        forTitle rawTitle: String,
        year: Int? = nil,
        isMovieHint: Bool = true
    ) async -> MovieRating? {
        guard isMovieHint else { return nil }
        let (title, parsedYear) = MovieTitleParser.parse(rawTitle)
        guard title.count >= 2 else { return nil }
        let y = year ?? parsedYear
        let key = MovieTitleParser.cacheKey(title: title, year: y)

        await ensureDiskLoaded()
        if let hit = memory[key], hit.hasAnyScore {
            if Date().timeIntervalSince(hit.fetchedAt) < Self.cacheTTL {
                return hit
            }
        }
        if let neg = negativeCache[key], Date().timeIntervalSince(neg) < 6 * 3600 {
            return nil
        }

        let omdbKey = await MainActor.run { KeychainStore.get(account: Self.omdbKeyAccount) }
            ?? ProcessInfo.processInfo.environment["OMDB_API_KEY"]
        let tmdbKey = await MainActor.run { KeychainStore.get(account: Self.tmdbKeyAccount) }
            ?? ProcessInfo.processInfo.environment["TMDB_API_KEY"]

        // No keys at all — fail closed quietly
        let hasOmdb = omdbKey.map { !$0.isEmpty } ?? false
        let hasTmdb = tmdbKey.map { !$0.isEmpty } ?? false
        guard hasOmdb || hasTmdb else { return nil }

        if let omdbKey, !omdbKey.isEmpty {
            if let r = await fetchOMDb(title: title, year: y, apiKey: omdbKey, cacheKey: key) {
                memory[key] = r
                negativeCache.removeValue(forKey: key)
                await persistDisk()
                return r
            }
        }
        if let tmdbKey, !tmdbKey.isEmpty {
            if let r = await fetchTMDB(title: title, year: y, apiKey: tmdbKey, cacheKey: key) {
                memory[key] = r
                negativeCache.removeValue(forKey: key)
                await persistDisk()
                return r
            }
        }

        negativeCache[key] = Date()
        return nil
    }

    /// Convenience for EPG programs.
    func rating(for program: EpgProgram, channelGroup: String? = nil, channelName: String? = nil) async -> MovieRating? {
        let hint = MovieDetection.isMovieCandidate(
            title: program.title,
            categories: program.categories,
            channelGroup: channelGroup,
            channelName: channelName
        )
        return await rating(forTitle: program.title, year: nil, isMovieHint: hint)
    }

    /// Debug/settings: verify keys + network with a known title.
    func testLookup(title: String = "Inception") async -> String {
        let omdb = await MainActor.run { KeychainStore.get(account: Self.omdbKeyAccount) }
        let tmdb = await MainActor.run { KeychainStore.get(account: Self.tmdbKeyAccount) }
        let omdbOK = omdb.map { !$0.isEmpty } ?? false
        let tmdbOK = tmdb.map { !$0.isEmpty } ?? false
        if !omdbOK && !tmdbOK {
            return "No API keys in Keychain. Save OMDb and/or TMDB under Settings → General."
        }
        // Bypass negative cache for test
        let (clean, year) = MovieTitleParser.parse(title)
        let key = MovieTitleParser.cacheKey(title: clean, year: year)
        negativeCache.removeValue(forKey: key)
        memory.removeValue(forKey: key)

        if let r = await rating(forTitle: title, year: year, isMovieHint: true) {
            var parts: [String] = ["OK · \(r.source) · \(r.title)"]
            if let c = r.criticLabel { parts.append("Critic \(c)") }
            if let a = r.audienceLabel { parts.append("Audience \(a)") }
            return parts.joined(separator: " · ")
        }
        var hint = "No score for “\(clean)”."
        if omdbOK { hint += " OMDb key present." }
        if tmdbOK { hint += " TMDB key present." }
        hint += " Check key validity / network."
        return hint
    }

    // MARK: - OMDb

    private func fetchOMDb(title: String, year: Int?, apiKey: String, cacheKey: String) async -> MovieRating? {
        // Try with type=movie first, then without (some EPGs match series-like titles).
        if let r = await fetchOMDbOnce(title: title, year: year, apiKey: apiKey, cacheKey: cacheKey, typeMovie: true) {
            return r
        }
        return await fetchOMDbOnce(title: title, year: year, apiKey: apiKey, cacheKey: cacheKey, typeMovie: false)
    }

    private func fetchOMDbOnce(
        title: String,
        year: Int?,
        apiKey: String,
        cacheKey: String,
        typeMovie: Bool
    ) async -> MovieRating? {
        var comps = URLComponents(string: "https://www.omdbapi.com/")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "t", value: title),
            URLQueryItem(name: "apikey", value: apiKey),
        ]
        if typeMovie {
            items.append(URLQueryItem(name: "type", value: "movie"))
        }
        if let year { items.append(URLQueryItem(name: "y", value: String(year))) }
        comps.queryItems = items
        guard let url = comps.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if let resp = json["Response"] as? String, resp == "False" { return nil }

            let resolvedTitle = (json["Title"] as? String) ?? title
            let resolvedYear = Int((json["Year"] as? String)?.prefix(4) ?? "") ?? year

            var critic: Int?
            var audience: Int?
            if let ratings = json["Ratings"] as? [[String: Any]] {
                for r in ratings {
                    let src = (r["Source"] as? String ?? "").lowercased()
                    let val = r["Value"] as? String ?? ""
                    if src.contains("rotten") {
                        critic = Self.parsePercent(val)
                    } else if src.contains("internet movie database") || src == "imdb" {
                        if let slash = val.split(separator: "/").first, let d = Double(slash) {
                            audience = Int((d * 10).rounded())
                        }
                    }
                }
            }
            if audience == nil, let imdb = json["imdbRating"] as? String, let d = Double(imdb), d > 0 {
                audience = Int((d * 10).rounded())
            }
            // Metascore as weak critic if RT missing
            if critic == nil, let meta = json["Metascore"] as? String, let m = Int(meta), (0 ... 100).contains(m) {
                critic = m
            }

            guard critic != nil || audience != nil else { return nil }
            return MovieRating(
                cacheKey: cacheKey,
                title: resolvedTitle,
                year: resolvedYear,
                criticScore: critic,
                audienceScore: audience,
                source: "OMDb",
                fetchedAt: Date(),
                posterURL: json["Poster"] as? String
            )
        } catch {
            return nil
        }
    }

    // MARK: - TMDB fallback

    private func fetchTMDB(title: String, year: Int?, apiKey: String, cacheKey: String) async -> MovieRating? {
        var search = URLComponents(string: "https://api.themoviedb.org/3/search/movie")!
        var items = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        if let year { items.append(URLQueryItem(name: "year", value: String(year))) }
        search.queryItems = items
        guard let searchURL = search.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: searchURL)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first else { return nil }

            let resolvedTitle = (first["title"] as? String) ?? title
            var resolvedYear = year
            if let rd = first["release_date"] as? String, rd.count >= 4 {
                resolvedYear = Int(rd.prefix(4))
            }
            let vote = first["vote_average"] as? Double
            let audience = vote.map { Int(($0 * 10).rounded()) }
            guard let audience, audience > 0 else { return nil }

            var poster: String?
            if let path = first["poster_path"] as? String, !path.isEmpty {
                poster = "https://image.tmdb.org/t/p/w185\(path)"
            }

            return MovieRating(
                cacheKey: cacheKey,
                title: resolvedTitle,
                year: resolvedYear,
                criticScore: nil,
                audienceScore: min(100, audience),
                source: "TMDB",
                fetchedAt: Date(),
                posterURL: poster
            )
        } catch {
            return nil
        }
    }

    // MARK: - Helpers / cache

    private static func parsePercent(_ raw: String) -> Int? {
        let digits = raw.filter(\.isNumber)
        guard let n = Int(digits), (0 ... 100).contains(n) else { return nil }
        return n
    }

    private func ensureDiskLoaded() async {
        guard !loadedDisk else { return }
        loadedDisk = true
        guard let url = Self.cacheURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: MovieRating].self, from: data) else { return }
        let now = Date()
        for (k, v) in decoded {
            if now.timeIntervalSince(v.fetchedAt) < Self.cacheTTL {
                memory[k] = v
            }
        }
    }

    private func persistDisk() async {
        guard let url = Self.cacheURL() else { return }
        let payload = memory
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func cacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheFileName)
    }
}
