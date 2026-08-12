import SwiftUI

/// Android parity: Sport → League → Team favorite picker with ESPN logos.
struct FavoriteTeamPickerView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Step { case sport, league, team }

    @State private var step: Step = .sport
    @State private var sportName: String?
    @State private var league: SportLeague?
    @State private var teams: [TeamInfo] = []
    @State private var loading = false
    @State private var error: String?

    private var groups: [(String, [SportLeague])] { appModel.sportGroupsForPicker() }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .sport:
                    List {
                        Section("1. Choose a sport") {
                            ForEach(groups, id: \.0) { name, leagues in
                                Button {
                                    sportName = name
                                    step = .league
                                } label: {
                                    HStack {
                                        Text(name).foregroundStyle(SportsColors.text)
                                        Spacer()
                                        Text("\(leagues.count) leagues")
                                            .font(.caption)
                                            .foregroundStyle(SportsColors.muted)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(SportsColors.gold)
                                    }
                                }
                                #if os(tvOS)
                                .sportsTVFocusClean()
                                #endif
                            }
                        }
                    }
                case .league:
                    List {
                        Section("2. Choose a league") {
                            ForEach(groups.first(where: { $0.0 == sportName })?.1 ?? [], id: \.id) { lg in
                                Button {
                                    league = lg
                                    step = .team
                                    Task { await loadTeams(lg) }
                                } label: {
                                    HStack {
                                        Text(lg.emoji + " " + lg.label)
                                            .foregroundStyle(SportsColors.text)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(SportsColors.gold)
                                    }
                                }
                                #if os(tvOS)
                                .sportsTVFocusClean()
                                #endif
                            }
                        }
                    }
                case .team:
                    List {
                        Section("3. Tap a team to star / unstar") {
                            if loading {
                                HStack {
                                    Spacer()
                                    ProgressView().tint(SportsColors.gold)
                                    Spacer()
                                }
                            } else if let error {
                                Text(error).foregroundStyle(.red)
                            } else {
                                ForEach(teams) { team in
                                    Button {
                                        appModel.toggleFavorite(team: team)
                                    } label: {
                                        HStack(spacing: 12) {
                                            teamLogo(team)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(team.name)
                                                    .foregroundStyle(SportsColors.text)
                                                    .fontWeight(.semibold)
                                                Text(team.abbreviation)
                                                    .font(.caption)
                                                    .foregroundStyle(SportsColors.muted)
                                            }
                                            Spacer()
                                            Text(appModel.isTeamFavorite(team.id) ? "★" : "☆")
                                                .font(.title3.weight(.bold))
                                                .foregroundStyle(SportsColors.gold)
                                        }
                                    }
                                    #if os(tvOS)
                                    .sportsTVFocusClean()
                                    #endif
                                }
                            }
                        }
                    }
                }
            }
            .sportsScreenBackground()
            .navigationTitle(navTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .sport {
                        Button("Back") { goBack() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var navTitle: String {
        switch step {
        case .sport: return "Add favorite"
        case .league: return sportName ?? "League"
        case .team: return league?.label ?? "Team"
        }
    }

    private func goBack() {
        switch step {
        case .team:
            step = .league
            teams = []
            error = nil
            league = nil
        case .league:
            step = .sport
            sportName = nil
        case .sport:
            break
        }
    }

    private func loadTeams(_ lg: SportLeague) async {
        loading = true
        error = nil
        let list = await appModel.loadTeamsForLeague(lg)
        teams = list
        loading = false
        if list.isEmpty {
            error = "No teams returned for \(lg.label). Try again later."
        }
    }

    @ViewBuilder
    private func teamLogo(_ team: TeamInfo) -> some View {
        if let raw = team.logoURL, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                default:
                    monogram(team.abbreviation)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            monogram(team.abbreviation)
        }
    }

    private func monogram(_ abbr: String) -> some View {
        Text(String(abbr.prefix(3)))
            .font(.caption2.weight(.bold))
            .foregroundStyle(SportsColors.gold)
            .frame(width: 36, height: 36)
            .background(SportsColors.voidBlack, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
