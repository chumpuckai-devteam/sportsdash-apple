import SwiftUI

// MARK: - Layout constants (mirror Flutter guide)

private enum GuideMetrics {
    /// 12h window keeps horizontal content lighter on device memory.
    static let hours = 12
    static let pxPerHour: CGFloat = 140
    #if os(tvOS)
    static let channelColWidth: CGFloat = 220
    static let rowHeight: CGFloat = SportsTVMetrics.channelRowHeight
    #else
    static let channelColWidth: CGFloat = 120
    static let rowHeight: CGFloat = 78
    #endif
    static let timeHeaderHeight: CGFloat = 36

    static var timelineWidth: CGFloat { CGFloat(hours) * pxPerHour }
}

/// Traditional TV guide + optional card grid, with a small guide-only settings menu.
struct GuideView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedGroup: String = ""
    @State private var windowStart: Date = GuideView.snappedNowMinusOneHour()
    @State private var playerRoute: PlayerRoute?
    @State private var nowTick = Date()
    @State private var sideWorkTask: Task<Void, Never>?
    @State private var ratingsTask: Task<Void, Never>?
    @State private var showGuideSettings = false
    @State private var showCategoryPicker = false
    /// Guide-only filter: now-playing looks like a movie (XMLTV categories + signals).
    @State private var moviesOnly = false

    private var displayMode: GuideLayoutMode {
        appModel.playerPrefs.guideLayout
    }

    private var groupNames: [String] {
        appModel.channelGroupNames
    }

    private var activeChannels: [IptvChannel] {
        guard !selectedGroup.isEmpty else {
            return appModel.channels(inGroup: groupNames.first ?? "")
        }
        return appModel.channels(inGroup: selectedGroup)
    }

    private var cleanNames: Bool { appModel.playerPrefs.cleanUpNames }

    private var guideRows: [GuideChannelRowData] {
        // Reference EPG map; LazyVStack/List only mount visible rows.
        let chans = activeChannels
        var rows: [GuideChannelRowData] = []
        rows.reserveCapacity(chans.count)
        for ch in chans {
            let programs = appModel.epgByChannel[ch.id] ?? []
            if moviesOnly {
                let now = programs.first(where: \.isNow) ?? programs.first
                let isMovie = now.map { prog in
                    MovieDetection.isMovieCandidate(
                        title: prog.title,
                        categories: prog.categories,
                        channelGroup: ch.group ?? selectedGroup,
                        channelName: ch.name
                    )
                } ?? false
                if !isMovie { continue }
            }
            rows.append(GuideChannelRowData(channel: ch, programs: programs))
        }
        return rows
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
                    VStack(spacing: 24) {
                        ContentUnavailableView(
                            "No channels in this category",
                            systemImage: "tv",
                            description: Text("Pick another category.")
                        )
                        #if os(tvOS)
                        if !groupNames.isEmpty {
                            Button("Choose category") { showCategoryPicker = true }
                                .sportsTVFocusClean()
                        }
                        #endif
                    }
                } else {
                    guideContent
                }
            }
            .background(SportsColors.voidBlack)
            .navigationTitle("Guide")
            .sportsNavTitleMode(large: false)
            .toolbar {
                ToolbarItem(placement: SportsToolbarPlacement.leading) {
                    if !groupNames.isEmpty {
                        #if os(tvOS)
                        // Toolbar only labels current group; real picker is in-content (focusable).
                        Text(selectedGroup.isEmpty ? "Category" : selectedGroup)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SportsColors.gold)
                            .lineLimit(1)
                        #else
                        SportsCategoryMenu(
                            title: selectedGroup,
                            selection: $selectedGroup,
                            options: groupNames
                        )
                        #endif
                    }
                }
                ToolbarItem(placement: SportsToolbarPlacement.trailing) {
                    guideSettingsMenu
                }
            }
            .task {
                if selectedGroup.isEmpty {
                    selectedGroup = groupNames.first ?? ""
                }
                // Background only — never block first Guide paint on EPG network.
                scheduleGuideSideWork()
            }
            .onChange(of: selectedGroup) { _, _ in
                // Category switch must feel instant: UI updates from selectedGroup immediately;
                // EPG fill + ratings run deferred.
                scheduleGuideSideWork()
            }
            .onChange(of: appModel.epgLoadedCount) { _, _ in
                // Debounced ratings only (EPG already published)
                scheduleRatingsOnly()
            }
            .onChange(of: appModel.channelGroupNames) { _, names in
                if selectedGroup.isEmpty || !names.contains(selectedGroup) {
                    selectedGroup = names.first ?? ""
                }
            }
            .onChange(of: appModel.channels.count) { _, _ in
                if selectedGroup.isEmpty {
                    selectedGroup = groupNames.first ?? ""
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
                // Progress bars only need minute-level refresh (was 30s full guide redraw).
                nowTick = date
            }
            .sportsPlayerCover(item: $playerRoute) { route in
                PlayerView(
                    channel: route.channel,
                    game: route.game,
                    alternateMatches: route.alternates
                )
                .environmentObject(appModel)
            }
            .sheet(isPresented: $showGuideSettings) {
                guideSettingsSheet
            }
            #if os(tvOS)
            .fullScreenCover(isPresented: $showCategoryPicker) {
                SportsCategoryPickerScreen(
                    selection: $selectedGroup,
                    options: groupNames,
                    onDone: { showCategoryPicker = false }
                )
                .background(SportsColors.voidBlack.ignoresSafeArea())
            }
            #endif
        }
    }

    @ViewBuilder
    private var guideSettingsControl: some View {
        #if os(tvOS)
        Button {
            showGuideSettings = true
        } label: {
            SportsTVFocused { focused in
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                    .frame(width: SportsTVMetrics.minFocusSize, height: SportsTVMetrics.minFocusSize)
                    .background {
                        Circle().fill(focused ? SportsColors.gold : SportsColors.panelElevated)
                    }
                    .overlay {
                        Circle().stroke(
                            focused ? SportsColors.goldDim : SportsColors.border.opacity(0.4),
                            lineWidth: focused ? 2 : 1
                        )
                    }
                    .scaleEffect(focused ? SportsTVMetrics.chipFocusScale : 1.0)
                    .animation(SportsTVFocusMotion.animation, value: focused)
            }
        }
        .sportsTVFocusClean()
        .accessibilityLabel("Guide settings")
        #else
        Menu {
            guideSettingsButtons
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(SportsColors.gold)
                .frame(width: 32, height: 32)
                .sportsGlass(in: Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Guide settings")
        #endif
    }

    @ViewBuilder
    private var guideSettingsButtons: some View {
        Button {
            Task { await appModel.reloadEpg(force: true) }
        } label: {
            Label(
                appModel.isLoadingEpg ? "Refreshing EPG…" : "Reload EPG",
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(appModel.isLoadingEpg)

        Divider()

        Section("Layout") {
            ForEach(GuideLayoutMode.allCases) { mode in
                Button {
                    var p = appModel.playerPrefs
                    p.guideLayout = mode
                    appModel.setPlayerPrefs(p)
                } label: {
                    if displayMode == mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Label(
                            mode.label,
                            systemImage: mode == .list ? "list.bullet.rectangle" : "square.grid.2x2"
                        )
                    }
                }
            }
        }

        Divider()

        Button {
            moviesOnly.toggle()
        } label: {
            Label(
                moviesOnly ? "Movies now · On" : "Movies now",
                systemImage: moviesOnly ? "film.fill" : "film"
            )
        }
    }

    private var guideSettingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await appModel.reloadEpg(force: true) }
                    } label: {
                        Label(
                            appModel.isLoadingEpg ? "Refreshing EPG…" : "Reload EPG",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(appModel.isLoadingEpg)
                }

                Section {
                    ForEach(GuideLayoutMode.allCases) { mode in
                        Button {
                            var p = appModel.playerPrefs
                            p.guideLayout = mode
                            appModel.setPlayerPrefs(p)
                            showGuideSettings = false
                        } label: {
                            HStack {
                                Label(
                                    mode.label,
                                    systemImage: mode == .list ? "list.bullet.rectangle" : "square.grid.2x2"
                                )
                                Spacer()
                                if displayMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(SportsColors.gold)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Layout")
                } footer: {
                    Text(
                        displayMode == .list
                            ? "Timeline grid: channel rows × time."
                            : "Card grid: Now / Next per channel."
                    )
                }

                Section {
                    Toggle(isOn: $moviesOnly) {
                        Label("Movies now", systemImage: "film")
                    }
                    .tint(SportsColors.gold)
                } header: {
                    Text("Filter")
                } footer: {
                    Text("Uses XMLTV categories when present, plus channel/title movie signals.")
                }
            }
            .navigationTitle("Guide settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showGuideSettings = false }
                }
            }
        }
    }

    // legacy name used by toolbar
    private var guideSettingsMenu: some View {
        guideSettingsControl
    }

    @ViewBuilder
    private var guideContent: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
            // Large in-content control — toolbar sheets don't take focus reliably.
            // Custom gold focus (no .card white lift). focusSection separates from channel list.
            if !groupNames.isEmpty {
                Button {
                    showCategoryPicker = true
                } label: {
                    SportsTVFocused { focused in
                        HStack(spacing: 14) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.title2)
                                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Category")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.7) : SportsColors.muted)
                                Text(selectedGroup.isEmpty ? "Select group" : selectedGroup)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(activeChannels.count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.7) : SportsColors.muted)
                            Image(systemName: "chevron.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, minHeight: SportsTVMetrics.minFocusSize, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: SportsTVMetrics.focusCorner, style: .continuous)
                                .fill(focused ? SportsColors.gold : SportsColors.panelElevated)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: SportsTVMetrics.focusCorner, style: .continuous)
                                .stroke(
                                    focused ? SportsColors.goldDim : SportsColors.border.opacity(0.4),
                                    lineWidth: focused ? 2 : 1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: SportsTVMetrics.focusCorner, style: .continuous))
                        .shadow(color: focused ? SportsColors.gold.opacity(0.28) : .clear, radius: 12, y: 0)
                        .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
                        .animation(SportsTVFocusMotion.animation, value: focused)
                    }
                }
                .sportsTVFocusClean()
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .focusSection()
            }
            #endif

            if appModel.isLoadingEpg {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(SportsColors.gold)
                    Text(epgStatusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SportsColors.muted)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SportsColors.panel)
            }

            switch displayMode {
            case .list:
                GuideTimelineGrid(
                    rows: guideRows,
                    windowStart: windowStart,
                    now: nowTick,
                    cleanUpNames: cleanNames,
                    onPlay: { channel in
                        playerRoute = PlayerRoute(channel: channel, game: nil, alternates: [])
                    }
                )
            case .grid:
                guideCardList
            }
        }
    }

    private var epgStatusText: String {
        if let s = appModel.epgStatus, !s.isEmpty { return s }
        let total = max(appModel.channels.count, 1)
        let loaded = appModel.epgLoadedCount
        if loaded == 0 {
            return "Downloading program guide…"
        }
        return "EPG \(loaded)/\(total) channels"
    }

    /// Card-style Now / Next rows (grid view).
    private var guideCardList: some View {
        List {
            Section {
                ForEach(guideRows) { row in
                    GuideCardRow(
                        channel: row.channel,
                        programs: row.programs,
                        cleanUpNames: cleanNames,
                        categoryName: selectedGroup,
                        onPlay: {
                            playerRoute = PlayerRoute(channel: row.channel, game: nil, alternates: [])
                        }
                    )
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
        .sportsInsetGroupedList()
        .sportsHideScrollBackground()
    }

    private func prefetchRatings() {
        MovieRatingsStore.shared.prefetch(
            channels: activeChannels,
            epgByChannel: appModel.epgByChannel,
            categoryName: selectedGroup
        )
    }

    /// Coalesce rapid category taps / EPG updates.
    private func scheduleGuideSideWork() {
        sideWorkTask?.cancel()
        let group = selectedGroup
        let chans = activeChannels
        sideWorkTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms debounce
            guard !Task.isCancelled else { return }
            await appModel.loadEpgIfNeeded(for: chans)
            guard !Task.isCancelled, selectedGroup == group else { return }
            prefetchRatings()
        }
    }

    private func scheduleRatingsOnly() {
        ratingsTask?.cancel()
        ratingsTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            prefetchRatings()
        }
    }

    private static func snappedNowMinusOneHour() -> Date {
        let n = Date()
        let cal = Calendar.current
        let hour = cal.dateInterval(of: .hour, for: n)?.start ?? n
        return cal.date(byAdding: .hour, value: -1, to: hour) ?? hour
    }
}

