import SwiftUI

/// Game detail — sheet slides up with team-tint hero + stream list.
/// Layout cues inspired by modern sports apps; SportsDash-specific actions (IPTV WATCH).
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
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    streamSection
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                }
            }
            .background(SportsColors.voidBlack.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(game.league.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SportsColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SportsColors.text)
                            .frame(width: 32, height: 32)
                            .sportsGlass(in: Circle())
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await runMatch() }
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

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 18) {
            if game.usesMatchupLayout {
                HStack(alignment: .top, spacing: 8) {
                    heroSide(team: game.away, score: game.away.displayScore)
                    VStack(spacing: 8) {
                        if game.isLive {
                            SportsLiveBadge()
                        }
                        Text(game.statusLine)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SportsColors.text)
                            .multilineTextAlignment(.center)
                        if !game.broadcasts.isEmpty {
                            Text(game.broadcasts.prefix(2).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(SportsColors.text.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .frame(minWidth: 88)
                    heroSide(team: game.home, score: game.home.displayScore)
                }
            } else {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(SportsColors.text)
                        .multilineTextAlignment(.center)
                    Text(game.statusLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SportsColors.live)
                }
                .padding(.vertical, 12)
            }

            if let venue = game.venue, !venue.isEmpty {
                Text(venue)
                    .font(.caption)
                    .foregroundStyle(SportsColors.text.opacity(0.7))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background {
            Group {
                if game.usesMatchupLayout {
                    TeamTheme.heroGradient(away: game.away, home: game.home)
                } else {
                    LinearGradient(
                        colors: [SportsColors.panelElevated, SportsColors.voidBlack],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .overlay {
                // Soft vignette for text contrast (same idea as sports detail sheets)
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private func heroSide(team: TeamInfo, score: String) -> some View {
        VStack(spacing: 10) {
            Text(score)
                .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(SportsColors.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            TeamMarkView(team: team, size: 52)
            Text(team.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SportsColors.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Streams

    private var streamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isMatching ? "Finding streams…" : (matches.isEmpty ? "Streams" : "Watch"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SportsColors.textSecondary)
                .padding(.horizontal, 20)

            if isMatching {
                HStack(spacing: 12) {
                    ProgressView().tint(SportsColors.gold)
                    Text("Matching channels…")
                        .font(.subheadline)
                        .foregroundStyle(SportsColors.muted)
                    Spacer()
                }
                .padding(16)
                .sportsSoftSurface(radius: 16)
                .padding(.horizontal, 16)
            } else if matches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No strong channel matches")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SportsColors.text)
                    Text("Open Guide and pick a category, or add more IPTV sources in Settings.")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sportsSoftSurface(radius: 16)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, m in
                        Button {
                            appModel.recordLastPlayed(gameId: game.id)
                            playerRoute = PlayerRoute(
                                channel: m.channel,
                                game: game,
                                alternates: matches.filter { $0.channel.id != m.channel.id }
                            )
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "play.tv.fill")
                                    .font(.title3)
                                    .foregroundStyle(SportsColors.gold)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(
                                        ChannelNameCleanup.displayName(
                                            m.channel.name,
                                            enabled: appModel.playerPrefs.cleanUpNames
                                        )
                                    )
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
                                Text("WATCH")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(SportsColors.voidBlack)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(SportsColors.gold.gradient, in: Capsule())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < matches.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 66)
                        }
                    }
                }
                .sportsSoftSurface(radius: 18)
                .padding(.horizontal, 16)
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
