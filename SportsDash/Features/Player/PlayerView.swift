import SwiftUI

/// Fullscreen IPTV player with UHF-style chrome: channel/EPG info, pause, PiP, captions, scores.
struct PlayerView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var channel: IptvChannel
    @State private var game: Game?
    @State private var alternates: [ChannelMatch]
    @StateObject private var playback = PlaybackController()
    @State private var showChrome = true
    @State private var showScoresStrip = true
    @State private var showStreamSheet = false
    @State private var showGamePicker: Game?
    @State private var showMoreMenu = false
    @State private var chromeTask: Task<Void, Never>?
    /// When true, dismissing full-screen hands off to the floating mini player (don't stop audio).
    @State private var isPoppingOut = false

    init(channel: IptvChannel, game: Game?, alternateMatches: [ChannelMatch] = []) {
        _channel = State(initialValue: channel)
        _game = State(initialValue: game)
        _alternates = State(initialValue: alternateMatches)
    }

    private var currentProgram: EpgProgram? {
        let programs = appModel.epgByChannel[channel.id] ?? []
        return programs.first(where: \.isNow) ?? programs.first
    }

    private var nextProgram: EpgProgram? {
        guard let now = currentProgram else { return nil }
        let programs = appModel.epgByChannel[channel.id] ?? []
        return programs.first { $0.start >= now.end }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurface(playback: playback)
                .ignoresSafeArea()
                .onTapGesture { toggleChrome() }

            if (playback.isLoading || playback.isBuffering) && !playback.isPlaying {
                loadingOverlay
                    .allowsHitTesting(false)
            }

            if let err = playback.error {
                errorOverlay(err)
            }

            // Android D parity: exit + optional ticker at TOP; info chrome mid/bottom.
            VStack(spacing: 0) {
                // Always-on exit row (even when chrome auto-hides)
                alwaysOnExitBar

                if showScoresStrip, playback.error == nil {
                    LiveScoresStrip(
                        games: appModel.games.filter(\.isLive),
                        currentGameId: game?.id,
                        favoriteTeamIds: appModel.favoriteTeamIds,
                        lastPlayedGameIds: appModel.lastPlayedGameIds,
                        compactTopStyle: true,
                        onGameTap: { g in
                            Task {
                                let chans = appModel.channels
                                let m = await Task.detached(priority: .userInitiated) {
                                    MatchingService().matchGameToChannels(g, channels: chans)
                                }.value
                                if m.isEmpty {
                                    playback.banner = "No streams matched for \(g.matchupLabel)"
                                } else {
                                    showGamePicker = g
                                }
                            }
                        }
                    )
                }

                if showChrome {
                    topChrome
                }
                Spacer(minLength: 0)
                if showChrome {
                    bottomInfoChrome
                }
            }
            .allowsHitTesting(true)
        }
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        .onAppear {
            playback.configure(prefs: appModel.playerPrefs)
            applyAspect()
            playback.start(url: channel.url)
            if let id = game?.id { appModel.recordLastPlayed(gameId: id) }
            if appModel.xtreamAccount == nil {
                Task { await appModel.refreshXtreamAccount() }
            }
            scheduleChromeHide()
        }
        .onDisappear {
            chromeTask?.cancel()
            // Keep decoding only if we handed off to the floating pop-out player.
            if !isPoppingOut {
                playback.stop()
            }
        }
        .onChange(of: appModel.playerPrefs) { _, prefs in
            playback.configure(prefs: prefs)
            applyAspect()
        }
        .sheet(isPresented: $showStreamSheet) {
            streamSheet(matches: streamOptions)
        }
        .sheet(item: $showGamePicker) { g in
            streamSheet(
                matches: MatchingService().matchGameToChannels(g, channels: appModel.channels),
                forGame: g
            )
        }
        .confirmationDialog("Player options", isPresented: $showMoreMenu, titleVisibility: .visible) {
            Button("Cycle aspect (\(appModel.playerPrefs.aspect.label))") { cycleAspect() }
            Button("Jump to LIVE") { playback.jumpToLive() }
            Button("Pop out player") { popOutToFloatingPlayer() }
            Button("System Picture in Picture") { playback.togglePictureInPicture() }
            Button("Alternate streams") { showStreamSheet = true }
            Button("Cycle subtitles") { playback.cycleSubtitleTrack() }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .top) {
            if let banner = playback.banner {
                Text(banner)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SportsColors.gold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .sportsGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 72)
                    .allowsHitTesting(false)
            }
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(SportsColors.gold)
            Text(playback.isLoading ? "Starting stream…" : "Buffering…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            if !playback.engineLabel.isEmpty {
                Text(playback.engineLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    // MARK: - Chrome
    // Liquid Glass on floating controls only — never glass-fill the video surface.
    // https://developer.apple.com/design/human-interface-guidelines/materials

    /// Always visible exit (Android player exit parity).
    private var alwaysOnExitBar: some View {
        HStack(spacing: 10) {
            chromeIconButton(systemName: "chevron.left") { dismiss() }
            Spacer(minLength: 0)
            if showChrome {
                chromeIconButton(systemName: "xmark") { dismiss() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                Text(engineChip)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .sportsGlass(in: Capsule(style: .continuous))

                chromeIconButton(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    playback.toggleMute()
                    scheduleChromeHide()
                }

                chromeIconButton(systemName: "aspectratio") {
                    cycleAspect()
                    scheduleChromeHide()
                }

                chromeIconButton(systemName: "ellipsis") {
                    showMoreMenu = true
                }
            }

            // Transport + utilities stay at the top so the scores ticker never covers them.
            HStack(spacing: 10) {
                Button {
                    playback.togglePlayPause()
                    scheduleChromeHide()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .sportsGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                HStack(spacing: 6) {
                    utilityButton(systemName: "dot.radiowaves.left.and.right", tint: SportsColors.live) {
                        playback.jumpToLive()
                        scheduleChromeHide()
                    }
                    // UHF-style pop-out: floating mini player over the app (not system PiP).
                    utilityButton(
                        systemName: "rectangle.inset.filled.and.person.filled",
                        tint: .white
                    ) {
                        popOutToFloatingPlayer()
                    }
                    #if os(iOS)
                    // System AirPlay / external display route picker.
                    // Note: VLC AirPlay is often audio-focused; AVKit can mirror video better.
                    AirPlayRoutePicker()
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("AirPlay")
                        .accessibilityHint("Video AirPlay works best with AVKit player in Settings")
                    #endif
                    utilityButton(systemName: "captions.bubble", tint: .white) {
                        playback.cycleSubtitleTrack()
                        scheduleChromeHide()
                    }
                    utilityButton(
                        systemName: showScoresStrip ? "sportscourt.fill" : "sportscourt",
                        tint: showScoresStrip ? SportsColors.gold : .white
                    ) {
                        showScoresStrip.toggle()
                        scheduleChromeHide()
                    }
                    utilityButton(systemName: "list.bullet", tint: SportsColors.gold) {
                        showStreamSheet = true
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .sportsGlass(in: Capsule(style: .continuous))

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        // Soft scrim for legibility only — not Liquid Glass over the video.
        .background(
            LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    /// Channel + EPG only — sits above the scores ticker.
    private var bottomInfoChrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let group = channel.group, !group.isEmpty {
                Text(group.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SportsColors.gold)
            }

            Text(ChannelNameCleanup.displayName(channel.name, enabled: appModel.playerPrefs.cleanUpNames))
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            if let prog = currentProgram {
                Text(prog.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
                Text(prog.timeRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                MovieRatingLoader(
                    title: prog.title,
                    categories: prog.categories,
                    channelGroup: channel.group,
                    channelName: channel.name,
                    compact: false
                )
                .padding(.top, 2)
            } else if let g = game {
                Text(g.matchupLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }

            if let next = nextProgram {
                Text("Next: \(next.title)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                badge(appModel.activePlaylist?.name ?? "IPTV", color: SportsColors.gold.opacity(0.85))
                badge(engineChip, color: .white.opacity(0.25))
                if playback.isPlaying {
                    badge("LIVE", color: SportsColors.live.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, showScoresStrip ? 10 : 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Content-layer scrim (opaque gradient) — not glass over video/info.
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.45), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var engineChip: String {
        let label = playback.engineLabel
        if label.localizedCaseInsensitiveContains("VLC") { return "VLC" }
        if label.localizedCaseInsensitiveContains("Auto") {
            return "Auto/\(playback.detectedContainer.shortLabel)"
        }
        if label.localizedCaseInsensitiveContains("AV") { return "AV" }
        return playback.activeBackend == .vlc ? "VLC" : "AV"
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule(style: .continuous))
    }

    /// Circular floating control — Liquid Glass on iOS 26+, material fallback earlier.
    private func chromeIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .sportsGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    private func utilityButton(systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Errors / streams

    private var streamOptions: [ChannelMatch] {
        var opts = [ChannelMatch(channel: channel, score: 100, reason: "Current")]
        opts.append(contentsOf: alternates.filter { $0.channel.id != channel.id })
        return opts
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(SportsColors.danger)
            Text("Playback failed")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(SportsColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            HStack {
                Button("Retry") { playback.start(url: channel.url) }
                    .buttonStyle(.borderedProminent)
                    .tint(SportsColors.gold)
                    .foregroundStyle(SportsColors.voidBlack)
                Button("Back") { dismiss() }
                    .buttonStyle(.bordered)
            }
            if appModel.playerPrefs.primaryPlayer != .auto {
                Button("Retry with Auto (TS→VLC · HLS→AV)") {
                    var prefs = appModel.playerPrefs
                    prefs.primaryPlayer = .auto
                    prefs.fallbackPlayers = true
                    appModel.setPlayerPrefs(prefs)
                    playback.configure(prefs: prefs)
                    playback.start(url: channel.url)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.gold)
            }
            if appModel.playerPrefs.primaryPlayer != .vlc {
                Button("Retry with VLC") {
                    var prefs = appModel.playerPrefs
                    prefs.primaryPlayer = .vlc
                    prefs.fallbackPlayers = true
                    appModel.setPlayerPrefs(prefs)
                    playback.configure(prefs: prefs)
                    playback.start(url: channel.url)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.gold)
            }
            if appModel.playerPrefs.primaryPlayer != .avKit {
                Button("Retry with AVKit") {
                    var prefs = appModel.playerPrefs
                    prefs.primaryPlayer = .avKit
                    prefs.fallbackPlayers = true
                    appModel.setPlayerPrefs(prefs)
                    playback.configure(prefs: prefs)
                    playback.start(url: channel.url)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.gold)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func streamSheet(matches: [ChannelMatch], forGame: Game? = nil) -> some View {
        NavigationStack {
            List {
                if let forGame {
                    Text(forGame.matchupLabel)
                        .font(.headline)
                        .listRowBackground(SportsColors.panel)
                }
                ForEach(matches) { m in
                    Button {
                        let g = forGame ?? game
                        switchTo(channel: m.channel, game: g, matches: matches)
                        showStreamSheet = false
                        showGamePicker = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ChannelNameCleanup.displayName(m.channel.name, enabled: appModel.playerPrefs.cleanUpNames))
                                    .foregroundStyle(SportsColors.text)
                                if let gr = m.channel.group {
                                    Text(gr).font(.caption).foregroundStyle(SportsColors.muted)
                                }
                            }
                            Spacer()
                            if m.channel.id == channel.id {
                                Text("NOW")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(SportsColors.gold)
                            }
                        }
                    }
                    .listRowBackground(SportsColors.panelElevated)
                }
            }
            .sportsHideScrollBackground()
            .background(SportsColors.panel)
            .navigationTitle("Streams")
            .sportsNavTitleMode(large: false)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showStreamSheet = false
                        showGamePicker = nil
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func switchTo(channel ch: IptvChannel, game g: Game?, matches: [ChannelMatch]) {
        channel = ch
        game = g
        alternates = matches.filter { $0.channel.id != ch.id }
        if let id = g?.id { appModel.recordLastPlayed(gameId: id) }
        applyAspect()
        playback.start(url: ch.url)
        showChrome = true
        scheduleChromeHide()
    }

    private func toggleChrome() {
        showChrome.toggle()
        if showChrome { scheduleChromeHide() }
    }

    private func scheduleChromeHide() {
        chromeTask?.cancel()
        chromeTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { showChrome = false }
            }
        }
    }

    private func cycleAspect() {
        let modes = PlayerAspectMode.allCases
        let i = modes.firstIndex(of: appModel.playerPrefs.aspect) ?? 0
        var prefs = appModel.playerPrefs
        prefs.aspect = modes[(i + 1) % modes.count]
        appModel.setPlayerPrefs(prefs)
        applyAspect()
        playback.banner = "Aspect: \(prefs.aspect.label)"
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { playback.banner = nil }
        }
    }

    private func applyAspect() {
        switch appModel.playerPrefs.aspect {
        case .fill, .stretch:
            playback.setAspectFill(true)
        case .auto, .fit, .ratio16x9, .ratio4x3:
            playback.setAspectFill(false)
        }
    }

    /// Leave fullscreen and show UHF-style floating player over tabs.
    private func popOutToFloatingPlayer() {
        isPoppingOut = true
        // Release fullscreen decoder; floating session starts its own player.
        playback.stop()
        appModel.popOutPlayer(channel: channel, game: game)
        dismiss()
    }
}
