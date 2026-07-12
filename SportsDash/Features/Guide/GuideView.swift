import SwiftUI

struct GuideView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedGroup: String?
    @State private var playerRoute: PlayerRoute?

    var body: some View {
        NavigationStack {
            ZStack {
                SportsColors.voidBlack.ignoresSafeArea()
                if appModel.channels.isEmpty {
                    ContentUnavailableView(
                        "Load a playlist first",
                        systemImage: "square.grid.2x2",
                        description: Text("EPG appears after Xtream/M3U is configured in Settings.")
                    )
                } else {
                    guideBody
                }
            }
            .navigationTitle("Guide")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            let groups = appModel.channelGroups
                            let name = selectedGroup ?? groups.first?.name
                            let chans = groups.first(where: { $0.name == name })?.channels ?? []
                            await appModel.loadEpg(for: Array(chans.prefix(40)))
                        }
                    } label: {
                        if appModel.isLoadingEpg {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task {
                let groups = appModel.channelGroups
                selectedGroup = groups.first?.name
                if let first = groups.first {
                    await appModel.loadEpg(for: Array(first.channels.prefix(30)))
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

    private var guideBody: some View {
        let groups = appModel.channelGroups
        let active = selectedGroup ?? groups.first?.name
        let channels = groups.first(where: { $0.name == active })?.channels ?? []

        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups.map(\.name), id: \.self) { name in
                        let selected = name == active
                        Button {
                            selectedGroup = name
                            Task {
                                let chans = groups.first(where: { $0.name == name })?.channels ?? []
                                await appModel.loadEpg(for: Array(chans.prefix(40)))
                            }
                        } label: {
                            Text(name)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selected ? SportsColors.voidBlack : SportsColors.muted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selected ? SportsColors.gold : SportsColors.panelElevated)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }

            List(channels) { ch in
                Button {
                    playerRoute = PlayerRoute(channel: ch, game: nil, alternates: [])
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ch.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SportsColors.text)
                        let programs = appModel.epgByChannel[ch.id] ?? []
                        if let now = programs.first(where: \.isNow) ?? programs.first {
                            Text(now.title)
                                .font(.caption)
                                .foregroundStyle(SportsColors.gold)
                            Text(now.timeRangeLabel)
                                .font(.caption2)
                                .foregroundStyle(SportsColors.muted)
                        } else {
                            Text("No EPG")
                                .font(.caption2)
                                .foregroundStyle(SportsColors.muted)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(SportsColors.panel)
            }
            .scrollContentBackground(.hidden)
        }
    }
}