// MARK: - Card row (grid view)

private struct GuideCardRow: View {
    let channel: IptvChannel
    let programs: [EpgProgram]
    var cleanUpNames: Bool = true
    var categoryName: String = ""
    var onPlay: () -> Void

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

    private var groupForRatings: String {
        channel.group ?? categoryName
    }

    private var forceMovieRatings: Bool {
        // Channel folder force + P0 XMLTV category movie flag on now-playing.
        if let now, XmltvCategory.saysMovie(now.categories) { return true }
        let g = groupForRatings.lowercased()
        let n = channel.name.lowercased()
        return g.contains("movie") || g.contains("cinema") || g.contains("film")
            || n.contains("cinema") || n.contains("movie") || n.contains("hbo")
            || n.contains("starz") || n.contains("showtime")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPlay) {
                #if os(tvOS)
                SportsTVFocused { focused in
                    cardTitleRow(focused: focused)
                }
                #else
                cardTitleRow(focused: false)
                #endif
            }
            #if os(tvOS)
            .sportsTVFocusClean()
            #else
            .buttonStyle(.plain)
            #endif

            VStack(alignment: .leading, spacing: 6) {
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

                if let now, let cat = now.categoryChipLabel {
                    GuideCategoryChip(label: cat, emphasized: XmltvCategory.saysMovie(now.categories))
                }

                if let now {
                    MovieRatingLoader(
                        title: now.title,
                        categories: now.categories,
                        channelGroup: groupForRatings,
                        channelName: channel.name,
                        compact: true,
                        forceMovie: forceMovieRatings
                    )
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(SportsColors.border.opacity(0.45))
                        Capsule()
                            .fill(SportsColors.live.opacity(0.85))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 3)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onPlay)

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
                .contentShape(Rectangle())
                .onTapGesture(perform: onPlay)
            }
        }
        .padding(.vertical, 2)
    }

    private func cardTitleRow(focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack {
            Text(ChannelNameCleanup.displayName(channel.name, enabled: cleanUpNames))
                .font(.body.weight(.semibold))
                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                .lineLimit(1)
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                .symbolRenderingMode(.hierarchical)
        }
        .padding(.horizontal, focused ? 12 : 0)
        .padding(.vertical, focused ? 10 : 0)
        #if os(tvOS)
        .frame(minHeight: SportsTVMetrics.minFocusSize)
        .background {
            shape.fill(focused ? SportsColors.gold : Color.clear)
        }
        .overlay {
            if focused {
                shape.stroke(SportsColors.goldDim, lineWidth: 2)
            }
        }
        .clipShape(shape)
        .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        #endif
    }
}

