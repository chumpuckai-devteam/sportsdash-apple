import SwiftUI

struct GameCardView: View {
    let game: Game
    var isFavorite: Bool = false
    var isAwayFavorite: Bool = false
    var isHomeFavorite: Bool = false
    var onTap: () -> Void
    var onToggleAwayFavorite: (() -> Void)?
    var onToggleHomeFavorite: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            GameMatchupRow(
                game: game,
                isFavorite: isFavorite,
                isAwayFavorite: isAwayFavorite,
                isHomeFavorite: isHomeFavorite,
                onToggleAwayFavorite: onToggleAwayFavorite,
                onToggleHomeFavorite: onToggleHomeFavorite
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens game details and streams")
    }
}
