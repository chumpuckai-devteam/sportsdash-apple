import SwiftUI

// MARK: - Layout constants (mirror Flutter guide)

private enum GuideMetrics {
    static let hours = 24
    static let pxPerHour: CGFloat = 160
    static let channelColWidth: CGFloat = 128
    static let rowHeight: CGFloat = 72
    static let timeHeaderHeight: CGFloat = 36

    static var timelineWidth: CGFloat { CGFloat(hours) * pxPerHour }
}

/// Traditional TV guide: channels on the left, EPG programs on a horizontal hour timeline.
struct GuideView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedGroup: String = ""
    @State private var windowStart: Date = GuideView.snappedNowMinusOneHour()
    @State private var playerRoute: PlayerRoute?
    @State private var nowTick = Date()

    private var groupNames: [String] {
        appModel.channelGroups.map(\.name)
    }

    private var activeChannels: [IptvChannel] {
        guard !selectedGroup.isEmpty else {
            return appModel.channelGroups.first?.channels ?? []
        }
        return appModel.channelGroups.first(where: { $0.name == selectedGroup })?.channels ?? []
    }

    private var guideRows: [GuideChannelRowData] {
        activeChannels.map { ch in
            GuideChannelRowData(
                channel: ch,
                programs: appModel.epgByChannel[ch.id] ?? []
            )
        }
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
                } else if activeChannels.isEmpty {
                    ContentUnavailableView(
                        "No channels in this category",
                        systemImage: "tv",
                        description: Text("Pick another category from the menu.")
                    )
                } else {
                    guideGrid
                }
            }
            .background(SportsColors.voidBlack)
            .navigationTitle("Guide")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !groupNames.isEmpty {
                        groupMenu
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        shiftWindow(byHours: -6)
                    } label: {
                        Image(systemName: "chevron.left.2")
                    }
                    .accessibilityLabel("Earlier")

                    Button("NOW") {
                        windowStart = Self.snappedNowMinusOneHour()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SportsColors.gold)

                    Button {
                        shiftWindow(byHours: 6)
                    } label: {
                        Image(systemName: "chevron.right.2")
                    }
                    .accessibilityLabel("Later")

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
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
                nowTick = date
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

    private var guideGrid: some View {
        VStack(spacing: 0) {
            if appModel.isLoadingEpg && guideRows.allSatisfy({ $0.programs.isEmpty }) {
                ProgressView("Loading program guide…")
                    .tint(SportsColors.gold)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GuideTimelineGrid(
                    rows: guideRows,
                    windowStart: windowStart,
                    now: nowTick,
                    onPlay: { channel in
                        playerRoute = PlayerRoute(channel: channel, game: nil, alternates: [])
                    }
                )
            }
        }
    }

    private func shiftWindow(byHours hours: Int) {
        windowStart = Calendar.current.date(byAdding: .hour, value: hours, to: windowStart) ?? windowStart
    }

    private func reloadEpg() async {
        // Load enough channels for a usable grid; short EPG is lightweight.
        let chans = Array(activeChannels.prefix(80))
        guard !chans.isEmpty else { return }
        await appModel.loadEpg(for: chans)
    }

    private static func snappedNowMinusOneHour() -> Date {
        let n = Date()
        let cal = Calendar.current
        let hour = cal.dateInterval(of: .hour, for: n)?.start ?? n
        return cal.date(byAdding: .hour, value: -1, to: hour) ?? hour
    }
}

// MARK: - Row model

private struct GuideChannelRowData: Identifiable {
    var id: String { channel.id }
    let channel: IptvChannel
    let programs: [EpgProgram]
}

// MARK: - Timeline grid (channel column + hour-scrolled programs)

private struct GuideTimelineGrid: View {
    let rows: [GuideChannelRowData]
    let windowStart: Date
    let now: Date
    let onPlay: (IptvChannel) -> Void

    @StateObject private var scrollSync = GuideScrollSync()

    private var windowEnd: Date {
        Calendar.current.date(byAdding: .hour, value: GuideMetrics.hours, to: windowStart) ?? windowStart
    }

    private var nowOffset: CGFloat {
        let minutes = now.timeIntervalSince(windowStart) / 60.0
        return CGFloat(minutes / 60.0) * GuideMetrics.pxPerHour
    }

    private var showNowLine: Bool {
        nowOffset >= 0 && nowOffset <= GuideMetrics.timelineWidth
    }

