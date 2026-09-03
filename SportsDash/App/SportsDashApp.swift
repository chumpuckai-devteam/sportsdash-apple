import SwiftUI

#if os(iOS)
import BackgroundTasks
#endif

@main
struct SportsDashApp: App {
    @StateObject private var appModel = AppModel()

    // Use delegate adaptor for early BGTask registration (required before app finishes launch)
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        JumbotronFonts.register()
        let prefs = StorageService.shared.playerPrefs()
        PlaybackController.applyGlobal(prefs)
        // BG path independent of AppModel (see ScoresBackgroundRefresh)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appModel)
                .environmentObject(appModel.epg)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch appModel.playerPrefs.theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

#if os(iOS)
/// Minimal delegate to register BGAppRefresh for scores when notifications enabled.
/// Fails soft. Identifier declared in Info.plist via Project.yml.
/// Schedule logic lives in ScoresBackgroundRefresh (no AppModel dep).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ScoresBackgroundRefresh.shared.register()
        return true
    }
}
#endif