// MARK: - Row model

private struct GuideChannelRowData: Identifiable {
    var id: String { channel.id }
    let channel: IptvChannel
    let programs: [EpgProgram]
}

// MARK: - Timeline grid (lazy rows — avoids O(channels × programs) views)

private struct GuideTimelineGrid: View {
    let rows: [GuideChannelRowData]
    let windowStart: Date
    let now: Date
    var cleanUpNames: Bool = true
    let onPlay: (IptvChannel) -> Void

    @StateObject private var scrollSync = GuideScrollSync()
    #if os(tvOS)
    @Namespace private var guideFocusNS
    #endif

    private var windowEnd: Date {
        Calendar.current.date(byAdding: .hour, value: GuideMetrics.hours, to: windowStart) ?? windowStart
    }

    var body: some View {
        VStack(spacing: 0) {
            timeHeader
                .frame(height: GuideMetrics.timeHeaderHeight)
                .background(SportsColors.panel)

            Rectangle()
                .fill(SportsColors.border.opacity(0.5))
                .frame(height: 1)

            // Lazy rows: only visible channels mount program views.
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        GuideTimelineRow(
                            row: row,
                            windowStart: windowStart,
                            windowEnd: windowEnd,
                            now: now,
                            cleanUpNames: cleanUpNames,
                            scrollSync: scrollSync,
                            onPlay: onPlay,
                            prefersDefault: index == 0
                            #if os(tvOS)
                            , focusNamespace: guideFocusNS
                            #endif
                        )
                    }
                }
                #if os(tvOS)
                .focusSection()
                .padding(.leading, 8)
                #endif
            }
        }
        .background(SportsColors.voidBlack)
        #if os(tvOS)
        .focusScope(guideFocusNS)
        #endif
        // No auto jump / snap — user freely scrolls horizontally.
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
                showsIndicators: true,
                sync: scrollSync,
                role: .header
            ) {
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
            }
        }
    }

    private func hourLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f.string(from: date).lowercased()
    }
}

