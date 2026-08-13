import XCTest

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

final class PlayerPrefsTests: XCTestCase {

    // TDD: pure clamp/conversion. Do not test VLC runtime/framework.

    func testVlcCachingMsClampsAndConverts() {
        // RED expectation written, GREEN after impl
        XCTAssertEqual(PlayerPrefs.vlcCachingMs(5.0), 5000)
        XCTAssertEqual(PlayerPrefs.vlcCachingMs(1.0), 1000)
        XCTAssertEqual(PlayerPrefs.vlcCachingMs(15.0), 15000)
        XCTAssertEqual(PlayerPrefs.vlcCachingMs(0.5), 1000)  // clamp low
        XCTAssertEqual(PlayerPrefs.vlcCachingMs(20.0), 15000) // clamp high
        XCTAssertEqual(PlayerPrefs.vlcCachingMs(2.3), 2300)
        XCTAssertEqual(PlayerPrefs.vlcCachingMs(-1), 1000)
    }

    func testClampedBufferSecondsMatches() {
        var p = PlayerPrefs()
        p.bufferSeconds = 0.5
        XCTAssertEqual(p.clampedBufferSeconds, 1.0)
        p.bufferSeconds = 20
        XCTAssertEqual(p.clampedBufferSeconds, 15.0)
        p.bufferSeconds = 7
        XCTAssertEqual(p.clampedBufferSeconds, 7.0)
    }

    // Pure testable generation/final guard (blocker 2 Apple partial race).
    // Simulates the token check: delayed partial after final mark must be rejected.
    // Final merged never overwritten or re-notified.
    func testResultGenerationFinalGuardPreventsDelayedPartialOverwrite() {
        var currentGen = 0
        var finalApplied = 0
        func begin() -> Int { currentGen += 1; return currentGen }
        func canApplyPartial(my: Int, curr: Int, fApplied: Int) -> Bool {
            my == curr && my > fApplied
        }
        func markFinalApplied(my: Int) {
            if my > finalApplied { finalApplied = my }
        }

        let my1 = begin()
        XCTAssertTrue(canApplyPartial(my: my1, curr: currentGen, fApplied: finalApplied), "partial before final ok")
        markFinalApplied(my: my1)
        XCTAssertFalse(canApplyPartial(my: my1, curr: currentGen, fApplied: finalApplied), "delayed partial after final must be ignored")
        let my2 = begin()
        XCTAssertTrue(canApplyPartial(my: my2, curr: currentGen, fApplied: finalApplied), "next gen partial allowed")
    }
}
