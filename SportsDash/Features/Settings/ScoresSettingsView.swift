import SwiftUI

/// Which leagues appear on the Scores dashboard.
struct ScoresSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(SportLeague.allCases) { league in
                    Toggle(isOn: leagueBinding(league)) {
                        Text("\(league.emoji) \(league.label)")
                    }
                    .tint(SportsColors.gold)
                }
            } header: {
                Text("Leagues on Scores")
            } footer: {
                Text("Fewer leagues loads faster. Pull to refresh after changes.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(SportsColors.voidBlack)
        .navigationTitle("Scores & leagues")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func leagueBinding(_ league: SportLeague) -> Binding<Bool> {
        Binding(
            get: { appModel.selectedLeagues.contains(league) },
            set: { on in
                var list = appModel.selectedLeagues
                if on {
                    if !list.contains(league) { list.append(league) }
                } else {
                    list.removeAll { $0 == league }
                }
                appModel.setSelectedLeagues(list)
            }
        )
    }
}
