import SwiftUI

/// Compact stream picker: title, broadcasts, streams only (no scores / status chrome).
struct GameDetailSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var playerRoute: PlayerRoute?
    @State private var matches: [ChannelMatch] = []
    @State private var isMatching = true

    private var title: String {
        if game.usesMatchupLayout {
            return "\(game.away.name) vs \(game.home.name)"
        }
        return game.eventName ?? game.league.label
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(SportsColors.text)
                        .listRowBackground(SportsColors.panel)
                    if !game.broadcasts.isEmpty {
                        Text(game.broadcasts.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(SportsColors.textSecondary)
                            .listRowBackground(SportsColors.panel)
                    }
                }

                Section {
                    if isMatching {
                        HStack {
                            ProgressView().tint(SportsColors.gold)
                            Text("Finding streams…")
                                .font(.caption)
                                .foregroundStyle(SportsColors.muted)
                        }
                        .listRowBackground(SportsColors.panel)
                    } else if matches.isEmpty {
                        Text("No strong matches. Browse Channels or Guide.")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .listRowBackground(SportsColors.panel)
                    } else {
                        ForEach(matches) { m in
                            Button {
                                appModel.recordLastPlayed(gameId: game.id)
                                playerRoute = PlayerRoute(
                                    channel: m.channel,
                                    game: game,
                                    alternates: matches.filter { $0.channel.id != m.channel.id }
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.tv.fill")
                                        .foregroundStyle(SportsColors.gold)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ChannelNameCleanup.displayName(
                                            m.channel.name,
                                            enabled: appModel.playerPrefs.cleanUpNames
                                        ))
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(SportsColors.text)
                                            .multilineTextAlignment(.leading)
                                        if let g = m.channel.group, !g.isEmpty {
                                            Text(g)
                                                .font(.caption)
                                                .foregroundStyle(SportsColors.muted)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(SportsColors.gold)
                                }
                            }
                            .listRowBackground(SportsColors.panelElevated)
                        }
                    }
                } header: {
                    Text(isMatching ? "Streams" : (matches.isEmpty ? "No streams" : "Streams"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(SportsColors.panel)
            .navigationTitle(game.league.label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await runMatch()
            }
            .fullScreenCover(item: $playerRoute) { route in
                PlayerView(
                    channel: route.channel,
                    game: route.game,
                    alternateMatches: route.alternates
                )
                .environmentObject(appModel)
            }
        }
    }

    private func runMatch() async {
        isMatching = true
        let gameSnapshot = game
        let channels = appModel.channels
        let result = await Task.detached(priority: .userInitiated) {
            MatchingService().matchGameToChannels(gameSnapshot, channels: channels)
        }.value
        matches = result
        isMatching = false
    }
}

struct PlayerRoute: Identifiable {
    var id: String { channel.id + (game?.id ?? "") }
    var channel: IptvChannel
    var game: Game?
    var alternates: [ChannelMatch]
}