    private var bodyHeight: CGFloat {
        CGFloat(rows.count) * GuideMetrics.rowHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sticky time header
            timeHeader
                .frame(height: GuideMetrics.timeHeaderHeight)
                .background(SportsColors.panel)

            Rectangle()
                .fill(SportsColors.border.opacity(0.5))
                .frame(height: 1)

            // Body: fixed channel column + horizontally scrolling timeline
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    channelColumn
                    timelineBody
                }
                .frame(height: max(bodyHeight, 1))
            }
        }
        .background(SportsColors.voidBlack)
        .onAppear {
            // Scroll so "now" sits slightly in from the left edge.
            let target = max(0, nowOffset - 40)
            scrollSync.jump(to: target)
        }
        .onChange(of: windowStart) { _, _ in
            let target = max(0, nowOffset - 40)
            DispatchQueue.main.async {
                scrollSync.jump(to: target)
            }
        }
    }

    private var timeHeader: some View {
        HStack(spacing: 0) {
            Text("CHANNEL")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SportsColors.muted)
                .tracking(1.0)
                .frame(width: GuideMetrics.channelColWidth, alignment: .leading)
                .padding(.leading, 12)

            GuideLinkedScrollView(
                axis: .horizontal,
                showsIndicators: false,
                sync: scrollSync,
                role: .header
            ) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(0..<GuideMetrics.hours, id: \.self) { h in
                            let t = Calendar.current.date(byAdding: .hour, value: h, to: windowStart) ?? windowStart
                            Text(hourLabel(t))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(SportsColors.goldDim)
                                .frame(width: GuideMetrics.pxPerHour, alignment: .leading)
                                .padding(.leading, 8)
                        }
                    }
                    .frame(width: GuideMetrics.timelineWidth, height: GuideMetrics.timeHeaderHeight)

                    if showNowLine {
                        Rectangle()
                            .fill(SportsColors.live)
                            .frame(width: 2, height: GuideMetrics.timeHeaderHeight)
                            .offset(x: nowOffset)
                    }
                }
                .frame(width: GuideMetrics.timelineWidth, height: GuideMetrics.timeHeaderHeight)
            }
        }
    }

    private var channelColumn: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                Button {
                    onPlay(row.channel)
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(SportsColors.voidBlack)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "tv")
                                    .font(.system(size: 13))
                                    .foregroundStyle(SportsColors.muted)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(SportsColors.border, lineWidth: 1)
                            }

                        Text(row.channel.name)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SportsColors.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: GuideMetrics.channelColWidth, height: GuideMetrics.rowHeight, alignment: .leading)
                    .background(SportsColors.panel)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(SportsColors.border.opacity(0.35))
                    .frame(height: 0.5)
            }
        }
        .frame(width: GuideMetrics.channelColWidth)
    }

    private var timelineBody: some View {
        GuideLinkedScrollView(
            axis: .horizontal,
            showsIndicators: true,
            sync: scrollSync,
            role: .body
        ) {
            ZStack(alignment: .topLeading) {
                // Hour grid lines
                ForEach(0...GuideMetrics.hours, id: \.self) { h in
                    Rectangle()
                        .fill(SportsColors.border.opacity(0.35))
                        .frame(width: 1, height: bodyHeight)
                        .offset(x: CGFloat(h) * GuideMetrics.pxPerHour)
                }

                // Program blocks
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let top = CGFloat(index) * GuideMetrics.rowHeight
                    ForEach(visiblePrograms(for: row), id: \.id) { program in
                        programBlock(program, channel: row.channel, top: top)
                    }
                }

                // Now line
                if showNowLine {
                    Rectangle()
                        .fill(SportsColors.live)
                        .frame(width: 2, height: bodyHeight)
                        .offset(x: nowOffset)
                }
            }
            .frame(width: GuideMetrics.timelineWidth, height: bodyHeight, alignment: .topLeading)
            .background(SportsColors.voidBlack)
        }
    }

    @ViewBuilder
    private func programBlock(_ program: EpgProgram, channel: IptvChannel, top: CGFloat) -> some View {
        let clipped = clippedRange(program)
        let left = xOffset(for: clipped.start)
        let width = max(28, xOffset(for: clipped.end) - left)
        let airing = program.start <= now && now < program.end

        Button {
            onPlay(channel)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(program.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SportsColors.text)
                    .lineLimit(1)
                Text(shortTimeRange(program))
                    .font(.system(size: 10))
                    .foregroundStyle(SportsColors.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: width - 4, height: GuideMetrics.rowHeight - 16, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(airing ? SportsColors.gold.opacity(0.18) : SportsColors.panelElevated)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        airing ? SportsColors.gold.opacity(0.55) : SportsColors.border,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .offset(x: left + 2, y: top + 8)
    }

    private func visiblePrograms(for row: GuideChannelRowData) -> [EpgProgram] {
        let programs = row.programs.isEmpty
            ? [
                EpgProgram(
                    channelKey: row.channel.id,
                    title: "No EPG data",
                    start: windowStart,
                    end: windowEnd,
                    description: nil
                )
            ]
            : row.programs

        return programs.filter { p in
            p.end > windowStart && p.start < windowEnd
        }
    }

    private func clippedRange(_ p: EpgProgram) -> (start: Date, end: Date) {
        let start = max(p.start, windowStart)
        let end = min(p.end, windowEnd)
        return (start, end)
    }

    private func xOffset(for date: Date) -> CGFloat {
        let minutes = date.timeIntervalSince(windowStart) / 60.0
        return CGFloat(minutes / 60.0) * GuideMetrics.pxPerHour
    }

    private func hourLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f.string(from: date).lowercased()
    }

    private func shortTimeRange(_ p: EpgProgram) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: p.start)) – \(f.string(from: p.end))"
    }
}

