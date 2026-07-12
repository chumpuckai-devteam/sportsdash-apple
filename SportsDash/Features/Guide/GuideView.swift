import SwiftUI

struct GuideView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                SportsColors.voidBlack.ignoresSafeArea()
                ContentUnavailableView(
                    "Guide coming soon",
                    systemImage: "square.grid.2x2",
                    description: Text("EPG grid will port from the Flutter prototype.")
                )
            }
            .navigationTitle("Guide")
        }
    }
}
