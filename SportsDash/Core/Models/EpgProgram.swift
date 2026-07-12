import Foundation

struct EpgProgram: Identifiable, Hashable, Sendable, Codable {
    var id: String { "\(channelKey)-\(start.timeIntervalSince1970)" }
    var channelKey: String
    var title: String
    var start: Date
    var end: Date
    var description: String?

    enum CodingKeys: String, CodingKey {
        case channelKey, title, start, end, description
    }

    var isNow: Bool {
        let now = Date()
        return start <= now && now < end
    }

    var timeRangeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}
