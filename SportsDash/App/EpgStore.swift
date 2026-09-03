import Combine
import Foundation

/// Guide state, split out of `AppModel` so EPG merges and status ticks only
/// invalidate views that show the guide. With `ObservableObject`, every
/// `@Published` write re-evaluates every view observing the object — while the
/// XMLTV load ran, that was Scores, Settings and the full-screen player too.
///
/// `AppModel` owns the loading logic and writes here; views observe this object
/// via `@EnvironmentObject` (injected alongside `AppModel`).
@MainActor
final class EpgStore: ObservableObject {
    @Published var epgByChannel: [String: [EpgProgram]] = [:]
    @Published var isLoadingEpg = false
    /// Channels with EPG entries loaded (may be empty lists).
    @Published var epgLoadedCount = 0
    @Published var lastEpgReload: Date?
    @Published var epgError: String?
    /// Human status while EPG loads (e.g. “Downloading full guide (XMLTV)…”).
    @Published var epgStatus: String?
    /// True while background short-EPG waves are running (not the same as bulk download).
    @Published var isAutoFillingEpg = false

    func programs(for channelId: String) -> [EpgProgram] {
        epgByChannel[channelId] ?? []
    }
}
