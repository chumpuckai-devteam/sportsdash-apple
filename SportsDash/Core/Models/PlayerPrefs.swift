import Foundation

// MARK: - Aspect

enum PlayerAspectMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto, fit, fill, ratio16x9, ratio4x3, stretch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .fit: return "Fit"
        case .fill: return "Fill / crop"
        case .ratio16x9: return "16:9"
        case .ratio4x3: return "4:3"
        case .stretch: return "Stretch"
        }
    }
}

// MARK: - Primary video player (UHF-style)

enum PrimaryVideoPlayer: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Detect TS vs HLS — VLC for TS, AVPlayer for HLS (recommended).
    case auto
    /// libVLC hard engine (MobileVLCKit / TVVLCKit) — main IPTV engine
    case vlc
    /// Apple AVKit / AVPlayer
    case avKit
    /// Legacy decode only → treated as VLC
    case ksPlayer
    case mpvKit

    var id: String { rawValue }

    static var selectableCases: [PrimaryVideoPlayer] {
        [.auto, .vlc, .avKit]
    }

    var label: String {
        switch self {
        case .auto: return "Auto · TS→VLC · HLS→AV · Default"
        case .vlc: return "VLC (libVLC) · Main"
        case .avKit: return "AVKit (Native)"
        case .ksPlayer: return "KSPlayer (legacy→VLC)"
        case .mpvKit: return "MPV (legacy→VLC)"
        }
    }

    var detail: String {
        switch self {
        case .auto:
            return "Detects stream type from the URL. MPEG-TS → VLC; HLS .m3u8 → AVPlayer. Best default for IPTV."
        case .vlc:
            return "libVLC via MobileVLCKit/TVVLCKit (LGPL). Strong TS/IPTV. Same engine family for Android later."
        case .avKit:
            return "Apple’s player. Best clean HLS + system AirPlay/PiP; weaker on raw TS."
        case .ksPlayer, .mpvKit:
            return "Legacy preference — SportsDash now uses VLC as the hard engine."
        }
    }
}

// MARK: - Live stream container preference

enum LiveStreamFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case ts
    case m3u8

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ts: return "TS (.ts)"
        case .m3u8: return "M3U8 (.m3u8)"
        }
    }
}

// MARK: - Theme

enum AppThemeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Guide layout

enum GuideLayoutMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Channel × time timeline
    case list
    /// Card-style Now / Next
    case grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        }
    }
}

// MARK: - Playlist refresh

enum PlaylistRefreshInterval: Int, CaseIterable, Identifiable, Codable, Sendable {
    case manual = 0
    case hourly = 1
    case every6Hours = 6
    case daily = 24
    case weekly = 168

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .hourly: return "Hourly"
        case .every6Hours: return "Every 6 hours"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

// MARK: - Launch tab

/// Root tabs the user can open on launch.
/// Note: standalone Channels tab was removed — Guide list/grid is the browse surface.
enum LaunchTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case scores, guide, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scores: return "Scores"
        case .guide: return "Guide"
        case .settings: return "Settings"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "guide": self = .guide
        case "settings": self = .settings
        case "channels":
            // Legacy pref → Guide (Channels tab removed)
            self = .guide
        default:
            self = .scores
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Combined prefs (persisted)

/// Player + general + UI preferences (UHF-inspired).
struct PlayerPrefs: Codable, Sendable, Equatable {
    // Player
    var aspect: PlayerAspectMode = .auto
    var primaryPlayer: PrimaryVideoPlayer = .auto
    var fallbackPlayers: Bool = true
    /// Preferred forward buffer (seconds), 1…15.
    var bufferSeconds: Double = 3
    var adaptiveFrameRate: Bool = true
    var hardwareDecode: Bool = true
    var asynchronousDecompression: Bool = false

    // General
    var userAgent: String = "VLC/3.0.21 LibVLC/3.0.21"
    var preferredLiveFormat: LiveStreamFormat = .ts
    var playlistRefresh: PlaylistRefreshInterval = .daily

    // UI
    var theme: AppThemeMode = .dark
    var guideLayout: GuideLayoutMode = .list
    var cleanUpNames: Bool = true
    var launchTab: LaunchTab = .scores

