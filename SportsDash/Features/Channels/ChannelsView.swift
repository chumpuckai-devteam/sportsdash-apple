import SwiftUI

/// Channel browser: category menu + adaptive card grid (App Store / TV-style tiles).
struct ChannelsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var query = ""
    @State private var selectedGroup: String = ""
    @State private var playerRoute: PlayerRoute?

    private var groupNames: [String] {
        appModel.channelGroupNames
    }

    private var displayedChannels: [IptvChannel] {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = query.lowercased()
            return appModel.channels.filter {
                $0.name.lowercased().contains(q)
                    || ($0.group?.lowercased().contains(q) ?? false)
            }
        }
        let group = selectedGroup.isEmpty ? groupNames.first : selectedGroup
        return appModel.channels(inGroup: group ?? "")
    }

    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 280), spacing: 16)]
        #else
        [GridItem(.adaptive(minimum: 160), spacing: 12)]
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if appModel.isLoadingChannels {
                    ProgressView("Loading channels…")
                        .tint(SportsColors.gold)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appModel.channels.isEmpty {
                    ContentUnavailableView(
                        "No channels loaded",
                        systemImage: "tv",
                        description: Text(
                            appModel.channelsError
                                ?? "Add an M3U or Xtream source in Settings."
                        )
                    )
                } else {
                    channelGrid
                }
            }
            .background(SportsColors.voidBlack)
            .navigationTitle("Channels")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search channels")
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if query.isEmpty, !groupNames.isEmpty {
                        groupMenu
                    }
                }
            }
            .task {
                if selectedGroup.isEmpty {
                    selectedGroup = groupNames.first ?? ""
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

    private var groupMenu: some View {
        Menu {
            Picker("Category", selection: $selectedGroup) {
                ForEach(groupNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedGroup.isEmpty ? "Category" : selectedGroup)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(SportsColors.gold)
        }
    }

    private var channelGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(displayedChannels) { ch in
                    ChannelCard(
                        channel: ch,
                        cleanUpNames: appModel.playerPrefs.cleanUpNames
                    ) {
                        playerRoute = PlayerRoute(channel: ch, game: nil, alternates: [])
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct ChannelCard: View {
    let channel: IptvChannel
    var cleanUpNames: Bool = true
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 10) {
                // Glyph tile (no remote logos — keeps grid fast & native)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    SportsColors.panelElevated,
                                    SportsColors.panel,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "tv.fill")
                        .font(.title2)
                        .foregroundStyle(SportsColors.gold.opacity(0.85))
                        .symbolRenderingMode(.hierarchical)
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SportsColors.border.opacity(0.6), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(ChannelNameCleanup.displayName(channel.name, enabled: cleanUpNames))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SportsColors.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let g = channel.group, !g.isEmpty {
                        Text(g)
                            .font(.caption2)
                            .foregroundStyle(SportsColors.muted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .background(SportsColors.panel.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SportsColors.border.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
