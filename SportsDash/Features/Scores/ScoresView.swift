import SwiftUI

struct ScoresView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedGame: Game?
    /// Collapsed sport section keys (`soccer`, `baseball`, …) — same idea as `LiveScoresStrip`.
    @State private var collapsedSports: Set<String> = []
    @State private var showLeaguesSettings = false
    @State private var showFavoritePicker = false

    var body: some View {
        NavigationStack {
            scoresRoot
                .sportsScreenBackground()
                #if os(iOS)
                .navigationTitle("")
                .sportsNavTitleMode(large: false)
                .toolbarBackground(.hidden, for: .navigationBar)
                .jumbotronAXCap()
                #else
                .navigationTitle("Scores")
                #endif
                .toolbar {
                    #if os(tvOS)
                    ToolbarItemGroup(placement: .primaryAction) {
                        SportsTVIconButton(
                            systemName: "star",
                            accessibilityLabelText: "Favorite teams"
                        ) {
                            showFavoritePicker = true
                        }
                        if appModel.isLoadingScores {
                            ProgressView().controlSize(.small).tint(SportsColors.gold)
                        } else {
                            SportsTVIconButton(
                                systemName: "arrow.clockwise",
                                accessibilityLabelText: "Refresh"
                            ) {
                                Task { await appModel.refreshScores() }
                            }
                            .disabled(appModel.isLoadingScores)
                        }
                    }
                    #else
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await appModel.refreshScores() }
                        } label: {
                            if appModel.isLoadingScores {
                                ProgressView().controlSize(.small).tint(SportsColors.gold)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(appModel.isLoadingScores)
                        .tint(SportsColors.gold)
                    }
                    #endif
                }
                .sheet(item: $selectedGame) { game in
                    GameDetailSheet(game: game)
                        .environmentObject(appModel)
                        .environmentObject(appModel.epg)
                        .sportsSheetChrome()
                }
                .sportsLargeCover(isPresented: $showFavoritePicker) {
                    FavoriteTeamPickerView()
                        .environmentObject(appModel)
                        .environmentObject(appModel.epg)
                        .sportsSheetChrome()
                }
                #if os(iOS)
                .navigationDestination(isPresented: $showLeaguesSettings) {
                    ScoresSettingsView()
                }
                #endif
        }
    }

    /// Filters + context strip stay pinned under nav while body scrolls (S-UX.P1.1).
    private var scoresRoot: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            jumbotronScoresChrome
            #else
            VStack(spacing: 0) {
                filterBar
                scoresContextStrip
            }
            .background(SportsColors.voidBlack.opacity(0.92))
            #endif
            scoresBody
        }
    }

    #if os(iOS)
    private var jumbotronScoresChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                JumbotronScreenTitle(first: "SCORE", gold: "BOARD")
                Spacer(minLength: 8)
                Circle()
                    .fill(SportsColors.live)
                    .frame(width: 8, height: 8)
                    .shadow(color: SportsColors.liveGlow, radius: 4)
                    .opacity(appModel.isLoadingScores ? blinkOpacity : 1)
                    .animation(
                        appModel.isLoadingScores
                            ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                            : .default,
                        value: appModel.isLoadingScores
                    )
                    .accessibilityHidden(true)
            }
            JumbotronSwitchboard(
                filter: $appModel.dashboardFilter,
                favoriteTeams: appModel.favoriteTeamsRail,
                onFavorites: { showFavoritePicker = true }
            )
            if let warning = appModel.scoresWarning, appModel.scoresError == nil {
                HStack(spacing: 8) {
                    Rectangle().fill(SportsColors.danger).frame(width: 4, height: 12)
                    Text(warning)
                        .font(JumbotronFonts.body(10))
                        .foregroundStyle(SportsColors.danger)
                        .lineLimit(2)
                }
                .accessibilityLabel("Scores warning: \(warning)")
            }
        }
        .padding(.horizontal, SportsMetrics.screenInset)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var blinkOpacity: Double { 0.25 }
    #endif

    @ViewBuilder
    private var scoresBody: some View {
        if appModel.isLoadingScores && appModel.games.isEmpty {
            #if os(iOS)
            VStack(spacing: 12) {
                if SetupChecklist.needsPlaylist(appModel) {
                    SetupChecklistCard()
                }
                JumbotronSkeletonPanel()
                JumbotronSkeletonPanel()
                JumbotronSkeletonPanel()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SportsMetrics.screenInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            VStack(spacing: 16) {
                if SetupChecklist.isIncomplete(appModel) {
                    SetupChecklistCard()
                        .padding(.horizontal, 10)
                }
                Spacer(minLength: 12)
                ProgressView()
                    .tint(SportsColors.gold)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        } else if let err = appModel.scoresError, appModel.games.isEmpty {
            ScrollView {
                VStack(spacing: 12) {
                    if SetupChecklist.needsPlaylist(appModel) {
                        SetupChecklistCard()
                    }
                    #if os(iOS)
                    JumbotronMessagePanel(
                        tick: SportsColors.danger,
                        title: "SCORES UNAVAILABLE",
                        subtitle: err,
                        cta: "RETRY",
                        action: { Task { await appModel.refreshScores() } }
                    )
                    #else
                    ContentUnavailableView(
                        "Scores unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(err)
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                    #endif
                }
                .padding(.horizontal, SportsMetrics.screenInset)
                .padding(.vertical, 6)
            }
            .sportsRefreshable { await appModel.refreshScores() }
        } else {
            scoresContent
        }
    }

    private var scoresContent: some View {
        // Android UI A parity: favorite logo rail + My Games pin, then collapsible sports.
        // Starred-team games also pin first inside league shelves (FAV.2).
        let pin = appModel.myGamesPin
        let pinIds = Set(pin.map(\.id))
        let boardGames = appModel.filteredGames.filter { !pinIds.contains($0.id) }
        let sections: [SportScoreSection] = Self.buildSections(
            games: boardGames,
            filter: appModel.dashboardFilter,
            selectedLeagues: appModel.selectedLeagues,
            favoriteTeamIds: appModel.favoriteTeamIds
        )

        #if os(tvOS)
        return tvNetflixBrowse(pin: pin, sections: sections)
        #else
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                #if os(tvOS)
                if let warning = appModel.scoresWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                        .padding(.horizontal, 10)
                        .accessibilityLabel("Scores warning: \(warning)")
                }
                #endif

                if SetupChecklist.needsPlaylist(appModel) {
                    SetupChecklistCard()
                        .padding(.horizontal, SportsMetrics.screenInset)
                }

                #if os(iOS)
                if let hero = pin.first {
                    JumbotronHeroBoard(
                        game: hero,
                        isAwayFavorite: appModel.isTeamFavorite(hero.away.id),
                        isHomeFavorite: appModel.isTeamFavorite(hero.home.id),
                        matchCount: appModel.matches(for: hero).count,
                        onSelect: { selectedGame = hero },
                        onWatch: { selectedGame = hero }
                    )
                    .padding(.horizontal, SportsMetrics.screenInset)
                    ForEach(pin.dropFirst()) { game in
                        scoreRow(game)
                            .padding(.horizontal, SportsMetrics.screenInset)
                    }
                }
                #else
                if !pin.isEmpty {
                    myGamesSection(pin)
                }
                #endif

                if sections.isEmpty && pin.isEmpty {
                    #if os(iOS)
                    JumbotronMessagePanel(
                        title: emptyTitle.uppercased(),
                        subtitle: emptySubtitle,
                        cta: emptyCTA,
                        action: emptyCTAAction
                    )
                    .padding(.horizontal, SportsMetrics.screenInset)
                    #else
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "sportscourt",
                        description: Text(emptySubtitle)
                    )
                    .frame(maxWidth: .infinity, minHeight: SetupChecklist.isIncomplete(appModel) ? 180 : 280)
                    #endif
                } else {
                    ForEach(sections) { section in
                        sportSectionBlock(section)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.bottom, 28)
            .background(Color.clear)
        }
        .sportsHideScrollBackground()
        .background(Color.clear)
        .sportsRefreshable { await appModel.refreshScores() }
        #endif
    }

    #if os(tvOS)
    /// Netflix-style horizontal card rails for Apple TV.
    private func tvNetflixBrowse(pin: [Game], sections: [SportScoreSection]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 36) {
                if let warning = appModel.scoresWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                        .padding(.horizontal, 48)
                        .accessibilityLabel("Scores warning: \(warning)")
                }

                if SetupChecklist.isIncomplete(appModel) {
                    SetupChecklistCard()
                        .padding(.horizontal, 48)
                        .padding(.top, 8)
                }

                if pin.isEmpty && sections.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "sportscourt",
                        description: Text(emptySubtitle)
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .padding(.horizontal, 48)
                } else {
                    if !pin.isEmpty {
                        ScoresTVRail(
                            title: "My Games",
                            emoji: "⭐",
                            games: pin,
                            favoriteTeamIds: appModel.favoriteTeamIds,
                            onSelect: { selectedGame = $0 }
                        )
                        .focusSection()
                    }
                    let rails = ScoreboardGrouping.tvScoreRails(sections: sections)
                    ForEach(rails, id: \.key) { rail in
                        ScoresTVRail(
                            title: rail.title,  // per-league (not sportTitle) for Upcoming empty rails
                            emoji: rail.emoji,
                            games: rail.games,
                            favoriteTeamIds: appModel.favoriteTeamIds,
                            onSelect: { selectedGame = $0 }
                        )
                        .focusSection()
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.bottom, 60)
        }
        .sportsHideScrollBackground()
        .background(SportsColors.voidBlack)
    }
    #endif

    #if os(iOS)
    private var favoriteTeamsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appModel.favoriteTeamsRail) { team in
                    Button {
                        showFavoritePicker = true
                    } label: {
                        railLogo(team)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(team.name)
                }
                Button {
                    showFavoritePicker = true
                } label: {
                    Text("+")
                        .font(.body.weight(.bold))
                        .foregroundStyle(SportsColors.muted)
                        .frame(width: 30, height: 30)
                        .background(SportsColors.panel, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add favorite team")
            }
            .padding(.leading, 4)
        }
    }

    private func railLogo(_ team: TeamInfo) -> some View {
        Group {
            if let raw = team.logoURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                    default:
                        Text(String(team.abbreviation.prefix(2)))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SportsColors.gold)
                    }
                }
            } else {
                Text(String(team.abbreviation.prefix(2)))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SportsColors.gold)
            }
        }
        .frame(width: 26, height: 26)
        .padding(2)
        .background(SportsColors.panel, in: Circle())
    }
    #endif

    /// Shared iOS + tvOS — must not sit under `#if os(iOS)` (SportsDashTV compile break after 1.2.0 pin path).
    private func myGamesSection(_ games: [Game]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(SportsColors.gold)
                    .font(.caption.weight(.bold))
                Text("My Games")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SportsColors.gold)
                let live = games.filter(\.isLive).count
                if live > 0 {
                    Text("\(live) Live")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SportsColors.live)
                }
                #if os(tvOS)
                Spacer(minLength: 8)
                Button {
                    showFavoritePicker = true
                } label: {
                    SportsTVFocused { focused in
                        HStack(spacing: 6) {
                            Image(systemName: "star")
                                .font(.caption.weight(.bold))
                            Text("Edit favorites")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: SportsTVMetrics.minFocusSize * 0.72)
                        .background {
                            Capsule(style: .continuous)
                                .fill(focused ? SportsColors.gold : SportsColors.panelElevated)
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(focused ? SportsColors.goldDim : SportsColors.border.opacity(0.4), lineWidth: focused ? 2 : 1)
                        }
                        .scaleEffect(focused ? SportsTVMetrics.chipFocusScale : 1.0)
                        .animation(SportsTVFocusMotion.animation, value: focused)
                    }
                }
                .sportsTVFocusClean()
                .accessibilityLabel("Edit favorite teams")
                #endif
            }
            .padding(.horizontal, 10)

            VStack(spacing: 10) {
                ForEach(games) { game in
                    GameScoreFocusRow(
                        game: game,
                        isFavorite: appModel.isFavorite(game),
                        isAwayFavorite: appModel.isTeamFavorite(game.away.id),
                        isHomeFavorite: appModel.isTeamFavorite(game.home.id),
                        onSelect: { selectedGame = game },
                        onToggleAwayFavorite: { appModel.toggleFavorite(team: game.away) },
                        onToggleHomeFavorite: { appModel.toggleFavorite(team: game.home) }
                    )
                }
            }
            #if os(tvOS)
            .frame(maxWidth: SportsTVMetrics.scoreCardMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SportsTVMetrics.scoreHorizontalInset)
            .focusSection()
            #else
            .padding(.horizontal, 10)
            #endif
        }
    }

    /// Always-visible: leagues (truncated) · Updated time + Edit leagues (S-UX.P0.2).
    private var scoresContextStrip: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(contextSummaryLine)
                .font(.caption.weight(.medium))
                .foregroundStyle(SportsColors.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(contextSummaryLine)

            #if os(iOS)
            Button {
                showLeaguesSettings = true
            } label: {
                editLeaguesChip(focused: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit leagues")
            .accessibilityHint("Opens Scores and leagues settings")
            #else
            NavigationLink {
                ScoresSettingsView()
            } label: {
                SportsTVFocused { focused in
                    editLeaguesChip(focused: focused)
                }
            }
            .sportsTVFocusClean()
            .accessibilityLabel("Edit leagues")
            .accessibilityHint("Opens Scores and leagues settings")
            #endif
        }
        .padding(.horizontal, horizontalChromeInset)
        .padding(.top, 2)
        .padding(.bottom, 10)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func editLeaguesChip(focused: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "slider.horizontal.3")
                .font(.caption.weight(.bold))
            Text("Edit leagues")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        #if os(iOS)
        .background {
            Capsule(style: .continuous)
                .fill(.clear)
                .sportsGlass(in: Capsule(style: .continuous))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(SportsColors.gold.opacity(0.35), lineWidth: 1)
        }
        #else
        .frame(minHeight: SportsTVMetrics.minFocusSize * 0.72)
        .background {
            Capsule(style: .continuous)
                .fill(focused ? SportsColors.gold : SportsColors.panelElevated)
        }
        .overlay {
            if focused {
                Capsule(style: .continuous)
                    .stroke(SportsColors.goldDim, lineWidth: 2)
            }
        }
        .scaleEffect(focused ? SportsTVMetrics.chipFocusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        #endif
    }

    private var horizontalChromeInset: CGFloat {
        #if os(tvOS)
        32
        #else
        16
        #endif
    }

    /// Effective leagues driving the scoreboard (defaults when unset).
    private var activeLeagues: [SportLeague] {
        appModel.selectedLeagues.isEmpty ? SportLeague.defaults : appModel.selectedLeagues
    }

    /// e.g. "World Cup, Champions League, Premier League +4 · Updated 3:42 PM"
    private var contextSummaryLine: String {
        "\(leaguesSummaryText) · \(updatedSummaryText)"
    }

    private var leaguesSummaryText: String {
        let leagues = activeLeagues
        guard !leagues.isEmpty else { return "No leagues selected" }
        let labels = leagues.map(\.label)
        let head = labels.prefix(3).joined(separator: ", ")
        if labels.count > 3 {
            return "\(head) +\(labels.count - 3)"
        }
        return head
    }

    private var updatedSummaryText: String {
        if appModel.isLoadingScores && appModel.lastUpdated == nil {
            return "Updating…"
        }
        if let updated = appModel.lastUpdated {
            let time = updated.formatted(date: .omitted, time: .shortened)
            if appModel.isLoadingScores {
                return "Updating… · last \(time)"
            }
            return "Updated \(time)"
        }
        return "Not updated yet"
    }

    /// Group games by sport → league; on Upcoming, keep empty shelves for selected
    /// leagues so MLB (etc.) never "disappears" when the slate is quiet.
    private static func buildSections(
        games: [Game],
        filter: DashboardFilter,
        selectedLeagues: [SportLeague],
        favoriteTeamIds: Set<String> = []
    ) -> [SportScoreSection] {
        var sections = ScoreboardGrouping.sportSections(from: games, favoriteTeamIds: favoriteTeamIds)
        guard filter == .upcoming else { return sections }

        let selected = selectedLeagues.isEmpty ? SportLeague.defaults : selectedLeagues
        let present = Set(sections.flatMap { $0.leagues.map(\.key) })
        let missing = selected.filter { !present.contains($0.rawValue) }
        guard !missing.isEmpty else { return sections }

        // Attach empty league shelves under the right sport bucket.
        for league in ScoreboardGrouping.leagueOrder where missing.contains(league) {
            let emptyShelf = LeagueShelf(
                key: league.rawValue,
                title: league.label,
                sportKey: league.sportPath,
                sportTitle: league.sportSectionTitle,
                showSportHeader: true,
                games: []
            )
            if let idx = sections.firstIndex(where: { $0.sportKey == league.sportPath }) {
                if !sections[idx].leagues.contains(where: { $0.key == league.rawValue }) {
                    sections[idx].leagues.append(emptyShelf)
                }
            } else {
                sections.append(
                    SportScoreSection(
                        sportKey: league.sportPath,
                        sportTitle: league.sportSectionTitle,
                        emoji: league.emoji,
                        leagues: [emptyShelf]
                    )
                )
            }
        }
        // Keep sport order stable (first appearance in leagueOrder).
        let sportOrder = ScoreboardGrouping.leagueOrder.map(\.sportPath)
        sections.sort { a, b in
            let ia = sportOrder.firstIndex(of: a.sportKey) ?? 999
            let ib = sportOrder.firstIndex(of: b.sportKey) ?? 999
            return ia < ib
        }
        return sections
    }

    // MARK: - Sport → league hierarchy (collapsible sports)

    @ViewBuilder
    private func sportSectionBlock(_ section: SportScoreSection) -> some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(section.leagues) { shelf in
                leagueBlock(
                    title: shelf.title,
                    systemImage: nil,
                    goldTitle: false,
                    games: shelf.games
                )
            }
        }
        #else
        let collapsed = collapsedSports.contains(section.sportKey)
        VStack(alignment: .leading, spacing: collapsed ? 0 : 16) {
            sportHeader(section, collapsed: collapsed)
            if !collapsed {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(section.leagues) { shelf in
                        leagueBlock(
                            title: shelf.title,
                            systemImage: nil,
                            goldTitle: false,
                            games: shelf.games
                        )
                    }
                }
            }
        }
        #endif
    }

    private func sportHeader(_ section: SportScoreSection, collapsed: Bool) -> some View {
        let gameCount = section.leagues.reduce(0) { $0 + $1.games.count }
        let liveCount = section.leagues.reduce(0) { $0 + $1.games.filter(\.isLive).count }

        return Button {
            toggleSport(section.sportKey)
        } label: {
            #if os(tvOS)
            SportsTVFocused { focused in
                sportHeaderLabel(section, collapsed: collapsed, liveCount: liveCount, gameCount: gameCount, focused: focused)
            }
            #else
            sportHeaderLabel(section, collapsed: collapsed, liveCount: liveCount, gameCount: gameCount, focused: false)
            #endif
        }
        #if os(tvOS)
        .sportsTVFocusClean()
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(section.sportTitle), \(gameCount) games")
        .accessibilityHint(collapsed ? "Expand sport" : "Collapse sport")
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func sportHeaderLabel(
        _ section: SportScoreSection,
        collapsed: Bool,
        liveCount: Int,
        gameCount: Int,
        focused: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(section.emoji)
                .font(.title2)
            Text(section.sportTitle)
                .font(.title2.weight(.heavy))
                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if liveCount > 0 {
                Text("\(liveCount) Live")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.75) : SportsColors.live)
            }
            Text("\(gameCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.7) : SportsColors.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((focused ? SportsColors.voidBlack.opacity(0.12) : SportsColors.panelElevated.opacity(0.95)))
                .clipShape(Capsule())
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(focused ? SportsColors.voidBlack.opacity(0.7) : SportsColors.gold)
                .frame(width: 24, height: 24)
                .background(
                    (focused ? SportsColors.voidBlack.opacity(0.12) : SportsColors.gold.opacity(0.18)),
                    in: Circle()
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        #if os(iOS)
        // Transparent — no gray band behind sport headers / game list
        .background(Color.clear)
        .padding(.horizontal, 10)
        #endif
        #if os(tvOS)
        .frame(minHeight: SportsTVMetrics.minFocusSize)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(focused ? SportsColors.gold : Color.clear)
        }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SportsColors.goldDim, lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        .padding(.horizontal, SportsTVMetrics.scoreHorizontalInset - 16)
        #endif
        .contentShape(Rectangle())
    }

    private func toggleSport(_ key: String) {
        #if os(iOS)
        withAnimation(.snappy(duration: 0.22)) {
            if collapsedSports.contains(key) {
                collapsedSports.remove(key)
            } else {
                collapsedSports.insert(key)
            }
        }
        #else
        if collapsedSports.contains(key) {
            collapsedSports.remove(key)
        } else {
            collapsedSports.insert(key)
        }
        #endif
    }

    private var filterBar: some View {
        #if os(tvOS)
        // No horizontal ScrollView — plain chips inside ScrollView often can't take focus on tvOS.
        HStack(spacing: 16) {
            ForEach(DashboardFilter.allCases) { f in
                let liveCount = appModel.games.filter(\.isLive).count
                let upcomingCount = appModel.games.filter(\.isUpcoming).count
                SportsFilterChip(
                    title: f.label,
                    count: f == .live ? liveCount : (f == .upcoming ? upcomingCount : nil),
                    selected: appModel.dashboardFilter == f
                ) {
                    appModel.dashboardFilter = f
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 6)
        .focusSection()
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DashboardFilter.allCases) { f in
                    let liveCount = appModel.games.filter(\.isLive).count
                    let upcomingCount = appModel.games.filter(\.isUpcoming).count
                    SportsFilterChip(
                        title: f.label,
                        count: f == .live ? liveCount : (f == .upcoming ? upcomingCount : nil),
                        selected: appModel.dashboardFilter == f
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            appModel.dashboardFilter = f
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        #endif
    }

    /// Borderless grouped list — soft surface, hairline dividers only (no per-card boxes).
    private func leagueBlock(
        title: String,
        systemImage: String?,
        goldTitle: Bool,
        games: [Game]
    ) -> some View {
        let live = games.filter(\.isLive).count
        let league = SportLeague.allCases.first { $0.label == title }
        return VStack(alignment: .leading, spacing: 6) {
            #if os(iOS)
            JumbotronLeagueHeader(
                title: title,
                tick: league?.jumbotronTick ?? SportsColors.gold,
                liveCount: live,
                upcomingCount: games.filter(\.isUpcoming).count,
                finalCount: games.filter(\.isFinal).count,
                filter: appModel.dashboardFilter
            )
            .padding(.horizontal, SportsMetrics.screenInset)
            #else
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SportsColors.gold)
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(goldTitle ? SportsColors.gold : SportsColors.muted)
                    .textCase(goldTitle ? nil : .uppercase)
                    .tracking(goldTitle ? 0 : 0.6)
                Spacer()
                if live > 0 {
                    Text("\(live) Live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SportsColors.live)
                } else if games.isEmpty {
                    Text("None scheduled")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SportsColors.muted)
                } else {
                    Text("\(games.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SportsColors.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .padding(.top, 2)
            #endif

            if games.isEmpty {
                Text("No upcoming games in the next week for this league.")
                    .font(JumbotronFonts.body(11))
                    .foregroundStyle(SportsColors.muted)
                    .padding(.horizontal, SportsMetrics.screenInset)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 6) {
                    ForEach(games) { game in
                        scoreRow(game)
                    }
                }
                #if os(tvOS)
                .frame(maxWidth: SportsTVMetrics.scoreCardMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SportsTVMetrics.scoreHorizontalInset)
                .focusSection()
                #else
                .background(Color.clear)
                .padding(.horizontal, SportsMetrics.screenInset)
                #endif
            }
        }
    }

    private func scoreRow(_ game: Game) -> some View {
        GameScoreFocusRow(
            game: game,
            isFavorite: appModel.isFavorite(game),
            isAwayFavorite: appModel.isTeamFavorite(game.away.id),
            isHomeFavorite: appModel.isTeamFavorite(game.home.id),
            hasMatch: !appModel.matches(for: game).isEmpty,
            onSelect: { selectedGame = game },
            onToggleAwayFavorite: { appModel.toggleFavorite(teamId: game.away.id) },
            onToggleHomeFavorite: { appModel.toggleFavorite(teamId: game.home.id) }
        )
    }

    private var emptyTitle: String {
        switch appModel.dashboardFilter {
        case .live: return "No live games"
        case .upcoming: return "No upcoming games"
        case .final: return "No final games"
        }
    }

    private var emptySubtitle: String {
        switch appModel.dashboardFilter {
        case .upcoming:
            let leagues = appModel.selectedLeagues.isEmpty
                ? SportLeague.defaults
                : appModel.selectedLeagues
            let labels = leagues.prefix(4).map(\.label).joined(separator: ", ")
            let more = leagues.count > 4 ? " +\(leagues.count - 4) more" : ""
            return "No scheduled games in the next few days for \(labels)\(more). Pull to refresh or adjust leagues in Settings."
        case .live:
            return "Nothing in progress right now. Check Upcoming or pull to refresh. Star a team on a matchup to pin their games first."
        case .final:
            return "No completed games in the current slate. Check Live or Upcoming, or pull to refresh."
        }
    }

    private var emptyCTA: String {
        switch appModel.dashboardFilter {
        case .live: return "UPCOMING ▸"
        case .upcoming: return "LEAGUES ▸"
        case .final: return "LIVE ▸"
        }
    }

    private var emptyCTAAction: () -> Void {
        {
            switch appModel.dashboardFilter {
            case .live:
                withAnimation(.easeOut(duration: 0.15)) { appModel.dashboardFilter = .upcoming }
            case .upcoming:
                showLeaguesSettings = true
            case .final:
                withAnimation(.easeOut(duration: 0.15)) { appModel.dashboardFilter = .live }
            }
        }
    }
}

// MARK: - Grouping models

struct LeagueShelf: Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var sportKey: String
    var sportTitle: String
    var showSportHeader: Bool
    var games: [Game]
}

/// Sport bucket used by Scores dashboard collapse (and shared strip grouping).
struct SportScoreSection: Identifiable {
    var id: String { sportKey }
    let sportKey: String
    let sportTitle: String
    let emoji: String
    var leagues: [LeagueShelf]
}

enum ScoreboardGrouping {
    static let leagueOrder: [SportLeague] = SportLeague.allCases

    /// Nonisolated so scoreboard grouping can run off MainActor.
    static func pinFavoriteGames(_ games: [Game], favoriteTeamIds: Set<String>) -> [Game] {
        guard !favoriteTeamIds.isEmpty else {
            return games.sorted {
                if $0.isLive != $1.isLive { return $0.isLive && !$1.isLive }
                return $0.startTime < $1.startTime
            }
        }
        return games.sorted { a, b in
            let aFav = favoriteTeamIds.contains(a.home.id) || favoriteTeamIds.contains(a.away.id)
            let bFav = favoriteTeamIds.contains(b.home.id) || favoriteTeamIds.contains(b.away.id)
            if aFav != bFav { return aFav && !bFav }
            if a.isLive != b.isLive { return a.isLive && !b.isLive }
            return a.startTime < b.startTime
        }
    }

    static func leagueShelves(from games: [Game], favoriteTeamIds: Set<String> = []) -> [LeagueShelf] {
        var buckets: [SportLeague: [Game]] = [:]
        for g in games {
            buckets[g.league, default: []].append(g)
        }
        for k in buckets.keys {
            // S-PARITY.FAV.2: within each league, favorite-team games pin first.
            buckets[k] = pinFavoriteGames(buckets[k] ?? [], favoriteTeamIds: favoriteTeamIds)
        }
        var shelves: [LeagueShelf] = []
        var lastSport: String?
        for league in leagueOrder {
            guard let list = buckets[league], !list.isEmpty else { continue }
            let sport = league.sportPath
            let showHeader = sport != lastSport
            lastSport = sport
            shelves.append(
                LeagueShelf(
                    key: league.rawValue,
                    title: league.label,
                    sportKey: sport,
                    sportTitle: league.sportSectionTitle,
                    showSportHeader: showHeader,
                    games: list
                )
            )
        }
        return shelves
    }

    /// Collapse consecutive league shelves into sport → league sections.
    static func sportSections(from games: [Game], favoriteTeamIds: Set<String> = []) -> [SportScoreSection] {
        let shelves = leagueShelves(from: games, favoriteTeamIds: favoriteTeamIds)
        var sections: [SportScoreSection] = []
        var current: SportScoreSection?
        for shelf in shelves {
            if current?.sportKey != shelf.sportKey {
                if let current { sections.append(current) }
                current = SportScoreSection(
                    sportKey: shelf.sportKey,
                    sportTitle: shelf.sportTitle,
                    emoji: shelf.games.first?.league.emoji ?? "🏟️",
                    leagues: [shelf]
                )
            } else {
                current?.leagues.append(shelf)
            }
        }
        if let current { sections.append(current) }
        return sections
    }

    /// Pure transformation extracted for TV Netflix browse (parity with Android tvScoreRails).
    /// Returns league-level rails (title=league.label) so Upcoming renders per-league
    /// including empty selected leagues (which will render "None scheduled" inside rail).
    /// Live/Final avoid empty because buildSections omits empty shelves for those filters.
    /// My Games is handled separately and remains first.
    static func tvScoreRails(sections: [SportScoreSection]) -> [(key: String, title: String, emoji: String, games: [Game])] {
        return sections.flatMap { section in
            section.leagues.map { shelf in
                (
                    key: "rail-\(section.sportKey)-\(shelf.key)",
                    title: shelf.title,
                    emoji: section.emoji,
                    games: shelf.games
                )
            }
        }
    }
}
