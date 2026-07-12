import KSPlayer
import SwiftUI

@main
struct SportsDashApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        // Configure multi-engine player defaults before any playback starts.
        let prefs = StorageService.shared.playerPrefs()
        PlaybackController.applyGlobalEngine(prefs.engine, hardwareDecode: prefs.hardwareDecode)
        KSOptions.isAutoPlay = true
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appModel)
                .preferredColorScheme(.dark)
        }
    }
}
