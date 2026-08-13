import XCTest

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

final class DashboardFilterTests: XCTestCase {

    // TDD for final label/raw value parity (iOS side, Android ScoresFilter mirror)

    func testDashboardFilterLabelAndRaw() {
        XCTAssertEqual(DashboardFilter.live.label, "Live")
        XCTAssertEqual(DashboardFilter.live.rawValue, "live")
        XCTAssertEqual(DashboardFilter.upcoming.label, "Upcoming")
        XCTAssertEqual(DashboardFilter.upcoming.rawValue, "upcoming")
        XCTAssertEqual(DashboardFilter.final.label, "Final")
        XCTAssertEqual(DashboardFilter.final.rawValue, "final")
        XCTAssertEqual(DashboardFilter.final.id, "final")

        // allCases
        XCTAssertEqual(DashboardFilter.allCases.count, 3)
        XCTAssertTrue(DashboardFilter.allCases.contains(.final))
    }

    // Pure test for visible loading ownership separate from result gen (item 5 fix)
    // Stale visible can retire its token; silent never creates/clears; latest visible owns.
    func testVisibleLoadingTrackerStaleRetireAndSilentNoTouch() {
        var tracker = VisibleLoadingTracker()

        // visible1 starts -> loading
        let t1 = tracker.beginVisible()
        XCTAssertTrue(tracker.isVisibleLoading)

        // silent starts, no token created
        // (no call)

        // visible2 starts
        let t2 = tracker.beginVisible()
        XCTAssertTrue(tracker.isVisibleLoading)

        // stale t1 retires, still loading because t2
        let still = tracker.retireVisible(token: t1)
        XCTAssertTrue(still, "t2 still owns")
        XCTAssertTrue(tracker.isVisibleLoading)

        // t2 retires -> not loading
        let still2 = tracker.retireVisible(token: t2)
        XCTAssertFalse(still2)
        XCTAssertFalse(tracker.isVisibleLoading)

        // another visible after
        let t3 = tracker.beginVisible()
        XCTAssertTrue(tracker.isVisibleLoading)
        _ = tracker.retireVisible(token: t3)
        XCTAssertFalse(tracker.isVisibleLoading)
    }
}
