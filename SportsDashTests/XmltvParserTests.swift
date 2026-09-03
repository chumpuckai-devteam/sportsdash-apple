import XCTest

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

/// Byte scanner and XMLParser fallback must agree on the same guide file.
final class XmltvParserTests: XCTestCase {

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    private func xmltv(_ date: Date, tz: String = " +0000") -> String {
        Self.stamp.string(from: date) + tz
    }

    private func writeTemp(_ xml: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmltv-test-\(UUID().uuidString).xml")
        try xml.data(using: .utf8)!.write(to: url)
        return url
    }

    func testTimeParsePureMath() {
        let d = XmltvTime.parse("20240102030405 +0100")
        XCTAssertNotNil(d)
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(d, iso.date(from: "2024-01-02T02:04:05Z"))

        XCTAssertEqual(XmltvTime.parse("20240102030405"), iso.date(from: "2024-01-02T03:04:05Z"))
        XCTAssertEqual(XmltvTime.parse("20240102030405 -0530"), iso.date(from: "2024-01-02T08:34:05Z"))
        XCTAssertNil(XmltvTime.parse("2024010203"))
        XCTAssertNil(XmltvTime.parse("2024AB02030405 +0000"))
        XCTAssertEqual(XmltvTime.daysFromCivil(1970, 1, 1), 0)
        XCTAssertEqual(XmltvTime.daysFromCivil(2000, 3, 1), 11017)
    }

