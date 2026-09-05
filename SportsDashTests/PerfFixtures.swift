import Foundation

#if os(tvOS)
@testable import SportsDashTV
#else
@testable import SportsDash
#endif

enum PerfFixtures {
    static func team(_ id: String, name: String, score: Int? = 1) -> TeamInfo {
        TeamInfo(
            id: id,
            name: name,
            abbreviation: String(name.prefix(3)).uppercased(),
            score: score,
            logoURL: nil,
            colorHex: nil,
            alternateColorHex: nil,
            shortName: name
        )
    }

    static func game(
        id: String,
        league: SportLeague,
        status: GameStatus = .live,
        start: Date = Date()
    ) -> Game {
        Game(
            id: id,
            league: league,
            home: team("h-\(id)", name: "Home \(id)"),
            away: team("a-\(id)", name: "Away \(id)"),
            status: status,
            startTime: start,
            statusDetail: status == .live ? "Q1" : nil,
            period: status == .live ? "1" : nil,
            clock: status == .live ? "12:00" : nil,
            broadcasts: ["ESPN"],
            venue: nil,
            eventName: nil,
            isHeadToHead: true
        )
    }

    static func channel(_ i: Int, name: String? = nil) -> IptvChannel {
        IptvChannel(
            id: "ch-\(i)",
            name: name ?? "US Sports \(i)",
            url: "http://example.test/\(i).m3u8",
            group: "Sports",
            logoURL: nil,
            tvgId: "tvg-\(i)",
            epgChannelId: "tvg-\(i)"
        )
    }
}
