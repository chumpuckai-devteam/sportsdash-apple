import SwiftUI

@main
struct SportsDashApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        let prefs = StorageService.shared.playerPrefs()
        PlaybackController.applyGlobal(prefs)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appModel)
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
