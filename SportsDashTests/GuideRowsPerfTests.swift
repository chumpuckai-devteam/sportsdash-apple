import XCTest

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

final class GuideRowsPerfTests: XCTestCase {

    func testDedupe2000Channels() {
        let channels: [IptvChannel] = (0..<2000).map { i in
            PerfFixtures.channel(i, name: "ESPN \(i % 400)")
        }
        var epg: [String: [EpgProgram]] = [:]
        let now = Date()
        for i in stride(from: 0, to: 2000, by: 3) {
            let id = "ch-\(i)"
            epg[id] = [
                EpgProgram(
                    channelKey: id,
                    title: "Live \(i)",
                    start: now.addingTimeInterval(-1800),
                    end: now.addingTimeInterval(1800)
                )
            ]
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = GuideView.dedupeChannels(channels, epg: epg)
        }
    }
}