/// One channel row: fixed label + horizontally synced program strip.
private struct GuideTimelineRow: View {
    let row: GuideChannelRowData
    let windowStart: Date
    let windowEnd: Date
    let now: Date
    let cleanUpNames: Bool
    @ObservedObject var scrollSync: GuideScrollSync
    let onPlay: (IptvChannel) -> Void
    /// First visible row prefers default focus when the guide appears.
    var prefersDefault: Bool = false
    #if os(tvOS)
    var focusNamespace: Namespace.ID? = nil
    #endif

    var body: some View {
        HStack(spacing: 0) {
            channelNameCell
                .zIndex(2)

            GuideLinkedScrollView(
                axis: .horizontal,
                showsIndicators: false,
                sync: scrollSync,
                role: .body
            ) {
                ZStack(alignment: .topLeading) {
                    ForEach(0...GuideMetrics.hours, id: \.self) { h in
                        Rectangle()
                            .fill(SportsColors.border.opacity(0.35))
                            .frame(width: 1, height: GuideMetrics.rowHeight)
                            .offset(x: CGFloat(h) * GuideMetrics.pxPerHour)
                    }

                    ForEach(visiblePrograms, id: \.id) { program in
                        programBlock(program)
                    }
                }
                .frame(width: GuideMetrics.timelineWidth, height: GuideMetrics.rowHeight, alignment: .topLeading)
                .background(SportsColors.voidBlack)
            }
            .zIndex(0)
        }
        .frame(height: GuideMetrics.rowHeight)
        #if os(tvOS)
        .padding(.vertical, SportsTVMetrics.rowVerticalGutter)
        #else
        .padding(.vertical, 4)
        #endif
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SportsColors.border.opacity(0.35))
                .frame(height: 0.5)
        }
    }

    /// Channel label — gold fill when focused; no system white focus plume.
    /// S-TV.1: `SportsTVFocused` + `sportsTVFocusClean()` only (no `@FocusState` / `.card`).
    @ViewBuilder
    private var channelNameCell: some View {
        Button {
            onPlay(row.channel)
        } label: {
            #if os(tvOS)
            SportsTVFocused { focused in
                channelLabel(focused: focused)
            }
            #else
            channelLabel(focused: false)
            #endif
        }
        #if os(tvOS)
        .sportsTVFocusClean()
        .modifier(GuideDefaultFocusModifier(enabled: prefersDefault, namespace: focusNamespace))
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(ChannelNameCleanup.displayName(row.channel.name, enabled: cleanUpNames))
        .accessibilityHint("Plays channel")
    }

    @ViewBuilder
    private func channelLabel(focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: SportsTVMetrics.channelCorner, style: .continuous)
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(focused ? SportsColors.voidBlack.opacity(0.22) : SportsColors.voidBlack)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                }

            Text(ChannelNameCleanup.displayName(row.channel.name, enabled: cleanUpNames))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(width: GuideMetrics.channelColWidth, height: GuideMetrics.rowHeight, alignment: .leading)
        .background {
            shape.fill(focused ? SportsColors.gold : SportsColors.panelElevated)
        }
        .overlay {
            if focused {
                shape.stroke(SportsColors.goldDim, lineWidth: 2)
            }
        }
        .clipShape(shape)
        .shadow(color: focused ? SportsColors.gold.opacity(0.32) : .clear, radius: 10, y: 0)
        #if os(tvOS)
        .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        #endif
    }

    private var visiblePrograms: [EpgProgram] {
        let inWindow = row.programs.filter { $0.end > windowStart && $0.start < windowEnd }
        if !inWindow.isEmpty { return inWindow }
        let title = row.programs.isEmpty ? "No EPG data" : "No programs in this time range"
        return [
            EpgProgram(
                channelKey: row.channel.id,
                title: title,
                start: windowStart,
                end: min(windowEnd, windowStart.addingTimeInterval(3600 * 3)),
                description: nil
            )
        ]
    }

    @ViewBuilder
    private func programBlock(_ program: EpgProgram) -> some View {
        let start = max(program.start, windowStart)
        let end = min(program.end, windowEnd)
        let left = CGFloat(start.timeIntervalSince(windowStart) / 3600.0) * GuideMetrics.pxPerHour
        let width = max(28, CGFloat(end.timeIntervalSince(start) / 3600.0) * GuideMetrics.pxPerHour)
        let airing = program.start <= now && now < program.end

        VStack(alignment: .leading, spacing: 2) {
            Text(program.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SportsColors.text)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(shortTimeRange(program))
                    .font(.system(size: 10))
                    .foregroundStyle(SportsColors.muted)
                    .lineLimit(1)
                if width > 96, let cat = program.categoryChipLabel {
                    GuideCategoryChip(
                        label: cat,
                        emphasized: XmltvCategory.saysMovie(program.categories),
                        compact: true
                    )
                }
            }
            if airing {
                MovieRatingLoader(
                    title: program.title,
                    categories: program.categories,
                    channelGroup: row.channel.group,
                    channelName: row.channel.name,
                    compact: true,
                    forceMovie: XmltvCategory.saysMovie(program.categories)
                        || (row.channel.group ?? "").localizedCaseInsensitiveContains("movie")
                        || row.channel.name.localizedCaseInsensitiveContains("cinema")
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width - 4, height: GuideMetrics.rowHeight - 12, alignment: .topLeading)
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
        .contentShape(Rectangle())
        .onTapGesture { onPlay(row.channel) }
        .offset(x: left + 2, y: 8)
    }

    private func shortTimeRange(_ p: EpgProgram) -> String {
        let f = Self.shortTimeFormatter
        return "\(f.string(from: p.start)) – \(f.string(from: p.end))"
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - XMLTV category chip

private struct GuideCategoryChip: View {
    let label: String
    var emphasized: Bool = false
    var compact: Bool = false

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: compact ? 8 : 9, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(emphasized ? SportsColors.voidBlack : SportsColors.gold)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 3)
            .background(
                Capsule(style: .continuous)
                    .fill(emphasized ? SportsColors.gold : SportsColors.gold.opacity(0.16))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(SportsColors.gold.opacity(emphasized ? 0 : 0.45), lineWidth: 0.5)
            }
            .accessibilityLabel("Category \(label)")
    }
}

