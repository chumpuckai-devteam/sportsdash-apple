import SwiftUI

// MARK: - Layout constants (mirror Flutter guide)

private enum GuideMetrics {
    /// 12h window keeps horizontal content lighter on device memory.
    static let hours = 12
    #if os(tvOS)
    static let pxPerHour: CGFloat = 280
    #else
    static let pxPerHour: CGFloat = 140
    #endif
    #if os(tvOS)
    static let channelColWidth: CGFloat = 220
    static let rowHeight: CGFloat = SportsTVMetrics.channelRowHeight
    #else
    static let channelColWidth: CGFloat = 148
    static let rowHeight: CGFloat = 78
    #endif
    static let timeHeaderHeight: CGFloat = 36

    static var timelineWidth: CGFloat { CGFloat(hours) * pxPerHour }
}

/// Traditional TV guide + optional card grid, with a small guide-only settings menu.
struct GuideView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var epg: EpgStore
    @State private var selectedGroup: String = ""
    @State private var windowStart: Date = GuideView.snappedCurrentHour()
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
        // ★ Favorites first (Android parity), then provider order.
        [AppModel.favoritesChannelGroup] + appModel.channelGroupNames
    }

    /// Prefer first **populated** category — never strand on empty ★ Favorites.
    private var defaultGuideGroup: String {
        let fav = AppModel.favoritesChannelGroup
        let favCount = appModel.channels(inGroup: fav).count
        if favCount > 0 { return fav }
        return appModel.channelGroupNames.first ?? fav
    }

    private var activeChannels: [IptvChannel] {
        guard !selectedGroup.isEmpty else {
            return appModel.channels(inGroup: defaultGuideGroup)
        }
        return appModel.channels(inGroup: selectedGroup)
    }

    private var cleanNames: Bool { appModel.playerPrefs.cleanUpNames }

    private var guideRows: [GuideChannelRowData] {
        // Reference EPG map; LazyVStack/List only mount visible rows.
        // Dedupe playlist clones (same display name in group — common on Xtream).
        let chans = Self.dedupeChannels(activeChannels, epg: epg.epgByChannel)
        var rows: [GuideChannelRowData] = []
        rows.reserveCapacity(chans.count)
        for ch in chans {
            if ch.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let programs = epg.epgByChannel[ch.id] ?? []
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

    /// Prefer the stream that already has EPG when names collide.
    private static func dedupeChannels(
        _ channels: [IptvChannel],
        epg: [String: [EpgProgram]]
    ) -> [IptvChannel] {
        var bestByKey: [String: IptvChannel] = [:]
        var order: [String] = []
        order.reserveCapacity(channels.count)
        for ch in channels {
            let key = ChannelNameCleanup.displayName(ch.name, enabled: true)
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = key.isEmpty ? ch.id : key
            if bestByKey[normalized] == nil {
                bestByKey[normalized] = ch
                order.append(normalized)
                continue
            }
            let existing = bestByKey[normalized]!
            let existingCount = epg[existing.id]?.count ?? 0
            let newCount = epg[ch.id]?.count ?? 0
            // Keep richer EPG; tie-break shorter id (stable).
            if newCount > existingCount
                || (newCount == existingCount && ch.id < existing.id) {
                bestByKey[normalized] = ch
            }
        }
        return order.compactMap { bestByKey[$0] }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appModel.channels.isEmpty {
                    #if os(iOS)
                    VStack(spacing: 16) {
                        JumbotronScreenTitle(first: "CHANNEL ", gold: "GUIDE")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SetupChecklistCard(forceTitle: "LOAD A PLAYLIST FIRST")
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, SportsMetrics.screenInset)
                    .padding(.top, 8)
                    #else
                    ContentUnavailableView(
                        "Load a playlist first",
                        systemImage: "rectangle.grid.1x2",
                        description: Text("Configure Xtream or M3U in Settings to show the guide.")
                    )
                    #endif
                } else if activeChannels.isEmpty {
                    VStack(spacing: 24) {
                        #if os(iOS)
                        JumbotronMessagePanel(
                            title: "NO CHANNELS IN THIS CATEGORY",
                            subtitle: "Pick another category.",
                            cta: "CHOOSE CATEGORY",
                            action: { showCategoryPicker = true }
                        )
                        .padding(.horizontal, SportsMetrics.screenInset)
                        #else
                        ContentUnavailableView(
                            "No channels in this category",
                            systemImage: "tv",
                            description: Text("Pick another category.")
                        )
                        #if os(tvOS)
                        if !groupNames.isEmpty {
                            Button {
                                showCategoryPicker = true
                            } label: {
                                SportsTVFocused { focused in
                                    Text("Choose category")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                                        .padding(.horizontal, 28)
                                        .padding(.vertical, 16)
                                        .frame(minHeight: SportsTVMetrics.minFocusSize)
                                        .background {
                                            Capsule(style: .continuous)
                                                .fill(focused ? SportsColors.gold : SportsColors.panelElevated)
                                        }
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .stroke(
                                                    focused ? SportsColors.goldDim : SportsColors.border.opacity(0.4),
                                                    lineWidth: focused ? 2 : 1
                                                )
                                        }
                                        .clipShape(Capsule(style: .continuous))
                                        .scaleEffect(focused ? SportsTVMetrics.chipFocusScale : 1.0)
                                        .animation(SportsTVFocusMotion.animation, value: focused)
                                }
                            }
                            .sportsTVFocusClean()
                        }
                        #endif
                        #endif
                    }
                } else {
                    guideContent
                }
            }
            .sportsScreenBackground()
            #if os(iOS)
            .navigationTitle("")
            .sportsNavTitleMode(large: false)
            .toolbarBackground(.hidden, for: .navigationBar)
            .jumbotronAXCap()
            #else
            .navigationTitle("Guide")
            .sportsNavTitleMode(large: false)
            #endif
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
                        if displayMode == .grid {
                            SportsCategoryMenu(
                                title: selectedGroup,
                                selection: $selectedGroup,
                                options: groupNames,
                                onOpen: { showCategoryPicker = true }
                            )
                        }
                        #endif
                    }
                }
                ToolbarItem(placement: SportsToolbarPlacement.trailing) {
                    guideSettingsMenu
                }
            }
            .task {
                if selectedGroup.isEmpty {
                    selectedGroup = defaultGuideGroup
                }
                // Always open on the current hour (left edge of timeline).
                windowStart = Self.snappedCurrentHour()
                nowTick = Date()
                // Background only — never block first Guide paint on EPG network.
                scheduleGuideSideWork()
            }
            .onChange(of: selectedGroup) { _, _ in
                // Category switch must feel instant: UI updates from selectedGroup immediately;
                // EPG fill + ratings run deferred.
                scheduleGuideSideWork()
            }
            .onChange(of: epg.epgLoadedCount) { _, _ in
                // Debounced ratings only (EPG already published)
                scheduleRatingsOnly()
            }
            .onChange(of: appModel.channelGroupNames) { _, names in
                if selectedGroup.isEmpty || !names.contains(selectedGroup) {
                    selectedGroup = defaultGuideGroup
                }
                // If parked on empty Favorites after unstar-all, jump to a real category.
                if selectedGroup == AppModel.favoritesChannelGroup,
                   appModel.channels(inGroup: selectedGroup).isEmpty,
                   let first = appModel.channelGroupNames.first {
                    selectedGroup = first
                }
            }
            .onChange(of: appModel.channels.count) { _, _ in
                if selectedGroup.isEmpty {
                    selectedGroup = defaultGuideGroup
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
                nowTick = date
                // Roll the grid when the clock crosses into a new hour.
                let hour = Self.snappedCurrentHour()
                if hour != windowStart {
                    windowStart = hour
                }
            }
            .sportsPlayerCover(item: $playerRoute) { route in
                PlayerView(
                    channel: route.channel,
                    game: route.game,
                    alternateMatches: route.alternates
                )
                .environmentObject(appModel)
                .environmentObject(appModel.epg)
            }
            .sheet(isPresented: $showGuideSettings) {
                guideSettingsSheet
            }
            .sportsLargeCover(isPresented: $showCategoryPicker) {
                SportsCategoryPickerScreen(
                    selection: $selectedGroup,
                    options: groupNames,
                    onDone: { showCategoryPicker = false }
                )
                .sportsLargePresentation()
                .background(SportsColors.voidBlack.ignoresSafeArea())
            }
        }
    }

    @ViewBuilder
    private var guideSettingsControl: some View {
        #if os(tvOS)
        SportsTVIconButton(
            systemName: "ellipsis.circle",
            accessibilityLabelText: "Guide settings"
        ) {
            showGuideSettings = true
        }
        #else
        Menu {
            guideSettingsButtons
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(SportsColors.gold)
                .frame(width: 32, height: 32)
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
                epg.isLoadingEpg ? "Refreshing EPG…" : "Reload EPG",
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(epg.isLoadingEpg)

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
            ZStack {
                #if os(tvOS)
                SportsColors.voidBlack.ignoresSafeArea()
                #endif
                List {
                    Section {
                        Button {
                            Task { await appModel.reloadEpg(force: true) }
                        } label: {
                            #if os(tvOS)
                            SportsTVListRowLabel {
                                Label(
                                    epg.isLoadingEpg ? "Refreshing EPG…" : "Reload EPG",
                                    systemImage: "arrow.clockwise"
                                )
                                .foregroundStyle($0 ? SportsColors.voidBlack : SportsColors.text)
                            }
                            #else
                            Label(
                                epg.isLoadingEpg ? "Refreshing EPG…" : "Reload EPG",
                                systemImage: "arrow.clockwise"
                            )
                            #endif
                        }
                        .disabled(epg.isLoadingEpg)
                        #if os(tvOS)
                        .sportsTVFocusClean()
                        .listRowBackground(Color.clear)
                        #endif
                    }

                    Section {
                        ForEach(GuideLayoutMode.allCases) { mode in
                            Button {
                                var p = appModel.playerPrefs
                                p.guideLayout = mode
                                appModel.setPlayerPrefs(p)
                                showGuideSettings = false
                            } label: {
                                #if os(tvOS)
                                SportsTVListRowLabel(selected: displayMode == mode) { focused in
                                    HStack {
                                        Label(
                                            mode.label,
                                            systemImage: mode == .list ? "list.bullet.rectangle" : "square.grid.2x2"
                                        )
                                        .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                                        Spacer()
                                        if displayMode == mode {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                                        }
                                    }
                                }
                                #else
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
                                #endif
                            }
                            #if os(tvOS)
                            .sportsTVFocusClean()
                            .listRowBackground(Color.clear)
                            #endif
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
                        #if os(tvOS)
                        Button {
                            moviesOnly.toggle()
                        } label: {
                            SportsTVListRowLabel(selected: moviesOnly) { focused in
                                HStack {
                                    Label("Movies now", systemImage: moviesOnly ? "film.fill" : "film")
                                        .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                                    Spacer()
                                    Text(moviesOnly ? "On" : "Off")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.75) : SportsColors.muted)
                                }
                            }
                        }
                        .sportsTVFocusClean()
                        .listRowBackground(Color.clear)
                        #else
                        Toggle(isOn: $moviesOnly) {
                            Label("Movies now", systemImage: "film")
                        }
                        .tint(SportsColors.gold)
                        #endif
                    } header: {
                        Text("Filter")
                    } footer: {
                        Text("Uses XMLTV categories when present, plus channel/title movie signals.")
                    }
                }
                #if os(tvOS)
                .listStyle(.plain)
                #endif
            }
            .navigationTitle("Guide settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    #if os(tvOS)
                    SportsTVIconButton(
                        systemName: "xmark",
                        accessibilityLabelText: "Close"
                    ) {
                        showGuideSettings = false
                    }
                    #else
                    Button("Close") { showGuideSettings = false }
                    #endif
                }
            }
        }
        #if os(tvOS)
        .preferredColorScheme(.dark)
        #endif
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
                        .background(focused ? SportsColors.gold : SportsColors.panelGradient)
                        .overlay {
                            Rectangle().stroke(
                                focused ? SportsColors.gold : SportsColors.gold.opacity(0.5),
                                lineWidth: SportsTVMetrics.hairline
                            )
                        }
                        .shadow(color: focused ? SportsColors.ledGlow : .clear, radius: focused ? SportsTVMetrics.focusGlowRadius : 0)
                        .scaleEffect(focused ? SportsTVMetrics.chipFocusScale : 1.0)
                        .animation(SportsTVFocusMotion.animation, value: focused)
                    }
                }
                .sportsTVFocusClean()
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .focusSection()
            }
            #endif

            if epg.isLoadingEpg || epg.isAutoFillingEpg {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(SportsColors.gold)
                    Text(epgStatusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SportsColors.muted)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SportsColors.panel)
            } else if !activeChannels.isEmpty {
                let withGuide = activeChannels.filter { !(epg.epgByChannel[$0.id] ?? []).isEmpty }.count
                HStack(spacing: 8) {
                    Text("Guide \(withGuide)/\(activeChannels.count) in this category")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(withGuide == 0 ? SportsColors.danger : SportsColors.muted)
                    Spacer(minLength: 8)
                    if let s = epg.epgStatus, s.localizedCaseInsensitiveContains("ready") {
                        Text(s)
                            .font(.caption2)
                            .foregroundStyle(SportsColors.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SportsColors.panel.opacity(0.85))
            }

            switch displayMode {
            case .list:
                #if os(iOS)
                GuideNowBarList(
                    rows: guideRows,
                    selectedGroup: selectedGroup,
                    groupNames: groupNames,
                    moviesOnly: moviesOnly,
                    displayMode: displayMode,
                    now: nowTick,
                    cleanNames: cleanNames,
                    favoriteChannelIds: appModel.favoriteChannelIds,
                    epgError: epg.epgError,
                    isLoadingEpg: epg.isLoadingEpg,
                    onSelectGroup: { showCategoryPicker = true },
                    onGrid: {
                        var p = appModel.playerPrefs
                        p.guideLayout = .grid
                        appModel.setPlayerPrefs(p)
                    },
                    onMovies: { moviesOnly.toggle() },
                    onPlay: { channel in
                        playerRoute = PlayerRoute(channel: channel, game: nil, alternates: [])
                    },
                    onToggleFavorite: { channel in
                        appModel.toggleFavoriteChannel(channel)
                    },
                    onChooseCategory: { showCategoryPicker = true },
                    onReloadEPG: { Task { await appModel.reloadEpg(force: true) } }
                )
                #else
                GuideTimelineGrid(
                    rows: guideRows,
                    windowStart: windowStart,
                    now: nowTick,
                    cleanUpNames: cleanNames,
                    favoriteChannelIds: appModel.favoriteChannelIds,
                    onPlay: { channel in
                        playerRoute = PlayerRoute(channel: channel, game: nil, alternates: [])
                    },
                    onToggleFavorite: { channel in
                        appModel.toggleFavoriteChannel(channel)
                    }
                )
                #endif
            case .grid:
                guideCardList
            }
        }
    }

    private var epgStatusText: String {
        if let s = epg.epgStatus, !s.isEmpty { return s }
        let total = max(appModel.channels.count, 1)
        let loaded = epg.epgLoadedCount
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
                        isFavorite: appModel.isFavoriteChannel(row.channel),
                        onPlay: {
                            playerRoute = PlayerRoute(channel: row.channel, game: nil, alternates: [])
                        },
                        onToggleFavorite: {
                            appModel.toggleFavoriteChannel(row.channel)
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
            epgByChannel: epg.epgByChannel,
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

    /// Start of the current local hour — Guide timeline left edge defaults here.
    private static func snappedCurrentHour() -> Date {
        let n = Date()
        let cal = Calendar.current
        return cal.dateInterval(of: .hour, for: n)?.start ?? n
    }
}

// MARK: - Card row (grid view)

private struct GuideCardRow: View {
    let channel: IptvChannel
    let programs: [EpgProgram]
    var cleanUpNames: Bool = true
    var categoryName: String = ""
    var isFavorite: Bool = false
    var onPlay: () -> Void
    var onToggleFavorite: () -> Void = {}

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
            .contextMenu {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(
                        isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: isFavorite ? "star.slash" : "star.fill"
                    )
                }
            }
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

struct GuideChannelRowData: Identifiable {
    var id: String { channel.id }
    let channel: IptvChannel
    let programs: [EpgProgram]
}

private enum GuideGapReason {
    case noData
    case outOfRange
    case between
}

private enum GuideTimelineBlockKind {
    case program
    case gap(GuideGapReason)
}

private struct GuideTimelineBlock: Identifiable {
    let id: String
    let kind: GuideTimelineBlockKind
    let start: Date
    let end: Date
    let program: EpgProgram?
}

// MARK: - Timeline grid (lazy rows — avoids O(channels × programs) views)

private struct GuideTimelineGrid: View {
    let rows: [GuideChannelRowData]
    let windowStart: Date
    let now: Date
    var cleanUpNames: Bool = true
    var favoriteChannelIds: Set<String> = []
    let onPlay: (IptvChannel) -> Void
    var onToggleFavorite: (IptvChannel) -> Void = { _ in }

    @StateObject private var scrollSync = GuideScrollSync()
    /// Always declared so rows can take `focusNamespace:` without mid-list `#if`
    /// (Swift rejects `#if` between call arguments on iOS CI). Consumed only on tvOS.
    @Namespace private var guideFocusNS

    private var windowEnd: Date {
        Calendar.current.date(byAdding: .hour, value: GuideMetrics.hours, to: windowStart) ?? windowStart
    }

    var body: some View {
        VStack(spacing: 0) {
            timeHeader
                .frame(height: GuideMetrics.timeHeaderHeight)
                .background(SportsColors.panel)

            Rectangle()
                .fill(SportsColors.border)
                .frame(height: SportsTVMetrics.hairline)

            // Lazy rows: only visible channels mount program views.
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        GuideTimelineRow(
                            row: row,
                            index: index + 1,
                            windowStart: windowStart,
                            windowEnd: windowEnd,
                            now: now,
                            cleanUpNames: cleanUpNames,
                            isFavorite: favoriteChannelIds.contains(row.channel.id),
                            scrollSync: scrollSync,
                            onPlay: onPlay,
                            onToggleFavorite: { onToggleFavorite(row.channel) },
                            prefersDefault: index == 0,
                            focusNamespace: guideFocusNS
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
        .onAppear {
            // Open scrolled to the left edge = current hour.
            scrollSync.resetToStart()
        }
        .onChange(of: windowStart) { _, _ in
            // New hour window → jump back to "now" (left edge).
            scrollSync.resetToStart()
        }
    }

    private var timeHeader: some View {
        HStack(spacing: 0) {
            Text("CHANNEL")
                .font(JumbotronFonts.display(16))
                .foregroundStyle(SportsColors.muted)
                .frame(width: GuideMetrics.channelColWidth, alignment: .leading)
                .padding(.leading, 12)

            GuideLinkedScrollView(
                axis: .horizontal,
                showsIndicators: true,
                sync: scrollSync,
                role: .header
            ) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(0..<GuideMetrics.hours, id: \.self) { h in
                            let t = Calendar.current.date(byAdding: .hour, value: h, to: windowStart) ?? windowStart
                            Text(hourLabel(t))
                                .font(JumbotronFonts.display(22))
                                .foregroundStyle(SportsColors.goldDim)
                                .frame(width: GuideMetrics.pxPerHour, alignment: .leading)
                                .padding(.leading, 8)
                        }
                    }
                    nowMarker
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

    @ViewBuilder
    private var nowMarker: some View {
        let offset = CGFloat(now.timeIntervalSince(windowStart) / 3600) * GuideMetrics.pxPerHour
        if offset >= 0 && offset <= GuideMetrics.timelineWidth {
            VStack(spacing: 0) {
                JumbotronLED(text: "▼ \(Self.hhmm.string(from: now))", size: 14, color: SportsColors.live, glow: true)
                Rectangle()
                    .fill(SportsColors.live)
                    .frame(width: SportsTVMetrics.hairline)
                    .shadow(color: SportsColors.liveGlow, radius: 6)
            }
            .offset(x: offset)
            .allowsHitTesting(false)
        }
    }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// One channel row: fixed label + horizontally synced program strip.
private struct GuideTimelineRow: View {
    let row: GuideChannelRowData
    var index: Int = 1
    let windowStart: Date
    let windowEnd: Date
    let now: Date
    let cleanUpNames: Bool
    var isFavorite: Bool = false
    @ObservedObject var scrollSync: GuideScrollSync
    let onPlay: (IptvChannel) -> Void
    var onToggleFavorite: () -> Void = {}
    /// First visible row prefers default focus when the guide appears.
    var prefersDefault: Bool = false
    /// Optional focus scope for tvOS default-focus (ignored on iOS). Always present so
    /// callers never need mid-argument-list `#if os(tvOS)`.
    var focusNamespace: Namespace.ID? = nil

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
                    Rectangle()
                        .fill(SportsColors.panel.opacity(0.35))
                        .frame(width: GuideMetrics.timelineWidth, height: GuideMetrics.rowHeight)

                    ForEach(0...GuideMetrics.hours, id: \.self) { h in
                        Rectangle()
                            .fill(SportsColors.border.opacity(0.45))
                            .frame(width: SportsTVMetrics.hairline, height: GuideMetrics.rowHeight)
                            .offset(x: CGFloat(h) * GuideMetrics.pxPerHour)
                    }

                    ForEach(timelineBlocks) { block in
                        timelineBlockView(block)
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
                .fill(SportsColors.gridDot)
                .frame(height: SportsTVMetrics.hairline)
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
        .contextMenu {
            Button {
                onToggleFavorite()
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "star.slash" : "star.fill"
                )
            }
        }
        #endif
        .accessibilityLabel(ChannelNameCleanup.displayName(row.channel.name, enabled: cleanUpNames))
        .accessibilityHint("Plays channel")
    }

    @ViewBuilder
    private func channelLabel(focused: Bool) -> some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(JumbotronBrand.stripe(for: row.channel.group))
                .frame(width: SportsTVMetrics.stripe)
            JumbotronLED(
                text: String(format: "%03d", index),
                size: 16,
                color: focused ? SportsColors.voidBlack : SportsColors.gold,
                glow: !focused
            )
            .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(ChannelNameCleanup.displayName(row.channel.name, enabled: cleanUpNames).uppercased())
                    .font(JumbotronFonts.display(26))
                    .jumbotronDisplayTracking(26)
                    .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                    .lineLimit(2)
                if isFavorite {
                    Text("★").font(JumbotronFonts.display(16)).foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: GuideMetrics.channelColWidth, height: GuideMetrics.rowHeight, alignment: .leading)
        .background(focused ? SportsColors.gold : SportsColors.panelGradient)
        .shadow(color: focused ? SportsColors.ledGlow : .clear, radius: focused ? SportsTVMetrics.focusGlowRadius : 0)
        #if os(tvOS)
        .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        #endif
    }

    /// Real programmes + muted gap fillers so the row is continuous (no black holes).
    private var timelineBlocks: [GuideTimelineBlock] {
        Self.buildTimelineBlocks(
            programs: row.programs,
            windowStart: windowStart,
            windowEnd: windowEnd
        )
    }

    private static func buildTimelineBlocks(
        programs: [EpgProgram],
        windowStart: Date,
        windowEnd: Date
    ) -> [GuideTimelineBlock] {
        let sorted = programs
            .filter { $0.end > windowStart && $0.start < windowEnd }
            .sorted { $0.start < $1.start }

        var blocks: [GuideTimelineBlock] = []
        var cursor = windowStart
        let minGap: TimeInterval = 90 // don't invent tiny slivers

        if sorted.isEmpty {
            return [
                GuideTimelineBlock(
                    id: "gap-full-\(windowStart.timeIntervalSince1970)",
                    kind: .gap(programs.isEmpty ? .noData : .outOfRange),
                    start: windowStart,
                    end: windowEnd,
                    program: nil
                )
            ]
        }

        for (idx, prog) in sorted.enumerated() {
            let segStart = max(prog.start, windowStart)
            let segEnd = min(prog.end, windowEnd)
            if segStart > cursor.addingTimeInterval(minGap) {
                blocks.append(
                    GuideTimelineBlock(
                        id: "gap-\(idx)-\(cursor.timeIntervalSince1970)",
                        kind: .gap(.between),
                        start: cursor,
                        end: segStart,
                        program: nil
                    )
                )
            }
            if segEnd > segStart {
                blocks.append(
                    GuideTimelineBlock(
                        id: prog.id,
                        kind: .program,
                        start: segStart,
                        end: segEnd,
                        program: prog
                    )
                )
                cursor = max(cursor, segEnd)
            }
        }
        if windowEnd > cursor.addingTimeInterval(minGap) {
            blocks.append(
                GuideTimelineBlock(
                    id: "gap-end-\(cursor.timeIntervalSince1970)",
                    kind: .gap(.between),
                    start: cursor,
                    end: windowEnd,
                    program: nil
                )
            )
        }
        return blocks
    }

    @ViewBuilder
    private func timelineBlockView(_ block: GuideTimelineBlock) -> some View {
        let left = CGFloat(block.start.timeIntervalSince(windowStart) / 3600.0) * GuideMetrics.pxPerHour
        let width = max(20, CGFloat(block.end.timeIntervalSince(block.start) / 3600.0) * GuideMetrics.pxPerHour)

        switch block.kind {
        case .program:
            if let program = block.program {
                programBlock(program, left: left, width: width)
            }
        case .gap(let reason):
            gapBlock(reason: reason, left: left, width: width)
        }
    }

    @ViewBuilder
    private func gapBlock(reason: GuideGapReason, left: CGFloat, width: CGFloat) -> some View {
        let label: String = {
            switch reason {
            case .noData: return "No guide"
            case .outOfRange: return "—"
            case .between: return ""
            }
        }()
        HStack {
            if !label.isEmpty, width > 56 {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SportsColors.muted.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: max(16, width - 4), height: GuideMetrics.rowHeight - 16, alignment: .center)
        .background(SportsColors.panel.opacity(0.35))
        .overlay {
            Rectangle().stroke(SportsColors.border.opacity(0.5), lineWidth: SportsTVMetrics.hairline)
        }
        .allowsHitTesting(false)
        .offset(x: left + 2, y: 8)
        .accessibilityLabel(label.isEmpty ? "No program information" : label)
    }

    @ViewBuilder
    private func programBlock(_ program: EpgProgram, left: CGFloat, width: CGFloat) -> some View {
        let airing = program.start <= now && now < program.end

        VStack(alignment: .leading, spacing: 4) {
            Text(program.title.isEmpty ? "Program" : program.title)
                .font(JumbotronFonts.body(16, bold: true))
                .foregroundStyle(SportsColors.text)
                .lineLimit(1)
            JumbotronLED(text: shortTimeRange(program), size: 14, color: SportsColors.gold, glow: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: max(24, width - 4), height: GuideMetrics.rowHeight - 16, alignment: .topLeading)
        .background(airing ? SportsColors.gold.opacity(0.18) : SportsColors.panelGradient)
        .overlay {
            Rectangle().stroke(
                airing ? SportsColors.gold.opacity(0.6) : SportsColors.border,
                lineWidth: SportsTVMetrics.hairline
            )
        }
        .overlay(alignment: .topTrailing) {
            if airing {
                JumbotronLED(text: "LIVE", size: 12, color: SportsColors.live, glow: true)
                    .padding(10)
            }
        }
        .allowsHitTesting(false)
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
    /// Shared free-scroll offset. Defaults to 0 = current hour at left edge.
    private(set) var sharedOffsetX: CGFloat = 0

    /// Jump all linked scrolls to the timeline start (current hour).
    func resetToStart() {
        apply(0, excluding: nil)
    }

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
        // Align newly visible rows to shared offset (0 on first open = current hour).
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
