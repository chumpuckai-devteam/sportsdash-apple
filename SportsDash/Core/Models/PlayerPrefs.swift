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

    var videoGravity: String {
        switch self {
        case .fill: return "resizeAspectFill"
        case .stretch: return "resize"
        case .auto, .fit, .ratio16x9, .ratio4x3: return "resizeAspect"
        }
    }
}

struct PlayerPrefs: Codable, Sendable, Equatable {
    var aspect: PlayerAspectMode = .auto
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
