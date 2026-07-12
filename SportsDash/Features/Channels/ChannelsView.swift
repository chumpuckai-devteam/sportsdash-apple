import SwiftUI

struct ChannelsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var query = ""
    @State private var selectedGroup: String?
    @State private var playerRoute: PlayerRoute?

    var body: some View {
        NavigationStack {
            ZStack {
                SportsColors.voidBlack.ignoresSafeArea()
                if appModel.isLoadingChannels {
                    ProgressView("Loading channels…").tint(SportsColors.gold)
                } else if appModel.channels.isEmpty {
                    ContentUnavailableView(
                        "No channels loaded",
                        systemImage: "tv",
                        description: Text(appModel.channelsError
                            ?? "Add an M3U or Xtream source in Settings.")
                    )
                } else {
                    channelBrowser
                }
            }
            .navigationTitle("Channels")
            #if os(iOS)
            .searchable(text: $query, prompt: "Search channels or groups")
            #endif
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

    private var channelBrowser: some View {
        let groups = appModel.channelGroups
        let groupNames = groups.map(\.name)
        let activeGroup = selectedGroup ?? groupNames.first
        let list: [IptvChannel] = {
            if !query.isEmpty {
                let q = query.lowercased()
                return appModel.channels.filter {
                    $0.name.lowercased().contains(q)
                        || ($0.group?.lowercased().contains(q) ?? false)
                }
            }
            return groups.first(where: { $0.name == activeGroup })?.channels ?? []
        }()

        return VStack(spacing: 0) {
            if query.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(groupNames, id: \.self) { name in
                            let selected = name == activeGroup
                            Button {
                                selectedGroup = name
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
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            }
            List(list) { ch in
                Button {
                    playerRoute = PlayerRoute(channel: ch, game: nil, alternates: [])
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ch.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(SportsColors.text)
                            if let g = ch.group {
                                Text(g)
                                    .font(.caption)
                                    .foregroundStyle(SportsColors.muted)
                            }
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(SportsColors.gold)
                            .font(.title2)
                    }
                }
                .listRowBackground(SportsColors.panel)
            }
            .scrollContentBackground(.hidden)
        }
    }
}
