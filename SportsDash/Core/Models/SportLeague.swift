import Foundation

/// Mirrors Flutter `SportLeague` — one ESPN path per competition.
enum SportLeague: String, CaseIterable, Identifiable, Codable, Sendable {
    case nfl, ncaaf, ufl
    case nba, wnba, ncaab
    case mlb
    case nhl
    case epl, mls, laliga, bundesliga, seriea, ligue1
    case eredivisie, ligaportugal, ligamx, brasileirao, ligapro
    case ucl, uel, worldcup
    case atp, wta
    case pga, lpga
    case f1, nascar, indycar
    case ufc
    case sixnations, premiership, urc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nfl: return "NFL"
        case .ncaaf: return "NCAA Football"
        case .ufl: return "UFL"
        case .nba: return "NBA"
        case .wnba: return "WNBA"
        case .ncaab: return "NCAA Men's"
        case .mlb: return "MLB"
        case .nhl: return "NHL"
        case .epl: return "Premier League"
        case .mls: return "MLS"
        case .laliga: return "La Liga"
        case .bundesliga: return "Bundesliga"
        case .seriea: return "Serie A"
        case .ligue1: return "Ligue 1"
        case .eredivisie: return "Eredivisie"
        case .ligaportugal: return "Liga Portugal"
        case .ligamx: return "Liga MX"
        case .brasileirao: return "Brasileirão"
        case .ligapro: return "Liga Profesional"
        case .ucl: return "Champions League"
        case .uel: return "Europa League"
        case .worldcup: return "World Cup"
        case .atp: return "ATP"
        case .wta: return "WTA"
        case .pga: return "PGA Tour"
        case .lpga: return "LPGA"
        case .f1: return "Formula 1"
        case .nascar: return "NASCAR"
        case .indycar: return "IndyCar"
        case .ufc: return "UFC"
        case .sixnations: return "6 Nations"
        case .premiership: return "Premiership"
        case .urc: return "URC"
        }
    }

    var sportPath: String {
        switch self {
        case .nfl, .ncaaf, .ufl: return "football"
        case .nba, .wnba, .ncaab: return "basketball"
        case .mlb: return "baseball"
        case .nhl: return "hockey"
        case .epl, .mls, .laliga, .bundesliga, .seriea, .ligue1,
             .eredivisie, .ligaportugal, .ligamx, .brasileirao, .ligapro,
             .ucl, .uel, .worldcup:
            return "soccer"
        case .atp, .wta: return "tennis"
        case .pga, .lpga: return "golf"
        case .f1, .nascar, .indycar: return "racing"
        case .ufc: return "mma"
        case .sixnations, .premiership, .urc: return "rugby"
        }
    }

    var leaguePath: String {
        switch self {
        case .nfl: return "nfl"
        case .ncaaf: return "college-football"
        case .ufl: return "ufl"
        case .nba: return "nba"
        case .wnba: return "wnba"
        case .ncaab: return "mens-college-basketball"
        case .mlb: return "mlb"
        case .nhl: return "nhl"
        case .epl: return "eng.1"
        case .mls: return "usa.1"
        case .laliga: return "esp.1"
        case .bundesliga: return "ger.1"
        case .seriea: return "ita.1"
        case .ligue1: return "fra.1"
        case .eredivisie: return "ned.1"
        case .ligaportugal: return "por.1"
        case .ligamx: return "mex.1"
        case .brasileirao: return "bra.1"
        case .ligapro: return "arg.1"
        case .ucl: return "uefa.champions"
        case .uel: return "uefa.europa"
        case .worldcup: return "fifa.world"
        case .atp: return "atp"
        case .wta: return "wta"
        case .pga: return "pga"
        case .lpga: return "lpga"
        case .f1: return "f1"
        case .nascar: return "nascar-premier"
        case .indycar: return "irl"
        case .ufc: return "ufc"
        case .sixnations: return "six-nations"
        case .premiership: return "premiership-rugby"
        case .urc: return "united-rugby-championship"
        }
    }

    var emoji: String {
        switch sportPath {
        case "football": return "🏈"
        case "basketball": return "🏀"
        case "baseball": return "⚾"
        case "hockey": return "🏒"
        case "soccer": return self == .ucl || self == .uel ? "🏆" : (self == .worldcup ? "🌍" : "⚽")
        case "tennis": return "🎾"
        case "golf": return "⛳"
        case "racing": return "🏎️"
        case "mma": return "🥊"
        case "rugby": return "🏉"
        default: return "🏟️"
        }
    }

    var sportSectionTitle: String {
        switch sportPath {
        case "football": return "Football"
        case "basketball": return "Basketball"
        case "baseball": return "Baseball"
        case "hockey": return "Hockey"
        case "soccer": return "Soccer"
        case "tennis": return "Tennis"
        case "golf": return "Golf"
        case "racing": return "Racing"
        case "mma": return "Combat"
        case "rugby": return "Rugby"
        default: return label
        }
    }

    /// Default leagues enabled on first launch (matches Flutter defaults intent).
    static let defaults: [SportLeague] = [
        .worldcup, .ucl, .epl, .mls,
        .nfl, .nba, .mlb, .nhl,
    ]
}