#if os(tvOS)
/// Applies `prefersDefaultFocus` when a namespace is provided (Guide first channel).
private struct GuideDefaultFocusModifier: ViewModifier {
    let enabled: Bool
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, let namespace {
            content.prefersDefaultFocus(true, in: namespace)
        } else {
            content
        }
    }
}
#endif

// MARK: - Linked horizontal scroll (header ↔ many lazy body rows)

@MainActor
final class GuideScrollSync: ObservableObject {
    weak var headerScroll: UIScrollView?
    /// Weak set of visible row scroll views (LazyVStack recycles these).
    private let bodyScrolls = NSHashTable<UIScrollView>.weakObjects()
    private var locking = false
    /// Shared free-scroll offset (user-controlled only — never auto-jump to “now”).
    private(set) var sharedOffsetX: CGFloat = 0

    func register(_ scrollView: UIScrollView, role: GuideScrollRole) {
        #if os(iOS)
        scrollView.isPagingEnabled = false
        #endif
        scrollView.decelerationRate = .normal
        switch role {
        case .header:
            headerScroll = scrollView
        case .body:
            bodyScrolls.add(scrollView)
        }
        scrollView.delegate = bridge
        // Align newly visible rows to the user's current offset only (no global re-snap).
        if abs(scrollView.contentOffset.x - sharedOffsetX) > 0.5 {
            locking = true
            scrollView.contentOffset.x = sharedOffsetX
            locking = false
        }
    }

