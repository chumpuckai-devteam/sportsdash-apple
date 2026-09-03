import SwiftUI

/// Shared first-run gates — playlist missing/unconfigured, or zero selected leagues.
/// Ratings keys are optional and never block dismissal.
/// `@MainActor` — reads `AppModel` observable state (main-actor isolated).
@MainActor
enum SetupChecklist {
    static func needsPlaylist(_ appModel: AppModel) -> Bool {
        appModel.playlists.isEmpty || appModel.iptvConfig?.isConfigured != true
    }

    static func needsLeagues(_ appModel: AppModel) -> Bool {
        appModel.selectedLeagues.isEmpty
    }

    /// Core setup incomplete — card should show on Settings root / Scores.
    static func isIncomplete(_ appModel: AppModel) -> Bool {
        needsPlaylist(appModel) || needsLeagues(appModel)
    }

    static func hasRatingsKeys() -> Bool {
        KeychainStore.hasValue(account: MovieRatingsService.omdbKeyAccount)
            || KeychainStore.hasValue(account: MovieRatingsService.tmdbKeyAccount)
    }

    static func playlistLamp(_ appModel: AppModel) -> JumbotronLampKind {
        if let err = appModel.channelsError, !err.isEmpty { return .blocked }
        return needsPlaylist(appModel) ? .pending : .done
    }

    static func epgLamp(_ appModel: AppModel) -> JumbotronLampKind {
        if let err = appModel.epg.epgError, !err.isEmpty { return .blocked }
        if appModel.epg.epgLoadedCount > 0 { return .done }
        return .pending
    }

    static func favoritesLamp(_ appModel: AppModel) -> JumbotronLampKind {
        appModel.favoriteTeamIds.isEmpty ? .pending : .done
    }

    static func setupDoneCount(_ appModel: AppModel) -> Int {
        [playlistLamp(appModel) == .done, epgLamp(appModel) == .done, favoritesLamp(appModel) == .done]
            .filter { $0 }.count
    }

    static func ctaTitle(_ appModel: AppModel) -> String {
        if needsPlaylist(appModel) { return "ADD PLAYLIST ▸" }
        if appModel.favoriteTeamIds.isEmpty { return "PICK TEAMS ▸" }
        if epgLamp(appModel) != .done { return "RELOAD EPG ▸" }
        return "SETTINGS ▸"
    }
}

/// First-run orientation when playlist or leagues aren't set up yet.
/// Deep-links into the right settings screens (not buried under Advanced).
struct SetupChecklistCard: View {
    @EnvironmentObject private var appModel: AppModel
    /// Observed so the EPG lamp updates; the helpers above read through `appModel.epg`.
    @EnvironmentObject private var epgStore: EpgStore
    var forceTitle: String? = nil

    private var playlist: JumbotronLampKind { SetupChecklist.playlistLamp(appModel) }
    private var epgLamp: JumbotronLampKind { SetupChecklist.epgLamp(appModel) }
    private var favorites: JumbotronLampKind { SetupChecklist.favoritesLamp(appModel) }
    private var setupCount: Int { SetupChecklist.setupDoneCount(appModel) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                lampRow("PLAYLIST", playlist)
                lampRow("EPG", epgLamp)
                lampRow("FAVORITES", favorites)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(forceTitle ?? "SETUP")
                        .font(JumbotronFonts.display(22))
                        .foregroundStyle(SportsColors.text)
                    JumbotronLED(text: "\(setupCount)/3", size: 20, color: SportsColors.gold, glow: true)
                }
                ctaLink
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            LinearGradient(
                stops: [
                    .init(color: Color(sportsHex: "E31837")?.opacity(0.35) ?? SportsColors.danger.opacity(0.35), location: 0),
                    .init(color: SportsColors.panel.opacity(0.95), location: 0.40),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .overlay { Rectangle().stroke(SportsColors.gold.opacity(0.45), lineWidth: 2) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup \(setupCount) of 3")
    }

    @ViewBuilder
    private var ctaLink: some View {
        let title = SetupChecklist.ctaTitle(appModel)
        if SetupChecklist.needsPlaylist(appModel) {
            NavigationLink { PlaylistSettingsView() } label: { ctaLabel(title) }
                .buttonStyle(.plain)
        } else if appModel.favoriteTeamIds.isEmpty {
            NavigationLink { FavoriteTeamPickerView() } label: { ctaLabel(title) }
                .buttonStyle(.plain)
        } else if SetupChecklist.epgLamp(appModel) != .done {
            Button {
                Task { await appModel.reloadEpg(force: true) }
            } label: { ctaLabel(title) }
            .buttonStyle(.plain)
        } else {
            NavigationLink { ScoresSettingsView() } label: { ctaLabel(title) }
                .buttonStyle(.plain)
        }
    }

    private func ctaLabel(_ title: String) -> some View {
        Text(title)
            .font(JumbotronFonts.display(16))
            .foregroundStyle(SportsColors.voidBlack)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(SportsColors.gold)
            .shadow(color: SportsColors.ledGlow.opacity(0.55), radius: 6)
            .frame(minHeight: 44)
    }

    private func lampRow(_ title: String, _ kind: JumbotronLampKind) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(lampColor(kind))
                .frame(width: 10, height: 10)
                .shadow(color: lampColor(kind).opacity(0.9), radius: 4)
            Text(title)
                .font(JumbotronFonts.body(11))
                .foregroundStyle(SportsColors.text)
        }
    }

    private func lampColor(_ kind: JumbotronLampKind) -> Color {
        switch kind {
        case .done: return SportsColors.live
        case .pending: return SportsColors.gold
        case .blocked: return SportsColors.danger
        }
    }
}
