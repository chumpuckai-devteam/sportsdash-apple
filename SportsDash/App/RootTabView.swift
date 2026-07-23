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
    /// Full-screen splash until bootstrap finishes (min time avoids a flash).
    @State private var showSplash = true
    @State private var splashFinishing = false

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
            .opacity(showSplash ? 0.001 : 1) // keep alive under splash so tabs warm up

            // UHF-style pop-out player above tabs
            if appModel.floatingPlayer != nil, !showSplash {
                FloatingPlayerView(playback: appModel.floatingPlayback)
                    .environmentObject(appModel)
                    .zIndex(100)
            }

            if showSplash {
                SplashView(isFinishing: splashFinishing)
                    .zIndex(200)
                    .transition(.opacity)
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
            let started = Date()
            await appModel.bootstrap()
            // Hold splash briefly so logo is readable even on cache-hit launches.
            let minSplash: TimeInterval = 1.15
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < minSplash {
                try? await Task.sleep(nanoseconds: UInt64((minSplash - elapsed) * 1_000_000_000))
            }
            splashFinishing = true
            try? await Task.sleep(nanoseconds: 320_000_000)
            withAnimation(.easeInOut(duration: 0.28)) {
                showSplash = false
            }
        }
    }
}
