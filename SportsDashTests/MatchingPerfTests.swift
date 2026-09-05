import XCTest

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

final class MatchingPerfTests: XCTestCase {

    func testBoardMatchIndex() {
        let leagues = Array(SportLeague.allCases)
        let games: [Game] = (0..<30).map { i in
            PerfFixtures.game(
                id: "g-\(i)",
                league: leagues[i % leagues.count],
                status: i % 3 == 0 ? .live : .upcoming
            )
        }
        let channels: [IptvChannel] = (0..<5_000).map { i in
            let name: String
            switch i % 7 {
            case 0: name = "ESPN \(i)"
            case 1: name = "Home g-\(i % 30) US"
            case 2: name = "Away g-\(i % 30)"
            default: name = "US Sports \(i)"
            }
            return PerfFixtures.channel(i, name: name)
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            _ = MatchingService().matchCountsByGameId(
                games: games,
                channels: channels,
                limit: 3
            )
        }
    }
}