    func testScannerMatchesXMLParser() throws {
        let now = Date()
        let hour: TimeInterval = 3600
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv generator-info-name="test">
          <channel id="espn.us"><display-name>ESPN</display-name></channel>
          <programmes-ignored start="\(xmltv(now))" stop="\(xmltv(now + hour))" channel="nope"/>
          <programme start="\(xmltv(now - 30 * 60))" stop="\(xmltv(now + 30 * 60))" channel="espn.us">
            <title lang="en">Monday Night &amp; More</title>
            <desc>long &lt;desc&gt; we never keep</desc>
            <category lang="en">Sports</category>
            <category lang="en"><![CDATA[ Football ]]></category>
          </programme>
          <programme start="\(xmltv(now + 2 * hour, tz: " +0200"))" stop="\(xmltv(now + 3 * hour, tz: " +0200"))" channel='espn.us'>
            <title>Later &#169; Show</title>
          </programme>
          <programme start="\(xmltv(now - 5 * hour))" stop="\(xmltv(now - 4 * hour))" channel="espn.us">
            <title>Out of window</title>
          </programme>
          <programme start="\(xmltv(now + 40 * hour))" stop="\(xmltv(now + 41 * hour))" channel="espn.us">
            <title>Too far ahead</title>
          </programme>
          <programme start="\(xmltv(now))" stop="\(xmltv(now + hour))" channel="hbo.us"/>
        </tv>
        """
        let url = try writeTemp(xml)
        defer { try? FileManager.default.removeItem(at: url) }

        let fast = XmltvByteScanner.parse(
            fileURL: url, interestKeys: [], maxPerChannel: 12, hoursBehind: 1, hoursAhead: 18
        )
        let sax = DiskXMLTVParser.parse(
            fileURL: url, interestKeys: [], maxPerChannel: 12, hoursBehind: 1, hoursAhead: 18
        )

        XCTAssertEqual(Set(fast.keys), ["espn.us", "hbo.us"])
        XCTAssertEqual(fast["espn.us"]?.count, 2)
        XCTAssertEqual(fast["espn.us"]?[0].title, "Monday Night & More")
        XCTAssertEqual(fast["espn.us"]?[0].categories, ["Sports", "Football"])
        XCTAssertEqual(fast["espn.us"]?[1].title, "Later © Show")
        XCTAssertEqual(fast["hbo.us"]?.first?.title, "Program")

        // Timezone offset applied: +0200 stamp two hours ahead lands at now + 0h local UTC.
        let later = try XCTUnwrap(fast["espn.us"]?[1])
        XCTAssertEqual(later.start.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)

        XCTAssertEqual(Set(sax.keys), Set(fast.keys))
        for key in fast.keys {
            let a = fast[key] ?? []
            let b = sax[key] ?? []
            XCTAssertEqual(a.count, b.count, key)
            for (x, y) in zip(a, b) {
                XCTAssertEqual(x.title, y.title)
                XCTAssertEqual(x.categories, y.categories)
                XCTAssertEqual(x.start.timeIntervalSince1970, y.start.timeIntervalSince1970, accuracy: 1)
                XCTAssertEqual(x.end.timeIntervalSince1970, y.end.timeIntervalSince1970, accuracy: 1)
            }
        }
    }

    func testScannerCapsPerChannelAndInterestKeys() throws {
        let now = Date()
        var body = ""
        for i in 0..<20 {
            let s = now.addingTimeInterval(TimeInterval(i) * 1800)
            body += "<programme start=\"\(xmltv(s))\" stop=\"\(xmltv(s.addingTimeInterval(1800)))\" channel=\"a\"><title>P\(i)</title></programme>\n"
        }
        body += "<programme start=\"\(xmltv(now))\" stop=\"\(xmltv(now.addingTimeInterval(1800)))\" channel=\"b\"><title>B</title></programme>\n"
        let url = try writeTemp("<tv>\n\(body)</tv>")
        defer { try? FileManager.default.removeItem(at: url) }

        let all = XmltvByteScanner.parse(fileURL: url, interestKeys: [], maxPerChannel: 5, hoursBehind: 1, hoursAhead: 18)
        XCTAssertEqual(all["a"]?.count, 5)
        XCTAssertEqual(all["a"]?.map(\.title), ["P0", "P1", "P2", "P3", "P4"])
        XCTAssertEqual(all["b"]?.count, 1)

        let only = XmltvByteScanner.parse(fileURL: url, interestKeys: ["b"], maxPerChannel: 5, hoursBehind: 1, hoursAhead: 18)
        XCTAssertNil(only["a"])
        XCTAssertEqual(only["b"]?.count, 1)
    }

    func testScannerReturnsEmptyForNonXmltv() throws {
        let url = try writeTemp("{\"not\": \"xml\"}")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(XmltvByteScanner.parse(fileURL: url, interestKeys: [], maxPerChannel: 12, hoursBehind: 1, hoursAhead: 18).isEmpty)
    }
}

// MARK: - Chunked / streaming scanner

extension XmltvParserTests {

    private static let streamStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    private func streamXml(programmes: Int) -> Data {
        let now = Date()
        var body = "<?xml version=\"1.0\"?>\n<tv>\n<channel id=\"c\"><display-name>C &amp; Co</display-name></channel>\n"
        for i in 0..<programmes {
            let s = now.addingTimeInterval(TimeInterval(i - 1) * 600)
            let e = s.addingTimeInterval(600)
            let ch = "ch\(i % 7)"
            body += "<programme start=\"\(Self.streamStamp.string(from: s)) +0000\" stop=\"\(Self.streamStamp.string(from: e)) +0000\" channel=\"\(ch)\">"
            body += "<title lang=\"en\">Show &#35;\(i) &amp; friends</title>"
            body += "<desc>\(String(repeating: "x", count: 300))</desc>"
            if i % 3 == 0 { body += "<category>Sports</category>" }
            body += "</programme>\n"
        }
        body += "<programme start=\"\(Self.streamStamp.string(from: now)) +0000\" stop=\"\(Self.streamStamp.string(from: now.addingTimeInterval(600))) +0000\" channel=\"tail\"/>"
        body += "\n</tv>\n"
        return body.data(using: .utf8)!
    }

    private func flatten(_ map: [String: [EpgProgram]]) -> [String] {
        map.keys.sorted().flatMap { key in
            (map[key] ?? []).map { "\(key)|\($0.title)|\(Int($0.start.timeIntervalSince1970))|\(Int($0.end.timeIntervalSince1970))|\($0.categories.joined(separator: ","))" }
        }
    }

    func testStreamingScannerMatchesWholeFileForAnyChunkSize() throws {
        let data = streamXml(programmes: 120)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmltv-stream-\(UUID().uuidString).xml")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let whole = XmltvByteScanner.parse(fileURL: url, interestKeys: [], maxPerChannel: 12, hoursBehind: 1, hoursAhead: 18)
        XCTAssertEqual(whole["tail"]?.count, 1)
        XCTAssertEqual(whole["ch0"]?.first?.title, "Show #0 & friends")
        XCTAssertFalse(whole.isEmpty)

        // Chunk sizes chosen to split tags, attribute values and entities in every way.
        for chunk in [1, 7, 13, 64, 1000, 4096, data.count] {
            let scanner = XmltvStreamScanner(interestKeys: [], maxPerChannel: 12, hoursBehind: 1, hoursAhead: 18)
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunk, data.count)
                scanner.feed(data.subdata(in: offset..<end))
                offset = end
            }
            let streamed = scanner.finish()
            XCTAssertEqual(flatten(streamed), flatten(whole), "chunk size \(chunk)")
            XCTAssertEqual(scanner.bytesScanned, data.count)
        }
    }

    func testStreamingScannerCapsPerChannel() {
        let data = streamXml(programmes: 120)
        let scanner = XmltvStreamScanner(interestKeys: ["ch1"], maxPerChannel: 3, hoursBehind: 1, hoursAhead: 18)
        scanner.feed(data)
        let map = scanner.finish()
        XCTAssertEqual(Array(map.keys), ["ch1"])
        XCTAssertEqual(map["ch1"]?.count, 3)
    }
}
