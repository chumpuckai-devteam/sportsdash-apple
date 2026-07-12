import SwiftUI

/// TV Guide: pick a category via menu, then a program-grid style list (Now / Next).
struct GuideView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedGroup: String = ""
    @State private var playerRoute: PlayerRoute?

    private var groupNames: [String] {
        appModel.channelGroups.map(\.name)
    }

    private var activeChannels: [IptvChannel] {
        guard !selectedGroup.isEmpty else {
            return appModel.channelGroups.first?.channels ?? []
        }
        return appModel.channelGroups.first(where: { $0.name == selectedGroup })?.channels ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if appModel.channels.isEmpty {
                    ContentUnavailableView(
                        "Load a playlist first",
                        systemImage: "rectangle.grid.1x2",
                        description: Text("Configure Xtream or M3U in Settings to show the guide.")
                    )
                } else {
                    guideList
                }
            }
            .background(SportsColors.voidBlack)
            .navigationTitle("Guide")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !groupNames.isEmpty {
                        groupMenu
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reloadEpg() }
                    } label: {
                        if appModel.isLoadingEpg {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh guide")
                }
            }
            .task {
                if selectedGroup.isEmpty {
                    selectedGroup = groupNames.first ?? ""
                }
                await reloadEpg()
            }
            .onChange(of: selectedGroup) { _, _ in
                Task { await reloadEpg() }
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

    /// Native menu control — tap to choose category (no horizontal chip scroll).
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

    private var guideList: some View {
        List {
            Section {
                ForEach(activeChannels) { ch in
                    Button {
                        playerRoute = PlayerRoute(channel: ch, game: nil, alternates: [])
                    } label: {
                        GuideChannelRow(
                            channel: ch,
                            programs: appModel.epgByChannel[ch.id] ?? []
                        )
                    }
                    .listRowBackground(SportsColors.panel)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
            } header: {
                Text(selectedGroup.isEmpty ? "Channels" : selectedGroup)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SportsColors.muted)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func reloadEpg() async {
        let chans = Array(activeChannels.prefix(50))
        guard !chans.isEmpty else { return }
        await appModel.loadEpg(for: chans)
    }
}

/// One guide row: channel + Now / Next programs (TV-guide style).
private struct GuideChannelRow: View {
    let channel: IptvChannel
    let programs: [EpgProgram]

    private var now: EpgProgram? {
        programs.first(where: \.isNow) ?? programs.first
    }

    private var next: EpgProgram? {
        guard let now else { return programs.dropFirst().first }
        return programs.first { $0.start >= now.end } ?? programs.dropFirst().first
    }

    private var progress: Double {
        guard let now else { return 0 }
        let total = now.end.timeIntervalSince(now.start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(now.start)
        return min(1, max(0, elapsed / total))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(channel.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SportsColors.text)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(SportsColors.gold)
                    .symbolRenderingMode(.hierarchical)
            }

            // Now
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("NOW")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SportsColors.live)
                    if let now {
                        Text(now.timeRangeLabel)
                            .font(.caption2)
                            .foregroundStyle(SportsColors.muted)
                    }
                }
                Text(now?.title ?? "No program info")
                    .font(.subheadline)
                    .foregroundStyle(SportsColors.textSecondary)
                    .lineLimit(2)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(SportsColors.live.opacity(0.85))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 3)
            }

            // Next
            if let next {
                HStack(alignment: .top, spacing: 6) {
                    Text("NEXT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SportsColors.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title)
                            .font(.caption)
                            .foregroundStyle(SportsColors.textSecondary)
                            .lineLimit(1)
                        Text(next.timeRangeLabel)
                            .font(.caption2)
                            .foregroundStyle(SportsColors.muted)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }
}
