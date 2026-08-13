import XCTest

#if os(iOS)
@testable import SportsDash

final class GameNotificationServiceTests: XCTestCase {

    private func makeGame(id: String, homeScore: Int? = nil, awayScore: Int? = nil, status: GameStatus = .live, start: Date = Date()) -> Game {
        let league = SportLeague.defaults[0]
        let home = TeamInfo(id: "h", name: "Home", abbreviation: "H", score: homeScore)
        let away = TeamInfo(id: "a", name: "Away", abbreviation: "A", score: awayScore)
        return Game(
            id: id,
            league: league,
            home: home,
            away: away,
            status: status,
            startTime: start,
            statusDetail: nil,
            period: nil,
            clock: nil,
            broadcasts: [],
            venue: nil,
            eventName: nil,
            isHeadToHead: false
        )
    }

    func testScoreDidIncrease_detectsIncrease() {
        // pure helper
        XCTAssertTrue(GameNotificationService.test_scoreDidIncrease(currentHome: 1, currentAway: 0, prevHome: 0, prevAway: 0))
        XCTAssertTrue(GameNotificationService.test_scoreDidIncrease(currentHome: 0, currentAway: 1, prevHome: 0, prevAway: 0))
        XCTAssertFalse(GameNotificationService.test_scoreDidIncrease(currentHome: 1, currentAway: 1, prevHome: 1, prevAway: 1))
        XCTAssertFalse(GameNotificationService.test_scoreDidIncrease(currentHome: 0, currentAway: 0, prevHome: 1, prevAway: 0))
        XCTAssertFalse(GameNotificationService.test_scoreDidIncrease(currentHome: nil, currentAway: nil, prevHome: nil, prevAway: nil))
        // treat nil as 0
        XCTAssertTrue(GameNotificationService.test_scoreDidIncrease(currentHome: 1, currentAway: nil, prevHome: nil, prevAway: nil))
    }

    func testGoalId_stableForSameScore() {
        let id1 = GameNotificationService.test_goalId(gameId: "g1", home: 2, away: 1)
        let id2 = GameNotificationService.test_goalId(gameId: "g1", home: 2, away: 1)
        XCTAssertEqual(id1, id2)
        let id3 = GameNotificationService.test_goalId(gameId: "g1", home: 3, away: 1)
        XCTAssertNotEqual(id1, id3)
    }

    func testMergeSnapshots_neverDropsKeysMissingFromObserved() {
        let existing: [String: GameNotificationService.TestSnapshot] = [
            "g1": GameNotificationService.TestSnapshot(home: 0, away: 0, status: .upcoming),
            "g2": GameNotificationService.TestSnapshot(home: 1, away: 0, status: .live)
        ]
        let observed: [String: GameNotificationService.TestSnapshot] = [
            "g2": GameNotificationService.TestSnapshot(home: 2, away: 0, status: .live),  // update
            "g3": GameNotificationService.TestSnapshot(home: 0, away: 0, status: .upcoming)  // new
        ]
        let merged = GameNotificationService.test_mergeSnapshots(existing: existing, observed: observed)
        XCTAssertEqual(merged.count, 3)
        XCTAssertNotNil(merged["g1"])  // kept, not in observed
        XCTAssertEqual(merged["g2"]?.home, 2)  // updated
        XCTAssertNotNil(merged["g3"])
    }

    func testPruneByAge_removesOld() {
        let now = Date()
        let old = now.addingTimeInterval(-50 * 3600)
        let recentFinal = now.addingTimeInterval(-3 * 3600)
        let oldFinal = now.addingTimeInterval(-10 * 3600)
        let snaps: [String: GameNotificationService.TestSnapshot] = [
            "old": GameNotificationService.TestSnapshot(home: 0, away: 0, status: .live, updatedAt: old),
            "recentFinal": GameNotificationService.TestSnapshot(home: 2, away: 1, status: .final_, updatedAt: recentFinal),
            "oldFinal": GameNotificationService.TestSnapshot(home: 3, away: 1, status: .final_, updatedAt: oldFinal),
            "fresh": GameNotificationService.TestSnapshot(home: 1, away: 0, status: .live, updatedAt: now)
        ]
        let pruned = GameNotificationService.test_pruneByAge(snaps)
        XCTAssertEqual(pruned.count, 2)
        XCTAssertNotNil(pruned["recentFinal"])
        XCTAssertNotNil(pruned["fresh"])
        XCTAssertNil(pruned["old"])
        XCTAssertNil(pruned["oldFinal"])
    }

    func testRealProductionDiskRoundTrip_usesLoadPersistMergeFromIOSImpl() {
        // Uses REAL production persist/load/merge (via injected suite defaults) — no copies.
        // This replaces previous weak sim tests.
        let suiteName = "sportsdash.test.notif.\(UUID().uuidString)"
        guard let ud = UserDefaults(suiteName: suiteName) else {
            XCTFail("could not create suite defaults")
            return
        }
        IOSImpl.testUserDefaults = ud
        defer {
            IOSImpl.testUserDefaults = nil
            ud.removePersistentDomain(forName: suiteName)
        }

        // clear
        ud.removeObject(forKey: "last_game_scores_snapshots_v1")

        // 1. write baseline g1 0-0 via PRODUCTION persist
        let baseline = IOSImpl.Snapshot(home: 0, away: 0, status: .live, updatedAt: Date())
        IOSImpl.shared.testPersistLastScores(["g1": baseline])

        // 2. clear in-memory (we load fresh for roundtrip test; lastScores is private)
        // 3. loads via PRODUCTION load
        let loaded = IOSImpl.shared.testLoadPersistedLastScores()
        XCTAssertNotNil(loaded["g1"], "baseline g1 must be persisted and loadable")
        XCTAssertEqual(loaded["g1"]?.home, 0)
        XCTAssertEqual(loaded["g1"]?.away, 0)

        // 4. merge partial without g1 , assert g1 retained (from disk baseline)
        let partial: [String: IOSImpl.Snapshot] = [
            "g2": IOSImpl.Snapshot(home: 0, away: 0, status: .upcoming, updatedAt: Date())
        ]
        let merged = IOSImpl.mergeSnapshots(existing: loaded, observed: partial)
        XCTAssertNotNil(merged["g1"], "g1 retained after partial merge missing it")
        XCTAssertNotNil(merged["g2"])

        // 5. asserts scoreDidIncrease for 1-0 vs loaded 0-0
        let prevG1 = loaded["g1"]!
        XCTAssertTrue(IOSImpl.scoreDidIncrease(currentHome: 1, currentAway: 0, prevHome: prevG1.home, prevAway: prevG1.away))
    }

    func test_startScheduleAction_decisions() {
        // pure decision helper
        XCTAssertEqual(GameNotificationService.test_startScheduleAction(touchStartSchedules: false, notifyStarts: true), "none")
        XCTAssertEqual(GameNotificationService.test_startScheduleAction(touchStartSchedules: false, notifyStarts: false), "none")
        XCTAssertEqual(GameNotificationService.test_startScheduleAction(touchStartSchedules: true, notifyStarts: true), "schedule")
        XCTAssertEqual(GameNotificationService.test_startScheduleAction(touchStartSchedules: true, notifyStarts: false), "clear")
    }
}

#endif
