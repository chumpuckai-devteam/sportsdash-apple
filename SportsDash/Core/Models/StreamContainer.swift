import Foundation

/// Best-effort stream container detection from URL path/query (no network probe).
enum StreamContainer: String, Sendable {
    case ts
    case hls
    case unknown

    /// Detect MPEG-TS vs HLS from a playback URL string.
    static func detect(_ urlString: String) -> StreamContainer {
        let raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .unknown }
        let lower = raw.lowercased()

        // Strip query/fragment for path checks.
        let path: String = {
            if let u = URL(string: raw) {
                return (u.path + " " + (u.query ?? "")).lowercased()
            }
            return lower
        }()

        // Explicit extensions / tokens
        if path.contains(".m3u8") || path.contains("m3u8") || path.contains("format=hls")
            || path.contains("/hls/") || path.contains("type=m3u") {
            return .hls
        }
        if path.contains(".ts") || path.contains("format=ts") || path.contains("extension=ts")
            || (path.contains("/live/") && !path.contains("m3u8")) {
            // Xtream live often: /live/user/pass/id  (raw TS) without extension
            if path.contains(".m3u8") { return .hls }
            return .ts
        }

        // Xtream Codes live path without extension → almost always MPEG-TS over HTTP.
        if lower.contains("/live/") && !lower.contains("m3u8") {
            return .ts
        }
        // movie/series with /movie/ often HLS or TS — leave unknown unless extension known
        return .unknown
    }

    var shortLabel: String {
        switch self {
        case .ts: return "TS"
        case .hls: return "HLS"
        case .unknown: return "?"
        }
    }
}
