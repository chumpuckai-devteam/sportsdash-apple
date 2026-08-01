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
}

/// First-run orientation when playlist or leagues aren't set up yet.
/// Deep-links into the right settings screens (not buried under Advanced).
struct SetupChecklistCard: View {
    @EnvironmentObject private var appModel: AppModel

    private var needsPlaylist: Bool { SetupChecklist.needsPlaylist(appModel) }
    private var needsLeagues: Bool { SetupChecklist.needsLeagues(appModel) }
    private var ratingsDone: Bool { SetupChecklist.hasRatingsKeys() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SportsColors.gold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish setup")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(SportsColors.text)
                    Text("A few steps so Scores and Guide light up.")
                        .font(.caption)
                        .foregroundStyle(SportsColors.muted)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 10) {
                NavigationLink {
                    PlaylistSettingsView()
                } label: {
                    setupRow(
                        done: !needsPlaylist,
                        title: "Add a playlist",
                        subtitle: playlistSubtitle,
                        icon: "list.bullet.rectangle"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ScoresSettingsView()
                } label: {
                    setupRow(
                        done: !needsLeagues,
                        title: "Choose leagues",
                        subtitle: leaguesSubtitle,
                        icon: "sportscourt"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    GeneralSettingsView()
                } label: {
                    setupRow(
                        done: ratingsDone,
                        title: "Movie ratings (optional)",
                        subtitle: ratingsDone
                            ? "OMDb / TMDB key saved"
                            : "OMDb / TMDB keys in General",
                        icon: "star.circle"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SportsColors.panelElevated.opacity(0.95))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SportsColors.gold.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Finish setup checklist")
    }

    private var playlistSubtitle: String {
        if needsPlaylist {
            return "Xtream or M3U"
        }
        if appModel.channels.isEmpty {
            return appModel.isLoadingChannels
                ? "Loading channels…"
                : "Configured · no channels yet"
        }
        return "\(appModel.channels.count) channels"
    }

    private var leaguesSubtitle: String {
        if needsLeagues {
            return "MLB, NBA, soccer, …"
        }
        let labels = appModel.selectedLeagues.map(\.label)
        let head = labels.prefix(4).joined(separator: ", ")
        return labels.count > 4 ? "\(head)…" : head
    }

    private func setupRow(done: Bool, title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(.title3)
                .foregroundStyle(done ? SportsColors.live : SportsColors.gold)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SportsColors.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(SportsColors.muted)
                .opacity(done ? 0.35 : 1)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        #if os(tvOS)
        .frame(minHeight: SportsTVMetrics.minFocusSize)
        #endif
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SportsColors.panel.opacity(0.9))
        }
        .contentShape(Rectangle())
        .accessibilityHint(done ? "Completed. Opens settings." : "Opens settings.")
    }
}