    private func apply(_ x: CGFloat, excluding: UIScrollView?) {
        locking = true
        sharedOffsetX = x
        let offset = CGPoint(x: x, y: 0)
        if headerScroll !== excluding {
            headerScroll?.setContentOffset(offset, animated: false)
        }
        for body in bodyScrolls.allObjects where body !== excluding {
            body.setContentOffset(offset, animated: false)
        }
        locking = false
    }

    fileprivate lazy var bridge = GuideScrollBridge(owner: self)

    fileprivate func didScroll(_ scrollView: UIScrollView) {
        guard !locking else { return }
        apply(scrollView.contentOffset.x, excluding: scrollView)
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
        // Preserve user scroll position when SwiftUI refreshes row content (e.g. EPG updates).
        let savedX = scrollView.contentOffset.x
        context.coordinator.hosting?.rootView = content()
        scrollView.layoutIfNeeded()
        if abs(scrollView.contentOffset.x - savedX) > 0.5 {
            scrollView.contentOffset.x = savedX
        }
        // Align recycled rows to shared offset without forcing a jump-to-now.
        let target = sync.sharedOffsetX
        if abs(scrollView.contentOffset.x - target) > 0.5 {
            scrollView.contentOffset.x = target
        }
    }

    final class Coordinator {
        var hosting: UIHostingController<Content>?
        weak var scrollView: UIScrollView?
    }
}
