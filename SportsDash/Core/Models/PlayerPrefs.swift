import Foundation

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

/// Which decoder stack to use for IPTV streams.
enum PlayerEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    /// FFmpeg first (handles more formats), AVPlayer as fallback.
    case auto
    /// Apple AVPlayer only (HLS-friendly, fails more on messy IPTV).
    case avPlayer
    /// FFmpeg / KSMEPlayer only (best IPTV compatibility).
    case ffmpeg

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto (FFmpeg → AVPlayer)"
        case .avPlayer: return "AVPlayer (native)"
        case .ffmpeg: return "FFmpeg (KSPlayer)"
        }
    }

    var detail: String {
        switch self {
        case .auto:
            return "Tries FFmpeg first for broader format support, then falls back to AVPlayer."
        case .avPlayer:
            return "Apple’s player. Fast for clean HLS, often fails on TS / exotic IPTV."
        case .ffmpeg:
            return "KSPlayer FFmpeg engine. Best for live IPTV when native playback fails."
        }
    }
}

struct PlayerPrefs: Codable, Sendable, Equatable {
    var aspect: PlayerAspectMode = .auto
    /// Default FFmpeg-first — native AVPlayer is inconsistent on many panels.
    var engine: PlayerEngine = .auto
    var hardwareDecode: Bool = true
}

enum DashboardFilter: String, CaseIterable, Identifiable, Sendable {
    case live, upcoming, favorites, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live: return "LIVE"
        case .upcoming: return "UPCOMING"
        case .favorites: return "★ FAVES"
        case .all: return "ALL"
        }
    }
}
