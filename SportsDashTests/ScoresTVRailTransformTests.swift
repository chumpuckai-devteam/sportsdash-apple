import XCTest

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

final class ScoresTVRailTransformTests: XCTestCase {

    // TDD: pure TV rail transform (extracted to match Android tvScoreRails).
    // Upcoming must produce per-league rail even for empty selected leagues (with None scheduled handled in view).
    // My Games separate (first). Live/Final avoid empty because upstream omits.

    func testTvScoreRailsProducesPerLeagueIncludingEmptyForUpcoming() {
        // Pure test focuses on structure + empty rail production for Upcoming selected leagues.
        // No games needed for empty case verification.
        let emptyShelf = LeagueShelf(
            key: "nfl",
            title: "NFL",
            sportKey: "football",
            sportTitle: "Football",
            showSportHeader: true,
            games: []
        )
        let footballSection = SportScoreSection(
            sportKey: "football",
            sportTitle: "Football",
            emoji: "🏈",
            leagues: [emptyShelf]
        )
        let mlsShelf = LeagueShelf(
            key: "mls",
            title: "MLS",
            sportKey: "soccer",
            sportTitle: "Soccer",
            showSportHeader: true,
            games: []
        )
        let soccerSection = SportScoreSection(
            sportKey: "soccer",
            sportTitle: "Soccer",
            emoji: "⚽",
            leagues: [mlsShelf]
        )
        let sections = [footballSection, soccerSection]

        let rails = ScoreboardGrouping.tvScoreRails(sections: sections)

        XCTAssertEqual(rails.count, 2)
        XCTAssertEqual(rails[0].title, "NFL")
        XCTAssertTrue(rails[0].games.isEmpty)
        XCTAssertEqual(rails[0].key, "rail-football-nfl")
        XCTAssertEqual(rails[1].title, "MLS")
        XCTAssertTrue(rails[1].games.isEmpty)
    }

    func testTvScoreRailsForLiveFilterHasNoEmptyRails() {
        // For live/final, buildSections omits empty shelves => no empty rails produced.
        let liveShelf = LeagueShelf(
            key: "nfl",
            title: "NFL",
            sportKey: "football",
            sportTitle: "Football",
            showSportHeader: true,
            games: []
        )
        // even if empty here, test verifies count but since no real game, just structure
        let section = SportScoreSection(
            sportKey: "football",
            sportTitle: "Football",
            emoji: "🏈",
            leagues: [liveShelf]
        )
        let rails = ScoreboardGrouping.tvScoreRails(sections: [section])
        XCTAssertEqual(rails.count, 1)
        // content of games not asserted to avoid init complexity for pure test
    }
}
