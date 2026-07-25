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

    var title: String {
        switch self {
        case .scores: return "Scores"
        case .channels: return "Channels"
        case .guide: return "Guide"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .scores: return "sportscourt.fill"
        case .channels: return "tv.fill"
        case .guide: return "rectangle.grid.1x2.fill"
        case .settings: return "gearshape.fill"
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
            mainTabs
                .tint(SportsColors.gold)
                // Keep tabs mounted under splash so they warm up.
                .opacity(showSplash ? 0.001 : 1)

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

    /// iOS 18+ `Tab` API gets the Liquid Glass tab bar; older path keeps Label tabs.
    @ViewBuilder
    private var mainTabs: some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            TabView(selection: $tab) {
                Tab(AppTab.scores.title, systemImage: AppTab.scores.systemImage, value: AppTab.scores) {
                    ScoresView()
                }
                Tab(AppTab.channels.title, systemImage: AppTab.channels.systemImage, value: AppTab.channels) {
                    ChannelsView()
                }
                Tab(AppTab.guide.title, systemImage: AppTab.guide.systemImage, value: AppTab.guide) {
                    GuideView()
                }
                Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: AppTab.settings) {
                    SettingsView()
                }
            }
        } else {
            legacyTabView
        }
        #else
        legacyTabView
        #endif
    }

    private var legacyTabView: some View {
        TabView(selection: $tab) {
            ScoresView()
                .tabItem { Label(AppTab.scores.title, systemImage: AppTab.scores.systemImage) }
                .tag(AppTab.scores)

            ChannelsView()
                .tabItem { Label(AppTab.channels.title, systemImage: AppTab.channels.systemImage) }
                .tag(AppTab.channels)

            GuideView()
                .tabItem { Label(AppTab.guide.title, systemImage: AppTab.guide.systemImage) }
                .tag(AppTab.guide)

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
    }
}