// MARK: - Linked horizontal scroll (header ↔ body)

@MainActor
final class GuideScrollSync: ObservableObject {
    weak var headerScroll: UIScrollView?
    weak var bodyScroll: UIScrollView?
    private var locking = false
    private var pendingX: CGFloat?

    func register(_ scrollView: UIScrollView, role: GuideScrollRole) {
        switch role {
        case .header: headerScroll = scrollView
        case .body: bodyScroll = scrollView
        }
        scrollView.delegate = bridge
        if let pendingX {
            apply(pendingX)
        }
    }

    func jump(to x: CGFloat) {
        pendingX = max(0, x)
        apply(pendingX!)
    }

    private func apply(_ x: CGFloat) {
        locking = true
        let offset = CGPoint(x: x, y: 0)
        headerScroll?.setContentOffset(offset, animated: false)
        bodyScroll?.setContentOffset(offset, animated: false)
        locking = false
    }

    fileprivate lazy var bridge = GuideScrollBridge(owner: self)

    fileprivate func didScroll(_ scrollView: UIScrollView) {
        guard !locking else { return }
        locking = true
        let x = scrollView.contentOffset.x
        pendingX = x
        if scrollView === bodyScroll {
            headerScroll?.contentOffset.x = x
        } else if scrollView === headerScroll {
            bodyScroll?.contentOffset.x = x
        }
        locking = false
    }
}

enum GuideScrollRole {
    case header
    case body
}

private final class GuideScrollBridge: NSObject, UIScrollViewDelegate {
    weak var owner: GuideScrollSync?

    init(owner: GuideScrollSync) {
        self.owner = owner
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        owner?.didScroll(scrollView)
    }
}

/// UIScrollView wrapper so the time header and program grid stay locked horizontally.
private struct GuideLinkedScrollView<Content: View>: UIViewRepresentable {
    let axis: Axis
    let showsIndicators: Bool
    let sync: GuideScrollSync
    let role: GuideScrollRole
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = showsIndicators && axis == .horizontal
        scroll.showsVerticalScrollIndicator = showsIndicators && axis == .vertical
        scroll.alwaysBounceHorizontal = axis == .horizontal
        scroll.alwaysBounceVertical = false
        scroll.bounces = true
        scroll.backgroundColor = .clear
        scroll.clipsToBounds = true
        #if os(iOS)
        scroll.contentInsetAdjustmentBehavior = .never
        #endif

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            host.view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        context.coordinator.hosting = host
        context.coordinator.scrollView = scroll

        DispatchQueue.main.async {
            sync.register(scroll, role: role)
        }

        return scroll
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hosting?.rootView = content()
        // Re-register in case the scroll view instance is reused after state changes.
        DispatchQueue.main.async {
            sync.register(scrollView, role: role)
        }
    }

    final class Coordinator {
        var hosting: UIHostingController<Content>?
        weak var scrollView: UIScrollView?
    }
}
