import SwiftUI

@main
struct SportsDashApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appModel)
                .preferredColorScheme(.dark)
        }
    }
}
