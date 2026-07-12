import SwiftUI

/// Fullscreen IPTV player with multi-engine (KSPlayer FFmpeg / AVPlayer), LIVE jump, aspect, scores strip.
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
    @State private var chromeTask: Task<Void, Never>?

    init(channel: IptvChannel, game: Game?, alternateMatches: [ChannelMatch] = []) {
        _channel = State(initialValue: channel)
        _game = State(initialValue: game)
        _alternates = State(initialValue: alternateMatches)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            KSPlayerSurface(playback: playback)
                .ignoresSafeArea()
                .onTapGesture { toggleChrome() }

            if playback.isLoading || playback.isBuffering {
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

            if let err = playback.error {
                errorOverlay(err)
            }

            if showChrome {
                VStack {
                    topBar
                    Spacer()
                }
            }

            if showScoresStrip, playback.error == nil {
                VStack {
                    Spacer()
                    LiveScoresStrip(
                        games: appModel.games.filter(\.isLive),
                        currentGameId: game?.id,
                        favoriteTeamIds: appModel.favoriteTeamIds,
                        lastPlayedGameIds: appModel.lastPlayedGameIds,
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
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            let prefs = appModel.playerPrefs
            playback.configure(engine: prefs.engine, hardwareDecode: prefs.hardwareDecode)
            applyAspect()
            playback.start(url: channel.url)
            if let id = game?.id { appModel.recordLastPlayed(gameId: id) }
            scheduleChromeHide()
        }
        .onDisappear {
            playback.stop()
            chromeTask?.cancel()
        }
        .onChange(of: appModel.playerPrefs.aspect) { _, _ in
            applyAspect()
        }
        .onChange(of: appModel.playerPrefs.engine) { _, engine in
            playback.configure(engine: engine, hardwareDecode: appModel.playerPrefs.hardwareDecode)
            playback.start(url: channel.url)
        }
        .onChange(of: appModel.playerPrefs.hardwareDecode) { _, hw in
            playback.configure(engine: appModel.playerPrefs.engine, hardwareDecode: hw)
            playback.start(url: channel.url)
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
        .overlay(alignment: .bottom) {
            if let banner = playback.banner {
                Text(banner)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SportsColors.gold)
                    .padding(10)
                    .background(.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, showScoresStrip ? 140 : 40)
            }
        }
    }

    private var streamOptions: [ChannelMatch] {
        var opts = [ChannelMatch(channel: channel, score: 100, reason: "Current")]
        opts.append(contentsOf: alternates.filter { $0.channel.id != channel.id })
        return opts
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let g = channel.group {
                    Text(g)
                        .font(.caption2)
                        .foregroundStyle(SportsColors.muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button { playback.jumpToLive() } label: {
                HStack(spacing: 4) {
                    Circle().fill(SportsColors.live).frame(width: 8, height: 8)
                    Text("LIVE").font(.caption.weight(.black))
                }
                .foregroundStyle(SportsColors.live)
                .padding(.horizontal, 8)
            }
            Button { cycleAspect() } label: {
                Image(systemName: "aspectratio")
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
            }
            Button { showScoresStrip.toggle() } label: {
                Image(systemName: showScoresStrip ? "sportscourt.fill" : "sportscourt")
                    .foregroundStyle(showScoresStrip ? SportsColors.gold : .white.opacity(0.85))
                    .padding(8)
            }
            Button { showStreamSheet = true } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(SportsColors.gold)
                    .padding(8)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
        )
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
            // Quick engine switch when current stack fails
            if appModel.playerPrefs.engine != .ffmpeg {
                Button("Retry with FFmpeg") {
                    var prefs = appModel.playerPrefs
                    prefs.engine = .ffmpeg
                    appModel.setPlayerPrefs(prefs)
                    playback.configure(engine: .ffmpeg, hardwareDecode: prefs.hardwareDecode)
                    playback.start(url: channel.url)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.gold)
            } else if appModel.playerPrefs.engine != .avPlayer {
                Button("Retry with AVPlayer") {
                    var prefs = appModel.playerPrefs
                    prefs.engine = .avPlayer
                    appModel.setPlayerPrefs(prefs)
                    playback.configure(engine: .avPlayer, hardwareDecode: prefs.hardwareDecode)
                    playback.start(url: channel.url)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(SportsColors.gold)
            }
            if let alt = IptvService.alternateXtreamContainer(channel.url) {
                Button("Try alternate format (.ts / .m3u8)") {
                    channel = IptvChannel(
                        id: channel.id,
                        name: channel.name,
                        url: alt,
                        group: channel.group,
                        logoURL: channel.logoURL,
                        tvgId: channel.tvgId,
                        epgChannelId: channel.epgChannelId
                    )
                    playback.start(url: alt)
                }
                .font(.caption)
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
                                Text(m.channel.name).foregroundStyle(SportsColors.text)
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
            .scrollContentBackground(.hidden)
            .background(SportsColors.panel)
            .navigationTitle("Streams")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showStreamSheet = false
                        showGamePicker = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
            try? await Task.sleep(nanoseconds: 5_000_000_000)
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
}
