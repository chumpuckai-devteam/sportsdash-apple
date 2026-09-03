import SwiftUI

enum AppTab: Hashable {
    case scores, guide, settings

    init(launch: LaunchTab) {
        switch launch {
        case .scores: self = .scores
        case .guide: self = .guide
        case .settings: self = .settings
        }
    }

    var title: String {
        switch self {
        case .scores: return "Scores"
        case .guide: return "Guide"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .scores: return "sportscourt.fill"
        case .guide: return "rectangle.grid.1x2.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var tab: AppTab = .scores
    #if os(tvOS)
    @FocusState private var sidebarItem: AppTab?
    #endif
    @State private var didApplyLaunchTab = false
    /// Full-screen splash until bootstrap finishes (min time avoids a flash).
    @State private var showSplash = true
    @State private var splashFinishing = false
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some View {
        ZStack {
            mainTabs
                .tint(SportsColors.gold)
                // Keep tabs mounted under splash so they warm up.
                .opacity(showSplash ? 0.001 : 1)

            // UHF-style pop-out player above tabs (phone only — TV uses fullScreenCover only)
            #if os(iOS)
            if appModel.floatingPlayer != nil, !showSplash {
                FloatingPlayerView(playback: appModel.floatingPlayback)
                    .environmentObject(appModel)
                    .environmentObject(appModel.epg)
                    .zIndex(100)
            }
            #endif

            if showSplash {
                SplashView(isFinishing: splashFinishing)
                    .zIndex(200)
                    .transition(.opacity)
            }
        }
        .sportsPlayerCover(item: $appModel.fullScreenPlayer) { route in
            PlayerView(
                channel: route.channel,
                game: route.game,
                alternateMatches: route.alternates
            )
            .environmentObject(appModel)
            .environmentObject(appModel.epg)
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
        #if os(iOS)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await appModel.refreshScores(silent: true)
                }
                // Re-arm the 45s poll timer (common modes already configured)
                appModel.startScoresPolling()
            }
            if newPhase == .inactive || newPhase == .background {
                // Signal for PiP handoff prep: post on .inactive (to begin parallel AV early for surface attach before suspend) as well as .background.
                // Idempotent handling + handoffInFlight prevents double-start / spam.
                // Each PlaybackController listens via startObservingLifecycle.
                NotificationCenter.default.post(name: .sportsDashWillBackground, object: nil)
            }
        }
        #endif
    }

    /// Three-tab shell: Scores · Guide · Settings.
    /// Guide owns channel browsing (list + grid); separate Channels tab removed as redundant.
    @ViewBuilder
    private var mainTabs: some View {
        #if os(iOS)
        jumbotronTabHost
        #else
        tvSidebarShell
        #endif
    }

    #if os(tvOS)
    /// Left rail: Back/Menu and long-press return focus to Scores · Guide · Settings.
    private var tvSidebarShell: some View {
        HStack(spacing: 0) {
            JumbotronTVSidebar(selection: $tab, sidebarItem: $sidebarItem)
            tvTabPage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
                .onExitCommand { sidebarItem = tab }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.65).onEnded { _ in
                        sidebarItem = tab
                    }
                )
        }
        .tint(SportsColors.gold)
    }

    @ViewBuilder
    private var tvTabPage: some View {
        switch tab {
        case .scores: ScoresView()
        case .guide: GuideView()
        case .settings: SettingsView()
        }
    }
    #endif

    #if os(iOS)
    /// Opaque lamp tab bar — no Liquid Glass on the tab layer (SPEC §6).
    /// TabView keeps each screen's state without stacking three live trees
    /// (the opacity-ZStack was slow and ate Guide/Settings taps).
    private var jumbotronTabHost: some View {
        TabView(selection: $tab) {
            ScoresView()
                .tabItem { Label(AppTab.scores.title, systemImage: AppTab.scores.systemImage) }
                .tag(AppTab.scores)
                .toolbar(.hidden, for: .tabBar)
            GuideView()
                .tabItem { Label(AppTab.guide.title, systemImage: AppTab.guide.systemImage) }
                .tag(AppTab.guide)
                .toolbar(.hidden, for: .tabBar)
            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            JumbotronTabBar(selection: $tab)
                .ignoresSafeArea(edges: .bottom)
        }
        .tint(SportsColors.gold)
    }
    #endif

    private var legacyTabView: some View {
        TabView(selection: $tab) {
            ScoresView()
                .tabItem { Label(AppTab.scores.title, systemImage: AppTab.scores.systemImage) }
                .tag(AppTab.scores)

            GuideView()
                .tabItem { Label(AppTab.guide.title, systemImage: AppTab.guide.systemImage) }
                .tag(AppTab.guide)

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        .tint(SportsColors.gold)
    }
}
