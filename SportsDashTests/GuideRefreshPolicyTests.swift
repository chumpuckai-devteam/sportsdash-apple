import XCTest

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

final class GuideRefreshPolicyTests: XCTestCase {
    func testNoOpWhileLoading() {
        let last = Date().addingTimeInterval(-4 * 3600)
        XCTAssertFalse(
            GuideRefreshPolicy.shouldReloadEpg(isLoading: true, lastReload: last),
            "poll must not start a second XMLTV load"
        )
    }

    func testReloadsWhenStale() {
        let last = Date().addingTimeInterval(-4 * 3600)
        XCTAssertTrue(GuideRefreshPolicy.shouldReloadEpg(isLoading: false, lastReload: last))
    }

    func testSkipsFreshMap() {
        let last = Date().addingTimeInterval(-30 * 60)
        XCTAssertFalse(GuideRefreshPolicy.shouldReloadEpg(isLoading: false, lastReload: last))
    }

    func testReloadsWhenNeverLoaded() {
        XCTAssertTrue(GuideRefreshPolicy.shouldReloadEpg(isLoading: false, lastReload: nil))
    }
}
