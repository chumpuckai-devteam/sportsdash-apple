import XCTest

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

final class XmltvPerfTests: XCTestCase {

    private static var xmlURL: URL!
    private static let targetBytes = 50 * 1024 * 1024

    override class func setUp() {
        super.setUp()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmltv-perf-50mb.xml")
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
           size.intValue >= targetBytes {
            xmlURL = url
            return
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            xmlURL = url
            return
        }
        var written = 0
        func append(_ s: String) {
            let data = Data(s.utf8)
            handle.write(data)
            written += data.count
        }
        append("<?xml version=\"1.0\" encoding=\"UTF-8\"?><tv>\n")
        for i in 0..<40 {
            append("<channel id=\"c\(i)\"><display-name>C\(i)</display-name></channel>\n")
        }
        let start = "20260101120000 +0000"
        let stop = "20260101130000 +0000"
        var i = 0
        while written < targetBytes - 64 {
            append(
                "<programme start=\"\(start)\" stop=\"\(stop)\" channel=\"c\(i % 40)\"><title>P\(i)</title></programme>\n"
            )
            i += 1
        }
        append("</tv>\n")
        try? handle.close()
        xmlURL = url
    }

    func testStreamScan50MB() throws {
        let url = Self.xmlURL!
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThanOrEqual(data.count, 40 * 1024 * 1024)

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let scanner = XmltvStreamScanner(
                interestKeys: [],
                maxPerChannel: 12,
                hoursBehind: 24 * 400,
                hoursAhead: 24 * 400
            )
            var offset = 0
            let chunk = 64 * 1024
            while offset < data.count {
                let end = min(offset + chunk, data.count)
                scanner.feed(data.subdata(in: offset..<end))
                offset = end
            }
            _ = scanner.finish()
        }
    }
}
