import SwiftUI

/// Game detail — sheet slides up with LTR team-split hero + stream list.
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
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                }
            }
            .background(SportsColors.voidBlack.ignoresSafeArea())
            .sportsNavTitleMode(large: false)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(game.league.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SportsColors.text.opacity(0.9))
                }
                ToolbarItem(placement: SportsToolbarPlacement.trailing) {
                    #if os(tvOS)
                    SportsTVIconButton(
                        systemName: "xmark",
                        accessibilityLabelText: "Close"
                    ) {
                        dismiss()
                    }
                    #else
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SportsColors.text)
                            .frame(width: 32, height: 32)
                            .sportsGlass(in: Circle())
                    }
                    #endif
                }
            }
            .sportsHiddenNavBarBackground()
            .task { await runMatch() }
            .sportsPlayerCover(item: $playerRoute) { route in
                PlayerView(
                    channel: route.channel,
                    game: route.game,
                    alternateMatches: route.alternates
                )
                .environmentObject(appModel)
            }
        }
    }

    // MARK: Hero — LTR split (away left / home right)

    private var hero: some View {
        VStack(spacing: 20) {
            if game.usesMatchupLayout {
                // Scores row
                HStack(alignment: .center, spacing: 12) {
                    Text(game.away.displayScore)
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(SportsColors.text)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 6) {
                        if game.isLive {
                            Text("LIVE")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(SportsColors.live)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(SportsColors.live.opacity(0.18), in: Capsule())
                        }
                        Text(game.statusLine)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SportsColors.text)
                            .multilineTextAlignment(.center)
                        if !game.broadcasts.isEmpty {
                            Text(game.broadcasts.prefix(2).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(SportsColors.text.opacity(0.78))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .frame(width: 100)

                    Text(game.home.displayScore)
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(SportsColors.text)
                        .frame(maxWidth: .infinity)
                }

                // Logos + names under scores
                HStack(alignment: .top) {
                    teamIdentity(game.away, isFav: appModel.isTeamFavorite(game.away.id)) {
                        appModel.toggleFavorite(teamId: game.away.id)
                    }
                    .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 100)
                    teamIdentity(game.home, isFav: appModel.isTeamFavorite(game.home.id)) {
                        appModel.toggleFavorite(teamId: game.home.id)
                    }
                    .frame(maxWidth: .infinity)
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
                .padding(.vertical, 16)
            }

            if let venue = game.venue, !venue.isEmpty {
                Text(venue)
                    .font(.caption)
                    .foregroundStyle(SportsColors.text.opacity(0.72))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background {
            // Single soft surface for every game — no team-color splits.
            ZStack {
                SportsColors.voidBlack
                LinearGradient(
                    colors: [
                        SportsColors.panelElevated.opacity(0.95),
                        SportsColors.panel.opacity(0.90),
                        SportsColors.voidBlack,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private func teamIdentity(_ team: TeamInfo, isFav: Bool = false, onToggleFavorite: (() -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                TeamMarkView(team: team, size: 56)
                #if os(iOS)
                if let onToggleFavorite, !team.id.isEmpty {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFav ? "star.fill" : "star")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isFav ? SportsColors.gold : SportsColors.muted)
                            .padding(6)
                            .background(Circle().fill(SportsColors.voidBlack.opacity(0.8)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 8, y: -6)
                    .accessibilityLabel(isFav ? "Unstar \(team.rowLabel)" : "Star \(team.rowLabel)")
                } else if isFav {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SportsColors.gold)
                        .padding(6)
                        .background(Circle().fill(SportsColors.voidBlack.opacity(0.8)))
                        .offset(x: 8, y: -6)
                        .accessibilityHidden(true)
                }
                #else
                if isFav {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SportsColors.gold)
                        .padding(6)
                        .background(Circle().fill(SportsColors.voidBlack.opacity(0.8)))
                        .offset(x: 8, y: -6)
                        .accessibilityHidden(true)
                }
                #endif
            }
            Text(team.rowLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SportsColors.text)
                .lineLimit(1)
            Text(team.name)
                .font(.caption2)
                .foregroundStyle(SportsColors.text.opacity(0.75))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            #if os(iOS)
            if let onToggleFavorite, !team.id.isEmpty {
                Button(action: onToggleFavorite) {
                    Text(isFav ? "Unstar" : "★ Favorite")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isFav ? SportsColors.gold : SportsColors.muted)
                }
                .buttonStyle(.plain)
            }
            #endif
        }
    }

    // MARK: Streams — same soft card language as the channel chooser

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
                VStack(spacing: 12) {
                    ForEach(matches) { m in
                        Button {
                            appModel.recordLastPlayed(gameId: game.id)
                            playerRoute = PlayerRoute(
                                channel: m.channel,
                                game: game,
                                alternates: matches.filter { $0.channel.id != m.channel.id }
                            )
                        } label: {
                            #if os(tvOS)
                            SportsTVListRowLabel { focused in
                                streamRowLabel(m, focused: focused)
                            }
                            #else
                            streamRowLabel(m, focused: false)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            #endif
                        }
                        #if os(tvOS)
                        .sportsTVFocusClean()
                        #else
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                #if os(tvOS)
                .padding(.horizontal, SportsTVMetrics.scoreHorizontalInset)
                .focusSection()
                #else
                .sportsSoftSurface(radius: 18)
                .padding(.horizontal, 16)
                #endif
            }
        }
    }

    private func streamRowLabel(_ m: ChannelMatch, focused: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "play.tv.fill")
                .font(.title3)
                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    ChannelNameCleanup.displayName(
                        m.channel.name,
                        enabled: appModel.playerPrefs.cleanUpNames
                    )
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                .multilineTextAlignment(.leading)
                if let g = m.channel.group, !g.isEmpty {
                    Text(g)
                        .font(.caption)
                        .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.7) : SportsColors.muted)
                }
            }
            Spacer(minLength: 0)
            Text("WATCH")
                .font(.caption.weight(.black))
                .foregroundStyle(focused ? SportsColors.gold : SportsColors.voidBlack)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(focused ? SportsColors.voidBlack.opacity(0.88) : SportsColors.gold)
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
