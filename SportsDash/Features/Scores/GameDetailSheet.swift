import SwiftUI

struct GameDetailSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var playerRoute: PlayerRoute?

    private var matches: [ChannelMatch] {
        appModel.matches(for: game)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(game.league.emoji) \(game.eventName ?? game.league.label)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SportsColors.gold)
                        if game.usesMatchupLayout {
                            Text("\(game.away.name)  vs  \(game.home.name)")
                                .font(.title3.weight(.bold))
                        } else {
                            Text(game.eventName ?? game.league.label)
                                .font(.title3.weight(.bold))
                        }
                        Text(statusLine)
                            .font(.subheadline)
                            .foregroundStyle(SportsColors.muted)
                        if game.usesMatchupLayout, game.isLive || game.isFinal {
                            HStack {
                                Spacer()
                                scoreBlock(game.away)
                                Text("—").foregroundStyle(SportsColors.muted)
                                scoreBlock(game.home)
                                Spacer()
                            }
                            .padding(.top, 8)
                        }
                    }
                    .listRowBackground(SportsColors.panel)
                }

                if !game.broadcasts.isEmpty {
                    Section("Broadcasts") {
                        Text(game.broadcasts.joined(separator: " · "))
                            .foregroundStyle(SportsColors.textSecondary)
                            .listRowBackground(SportsColors.panel)
                    }
                }

                Section {
                    if matches.isEmpty {
                        Text("No strong matches. Browse Guide or Channels for the feed you want.")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .listRowBackground(SportsColors.panel)
                        Button("Open Guide") {
                            dismiss()
                        }
                        .listRowBackground(SportsColors.panel)
                    } else {
                        Text("Top matches for this game. Use Guide or Channels if yours isn’t listed.")
                            .font(.caption)
                            .foregroundStyle(SportsColors.muted)
                            .listRowBackground(SportsColors.panel)
                        ForEach(matches) { m in
                            Button {
                                appModel.recordLastPlayed(gameId: game.id)
                                playerRoute = PlayerRoute(
                                    channel: m.channel,
                                    game: game,
                                    alternates: matches.filter { $0.channel.id != m.channel.id }
                                )
                            } label: {
                                HStack {
                                    Image(systemName: "play.tv.fill")
                                        .foregroundStyle(SportsColors.gold)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.channel.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(SportsColors.text)
                                        if let g = m.channel.group, !g.isEmpty {
                                            Text(g)
                                                .font(.caption)
                                                .foregroundStyle(SportsColors.muted)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(SportsColors.gold)
                                }
                            }
                            .listRowBackground(SportsColors.panelElevated)
                        }
                    }
                } header: {
                    Text(matches.isEmpty ? "Find a stream" : "Choose a stream")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SportsColors.panel)
            .navigationTitle("Watch")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
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

    private var statusLine: String {
        [
            game.isLive ? "LIVE" : nil,
            game.isFinal ? "FINAL" : nil,
            game.statusDetail,
            game.venue,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func scoreBlock(_ team: TeamInfo) -> some View {
        VStack {
            Text(team.abbreviation)
                .font(.caption.weight(.bold))
                .foregroundStyle(SportsColors.muted)
            Text(team.displayScore)
                .font(.largeTitle.weight(.heavy).monospacedDigit())
        }
    }
}

struct PlayerRoute: Identifiable {
    var id: String { channel.id + (game?.id ?? "") }
    var channel: IptvChannel
    var game: Game?
    var alternates: [ChannelMatch]
}
