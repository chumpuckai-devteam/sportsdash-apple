import XCTest

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

final class ScoreboardPerfTests: XCTestCase {

    func testSportSections() {
        let leagues = Array(SportLeague.allCases)
        let games: [Game] = (0..<400).map { i in
            let status: GameStatus
            switch i % 3 {
            case 0: status = .live
            case 1: status = .upcoming
            default: status = .final_
            }
            return PerfFixtures.game(
                id: "g-\(i)",
                league: leagues[i % leagues.count],
                status: status,
                start: Date().addingTimeInterval(Double(i) * 60)
            )
        }
        let favs = Set(games.prefix(20).map(\.home.id))

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = ScoreboardGrouping.sportSections(from: games, favoriteTeamIds: favs)
        }
    }
}