    enum CodingKeys: String, CodingKey {
        case aspect, primaryPlayer, fallbackPlayers, bufferSeconds
        case adaptiveFrameRate, hardwareDecode, asynchronousDecompression
        case userAgent, preferredLiveFormat, playlistRefresh
        case theme, guideLayout, cleanUpNames, launchTab
        case engine
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aspect = try c.decodeIfPresent(PlayerAspectMode.self, forKey: .aspect) ?? .auto
        bufferSeconds = try c.decodeIfPresent(Double.self, forKey: .bufferSeconds) ?? 3
        adaptiveFrameRate = try c.decodeIfPresent(Bool.self, forKey: .adaptiveFrameRate) ?? true
        hardwareDecode = try c.decodeIfPresent(Bool.self, forKey: .hardwareDecode) ?? true
        asynchronousDecompression = try c.decodeIfPresent(Bool.self, forKey: .asynchronousDecompression) ?? false
        userAgent = try c.decodeIfPresent(String.self, forKey: .userAgent) ?? "VLC/3.0.21 LibVLC/3.0.21"
        preferredLiveFormat = try c.decodeIfPresent(LiveStreamFormat.self, forKey: .preferredLiveFormat) ?? .ts
        playlistRefresh = try c.decodeIfPresent(PlaylistRefreshInterval.self, forKey: .playlistRefresh) ?? .daily
        theme = try c.decodeIfPresent(AppThemeMode.self, forKey: .theme) ?? .dark
        guideLayout = try c.decodeIfPresent(GuideLayoutMode.self, forKey: .guideLayout) ?? .list
        cleanUpNames = try c.decodeIfPresent(Bool.self, forKey: .cleanUpNames) ?? true
        launchTab = try c.decodeIfPresent(LaunchTab.self, forKey: .launchTab) ?? .scores

        // Decode as String so unknown/legacy values (vlc, auto) don't fail the whole prefs blob.
        if let raw = try c.decodeIfPresent(String.self, forKey: .primaryPlayer) {
            switch raw {
            case PrimaryVideoPlayer.auto.rawValue:
                primaryPlayer = .auto
            case PrimaryVideoPlayer.vlc.rawValue, "vlc",
                 PrimaryVideoPlayer.ksPlayer.rawValue, "ffmpeg",
                 PrimaryVideoPlayer.mpvKit.rawValue, "mpv":
                primaryPlayer = .vlc
            case PrimaryVideoPlayer.avKit.rawValue, "avPlayer":
                primaryPlayer = .avKit
            default:
                primaryPlayer = .auto
            }
            fallbackPlayers = try c.decodeIfPresent(Bool.self, forKey: .fallbackPlayers) ?? true
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .engine) {
            // Migrate old PlayerEngine raw values
            switch legacy {
            case "avPlayer":
                primaryPlayer = .avKit
                fallbackPlayers = false
            case "ffmpeg", "ksPlayer", "vlc", "mpv":
                primaryPlayer = .vlc
                fallbackPlayers = false
            default: // auto
                primaryPlayer = .auto
                fallbackPlayers = true
            }
        } else {
            primaryPlayer = .auto
            fallbackPlayers = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(aspect, forKey: .aspect)
        try c.encode(primaryPlayer, forKey: .primaryPlayer)
        try c.encode(fallbackPlayers, forKey: .fallbackPlayers)
        try c.encode(bufferSeconds, forKey: .bufferSeconds)
        try c.encode(adaptiveFrameRate, forKey: .adaptiveFrameRate)
        try c.encode(hardwareDecode, forKey: .hardwareDecode)
        try c.encode(asynchronousDecompression, forKey: .asynchronousDecompression)
        try c.encode(userAgent, forKey: .userAgent)
        try c.encode(preferredLiveFormat, forKey: .preferredLiveFormat)
        try c.encode(playlistRefresh, forKey: .playlistRefresh)
        try c.encode(theme, forKey: .theme)
        try c.encode(guideLayout, forKey: .guideLayout)
        try c.encode(cleanUpNames, forKey: .cleanUpNames)
        try c.encode(launchTab, forKey: .launchTab)
    }

    /// Clamped buffer seconds for hard engine caching.
    var clampedBufferSeconds: Double {
        min(15, max(1, bufferSeconds))
    }
}

// MARK: - Channel name cleanup

enum ChannelNameCleanup {
    /// Strip common IPTV quality / codec noise when “Clean up names” is on.
    static func displayName(_ raw: String, enabled: Bool) -> String {
        guard enabled else { return raw }
        var s = raw
        let patterns = [
            #"\s*\[.*?\]"#,
            #"\s*\((?:4K|UHD|FHD|HD|SD|HEVC|H\.?265|H\.?264|60FPS|50FPS|1080p|720p|2160p)[^)]*\)"#,
            #"\s+(?:4K|UHD|FHD|HD|SD|HEVC|H265|H264|1080P|720P|2160P)\b"#,
            #"\s{2,}"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Dashboard filter

enum DashboardFilter: String, CaseIterable, Identifiable, Sendable {
    /// Live / Upcoming / All only — no separate favorite-games filter (S-PARITY.FAV.3).
    /// Favorite **teams** pin first inside each filter (S-PARITY.FAV.2).
    case live, upcoming, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live: return "LIVE"
        case .upcoming: return "UPCOMING"
        case .all: return "ALL"
        }
    }
}
