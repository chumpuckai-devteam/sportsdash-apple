import AVFoundation
import AVKit
import SwiftUI

/// Fullscreen IPTV player with LIVE jump, aspect, stream picker, live scores strip.
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

            if let player = playback.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { toggleChrome() }
            }

            if playback.isLoading {
                ProgressView("Starting stream…")
                    .tint(SportsColors.gold)
                    .foregroundStyle(.white)
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

            if showScoresStrip, playback.error == nil, !playback.isLoading {
                VStack {
                    Spacer()
                    LiveScoresStrip(
                        games: appModel.games,
                        currentGameId: game?.id,
                        favoriteTeamIds: appModel.favoriteTeamIds,
                        lastPlayedGameIds: appModel.lastPlayedGameIds,
                        onGameTap: { g in
                            let m = appModel.matches(for: g)
                            if m.isEmpty {
                                playback.banner = "No streams matched for \(g.matchupLabel)"
                            } else {
                                showGamePicker = g
                            }
                        }
                    )
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .statusBarHidden(true)
        .onAppear {
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
        .sheet(isPresented: $showStreamSheet) {
            streamSheet(matches: streamOptions)
        }
        .sheet(item: $showGamePicker) { g in
            streamSheet(matches: appModel.matches(for: g), forGame: g)
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
        var opts = [
            ChannelMatch(channel: channel, score: 100, reason: "Current"),
        ]
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
            Button {
                playback.jumpToLive()
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(SportsColors.live).frame(width: 8, height: 8)
                    Text("LIVE")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(SportsColors.live)
                .padding(.horizontal, 8)
            }
            Button {
                cycleAspect()
            } label: {
                Image(systemName: "aspectratio")
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
            }
            Button {
                showScoresStrip.toggle()
            } label: {
                Image(systemName: showScoresStrip ? "sportscourt.fill" : "sportscourt")
                    .foregroundStyle(showScoresStrip ? SportsColors.gold : .white.opacity(0.85))
                    .padding(8)
            }
            Button {
                showStreamSheet = true
            } label: {
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
                Button("Retry") {
                    playback.start(url: channel.url)
                }
                .buttonStyle(.borderedProminent)
                .tint(SportsColors.gold)
                .foregroundStyle(SportsColors.voidBlack)
                Button("Back") { dismiss() }
                    .buttonStyle(.bordered)
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
                                Text(m.channel.name)
                                    .foregroundStyle(SportsColors.text)
                                if let gr = m.channel.group {
                                    Text(gr)
                                        .font(.caption)
                                        .foregroundStyle(SportsColors.muted)
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
        playback.setVideoGravity(appModel.playerPrefs.aspect)
    }
}

@MainActor
final class PlaybackController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var error: String?
    @Published var banner: String?

    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var triedAlternate = false
    private var currentURL: String?

    func start(url: String) {
        stop()
        currentURL = url
        isLoading = true
        error = nil
        triedAlternate = false
        guard let u = URL(string: url) else {
            error = "Invalid stream URL"
            isLoading = false
            return
        }
        let item = AVPlayerItem(url: u)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        player = p
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.player?.play()
                case .failed:
                    self.handleFail(item.error?.localizedDescription ?? "Playback failed")
                default:
                    break
                }
            }
        }
        // Timeout if stuck loading
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if isLoading {
                handleFail("Stream timed out while loading")
            }
        }
    }

    func stop() {
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    func jumpToLive() {
        guard let player, let item = player.currentItem else {
            if let url = currentURL { start(url: url) }
            return
        }
        let duration = item.duration
        if duration.isNumeric && duration.seconds.isFinite && duration.seconds > 2 {
            let edge = CMTime(seconds: max(0, duration.seconds - 0.5), preferredTimescale: 600)
            player.seek(to: edge)
            player.play()
            banner = "Jumped to live"
        } else if let url = currentURL {
            // Live TS / unknown duration — hard restart
            start(url: url)
            banner = "Rejoined live stream"
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { banner = nil }
        }
    }

    func setVideoGravity(_ aspect: PlayerAspectMode) {
        // AVPlayerViewController gravity is set via VideoPlayer; use layer if available
        // SwiftUI VideoPlayer doesn't expose gravity easily — store for future AVPlayerLayer host
        _ = aspect
    }

    private func handleFail(_ message: String) {
        if !triedAlternate, let url = currentURL,
           let alt = IptvService.alternateXtreamContainer(url) {
            triedAlternate = true
            start(url: alt)
            return
        }
        isLoading = false
        error = message
    }
}
