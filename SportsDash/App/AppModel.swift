import Combine
import Foundation
import SwiftUI

/// Shared app state (scores, IPTV, preferences). Expanded as features land.
@MainActor
final class AppModel: ObservableObject {
    @Published var games: [Game] = []
    @Published var channels: [IptvChannel] = []
    @Published var isLoadingScores = false
    @Published var scoresError: String?
    @Published var lastUpdated: Date?

    let sportsAPI = SportsAPI()
    let iptvService = IptvService()
    let matching = MatchingService()

    func refreshScores() async {
        isLoadingScores = true
        scoresError = nil
        defer { isLoadingScores = false }
        do {
            games = try await sportsAPI.fetchScoreboards(leagues: SportLeague.defaults)
            lastUpdated = Date()
        } catch {
            scoresError = error.localizedDescription
        }
    }
}
