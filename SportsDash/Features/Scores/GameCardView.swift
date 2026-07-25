import SwiftUI

struct GameCardView: View {
    let game: Game
    var isFavorite: Bool = false
    var onTap: () -> Void
    var onFavorite: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            GameMatchupRow(
                game: game,
                isFavorite: isFavorite,
                onFavorite: onFavorite
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens game details and streams")
    }
}
