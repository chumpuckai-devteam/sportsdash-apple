import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum FloatingPlayerSize: Equatable {
    case compact
    case expanded
}

struct FloatingPlayerState: Equatable {
    var channel: IptvChannel
    var game: Game?
    var size: FloatingPlayerSize
}

/// UHF-style in-app pop-out player over tabs. Double-tap toggles compact ↔ expanded.
struct FloatingPlayerView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var playback: PlaybackController

    @State private var showControls = true
    @State private var dragOffset: CGSize = .zero
    @State private var settledOrigin: CGPoint = CGPoint(x: 12, y: 56)
    @State private var hideControlsTask: Task<Void, Never>?

    private var state: FloatingPlayerState? { appModel.floatingPlayer }

    private var compactSize: CGSize { CGSize(width: 168, height: 96) }
    private var expandedWidth: CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.width - 24
        #else
        640
        #endif
    }
    private var expandedSize: CGSize {
        CGSize(width: expandedWidth, height: expandedWidth * 9 / 16 + 44)
    }

    var body: some View {
        GeometryReader { geo in
            if let state {
                playerCard(state: state, in: geo.size)
                    .position(
                        x: settledOrigin.x + dragOffset.width + currentSize(state).width / 2,
                        y: settledOrigin.y + dragOffset.height + currentSize(state).height / 2
                    )
                    .gesture(dragGesture(in: geo.size, state: state))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(appModel.floatingPlayer != nil)
    }

    private func currentSize(_ state: FloatingPlayerState) -> CGSize {
        state.size == .compact ? compactSize : expandedSize
    }

    private func playerCard(state: FloatingPlayerState, in bounds: CGSize) -> some View {
        let size = currentSize(state)
        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)

            KSPlayerSurface(playback: playback)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if (playback.isLoading || playback.isBuffering) && !playback.isPlaying {
                ProgressView().tint(SportsColors.gold)
            }

            // Controls overlay
            if showControls || state.size == .expanded {
                controlsOverlay(state: state)
            }

            // LIVE badge always visible on compact when playing
            if state.size == .compact, playback.isPlaying {
                VStack {
                    Spacer()
                    HStack {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(SportsColors.danger.opacity(0.9), in: Capsule())
                            .padding(8)
                        Spacer()
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(count: 2) {
            toggleSize(state)
        }
        .onTapGesture(count: 1) {
            showControls.toggle()
            if showControls { scheduleHideControls() }
        }
        .onAppear {
            // Start near top-leading like UHF.
            settledOrigin = CGPoint(x: 12, y: 56)
            showControls = true
            scheduleHideControls()
        }
    }

    private func controlsOverlay(state: FloatingPlayerState) -> some View {
        ZStack {
            // Dim for expanded readability
            if state.size == .expanded {
                Color.black.opacity(0.25)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        appModel.closeFloatingPlayer()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.45), in: Circle())
                    }

                    Spacer()

                    Button {
                        appModel.expandFloatingPlayerToFullscreen()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                }
                .padding(8)

                Spacer()

                if state.size == .expanded {
                    // Transport row (UHF-style)
                    HStack(spacing: 28) {
                        Button {
                            playback.jumpToLive()
                            scheduleHideControls()
                        } label: {
                            Image(systemName: "gobackward.10")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.white.opacity(0.15), in: Circle())
                        }

                        Button {
                            playback.togglePlayPause()
                            scheduleHideControls()
                        } label: {
                            Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(.white.opacity(0.2), in: Circle())
                        }

                        Button {
                            playback.jumpToLive()
                            scheduleHideControls()
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                    }
                    .padding(.bottom, 8)

                    // Live progress bar (decorative edge indicator)
                    VStack(spacing: 6) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.25))
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: g.size.width * 0.92)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            Text("LIVE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SportsColors.danger, in: Capsule())
                            Spacer()
                            Text(ChannelNameCleanup.displayName(
                                state.channel.name,
                                enabled: appModel.playerPrefs.cleanUpNames
                            ))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                } else {
                    // Compact: play + close already in corners; small transport
                    HStack {
                        Spacer()
                        Button {
                            playback.togglePlayPause()
                        } label: {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .padding(8)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func toggleSize(_ state: FloatingPlayerState) {
        var next = state
        next.size = state.size == .compact ? .expanded : .compact
        appModel.floatingPlayer = next
        // Keep on-screen after resize
        dragOffset = .zero
        showControls = true
        scheduleHideControls()
    }

    private func dragGesture(in bounds: CGSize, state: FloatingPlayerState) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let size = currentSize(state)
                var origin = CGPoint(
                    x: settledOrigin.x + value.translation.width,
                    y: settledOrigin.y + value.translation.height
                )
                // Clamp inside screen (leave margin for Dynamic Island / home indicator).
                let margin: CGFloat = 8
                origin.x = min(max(margin, origin.x), bounds.width - size.width - margin)
                origin.y = min(max(margin + 40, origin.y), bounds.height - size.height - margin - 50)
                settledOrigin = origin
                dragOffset = .zero
            }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    // Keep expanded controls a bit longer; still auto-hide.
                    showControls = false
                }
            }
        }
    }
}
