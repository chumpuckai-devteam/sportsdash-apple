import SwiftUI

enum AppTab: Hashable {
    case scores, channels, guide, settings

    init(launch: LaunchTab) {
        switch launch {
        case .scores: self = .scores
        case .channels: self = .channels
        case .guide: self = .guide
        case .settings: self = .settings
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var tab: AppTab = .scores
    @State private var didApplyLaunchTab = false

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                ScoresView()
                    .tabItem { Label("Scores", systemImage: "sportscourt.fill") }
                    .tag(AppTab.scores)

                ChannelsView()
                    .tabItem { Label("Channels", systemImage: "tv") }
                    .tag(AppTab.channels)

                GuideView()
                    .tabItem { Label("Guide", systemImage: "square.grid.2x2") }
                    .tag(AppTab.guide)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .tint(SportsColors.gold)

            // UHF-style pop-out player above tabs
            if appModel.floatingPlayer != nil {
                FloatingPlayerView(playback: appModel.floatingPlayback)
                    .environmentObject(appModel)
                    .zIndex(100)
            }
        }
        .fullScreenCover(item: $appModel.fullScreenPlayer) { route in
            PlayerView(
                channel: route.channel,
                game: route.game,
                alternateMatches: route.alternates
            )
            .environmentObject(appModel)
        }
        .task {
            if !didApplyLaunchTab {
                tab = AppTab(launch: appModel.playerPrefs.launchTab)
                didApplyLaunchTab = true
            }
            await appModel.bootstrap()
        }
    }
}
