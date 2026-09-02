import SwiftUI

/// Jumbotron phone Guide list — Now-bar rows (timeline grid is TV / later).
struct GuideNowBarList: View {
    let rows: [GuideChannelRowData]
    var selectedGroup: String
    var groupNames: [String]
    var moviesOnly: Bool
    var displayMode: GuideLayoutMode
    var now: Date
    var cleanNames: Bool
    var favoriteChannelIds: Set<String>
    var epgError: String?
    var isLoadingEpg: Bool
    var onSelectGroup: () -> Void
    var onGrid: () -> Void
    var onMovies: () -> Void
    var onPlay: (IptvChannel) -> Void
    var onToggleFavorite: (IptvChannel) -> Void
    var onChooseCategory: () -> Void
    var onReloadEPG: () -> Void

    @State private var hourAnchor: Date? = nil

    private var playable: [GuideChannelRowData] {
        rows.filter { !$0.channel.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var anchor: Date { hourAnchor ?? now }

    private var liveCount: Int {
        playable.filter { row in
            (row.programs.first(where: \.isNow) != nil)
        }.count
    }

    private var hourChips: [Date] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .hour, for: now)?.start ?? now
        return (1...3).compactMap { cal.date(byAdding: .hour, value: $0, to: start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                JumbotronScreenTitle(first: "CHANNEL ", gold: "GUIDE")
                Spacer(minLength: 8)
            }
            .padding(.horizontal, SportsMetrics.screenInset)
            .padding(.top, 4)

            HStack(spacing: 6) {
                Button(action: onSelectGroup) {
                    HStack {
                        Text((selectedGroup.isEmpty ? "★ FAVORITES" : selectedGroup).uppercased())
                            .font(JumbotronFonts.display(18))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        Text("▾")
                            .font(JumbotronFonts.display(16))
                            .foregroundStyle(SportsColors.muted)
                    }
                    .foregroundStyle(SportsColors.gold)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .jumbotronPanel(border: SportsColors.gold.opacity(0.5))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)

                Button(action: onGrid) {
                    Text("GRID")
                        .font(JumbotronFonts.display(16))
                        .foregroundStyle(displayMode == .grid ? SportsColors.voidBlack : SportsColors.muted)
                        .frame(width: 64, height: 38)
                        .background(displayMode == .grid ? SportsColors.gold : SportsColors.panelGradient)
                        .overlay { Rectangle().stroke(SportsColors.border, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)

                Button(action: onMovies) {
                    Text("MOVIES")
                        .font(JumbotronFonts.display(16))
                        .foregroundStyle(moviesOnly ? SportsColors.voidBlack : SportsColors.muted)
                        .frame(width: 74, height: 38)
                        .background(moviesOnly ? SportsColors.gold : SportsColors.panelGradient)
                        .overlay { Rectangle().stroke(SportsColors.border, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, SportsMetrics.screenInset)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    nowChip
                    ForEach(hourChips, id: \.self) { h in
                        hourChip(h)
                    }
                }
                .padding(.horizontal, SportsMetrics.screenInset)
            }

            if let epgError, !epgError.isEmpty {
                JumbotronMessagePanel(
                    tick: SportsColors.danger,
                    title: "EPG UNAVAILABLE",
                    subtitle: epgError,
                    cta: "RELOAD EPG",
                    action: onReloadEPG
                )
                .padding(.horizontal, SportsMetrics.screenInset)
            } else if playable.isEmpty {
                JumbotronMessagePanel(
                    title: "NO CHANNELS IN THIS CATEGORY",
                    subtitle: "Pick another category.",
                    cta: "CHOOSE CATEGORY",
                    action: onChooseCategory
                )
                .padding(.horizontal, SportsMetrics.screenInset)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("CH")
                            .frame(width: 40, alignment: .leading)
                        Text("NAME")
                            .frame(width: 74, alignment: .leading)
                        HStack {
                            Text("NOW")
                            Spacer()
                            JumbotronLED(
                                text: "▼ \(Self.hhmm.string(from: now))",
                                size: 9,
                                color: SportsColors.live,
                                glow: true
                            )
                            Spacer()
                            Text("ENDS")
                        }
                    }
                    .font(JumbotronFonts.body(9))
                    .foregroundStyle(SportsColors.muted)
                    .padding(.leading, 15)
                    .padding(.trailing, 8)
                    .frame(height: 28)

                    ForEach(Array(playable.enumerated()), id: \.element.id) { idx, row in
                        GuideNowBarRow(
                            index: idx + 1,
                            row: row,
                            now: anchor,
                            wallNow: now,
                            cleanNames: cleanNames,
                            isFavorite: favoriteChannelIds.contains(row.channel.id),
                            onPlay: { onPlay(row.channel) },
                            onToggleFavorite: { onToggleFavorite(row.channel) }
                        )
                    }
                }
                .jumbotronPanel()
                .padding(.horizontal, SportsMetrics.screenInset)
            }
        }
        .jumbotronAXCap()
    }

    private var nowChip: some View {
        let selected = hourAnchor == nil
        return Button {
            hourAnchor = nil
        } label: {
            Text("NOW · \(liveCount) LIVE")
                .font(JumbotronFonts.display(14))
                .foregroundStyle(selected ? SportsColors.voidBlack : SportsColors.muted)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(selected ? SportsColors.live : Color.clear)
                .overlay {
                    if !selected { Rectangle().stroke(SportsColors.border, lineWidth: 1) }
                }
                .shadow(color: selected ? SportsColors.liveGlow.opacity(0.6) : .clear, radius: 5)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Now, \(liveCount) live")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func hourChip(_ date: Date) -> some View {
        let selected = hourAnchor.map { Calendar.current.isDate($0, equalTo: date, toGranularity: .hour) } ?? false
        return Button {
            hourAnchor = date
        } label: {
            Text(Self.hhmm.string(from: date))
                .font(JumbotronFonts.display(14))
                .foregroundStyle(selected ? SportsColors.gold : SportsColors.muted)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .overlay { Rectangle().stroke(selected ? SportsColors.gold : SportsColors.border, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

private struct GuideNowBarRow: View {
    let index: Int
    let row: GuideChannelRowData
    let now: Date
    let wallNow: Date
    var cleanNames: Bool
    var isFavorite: Bool
    var onPlay: () -> Void
    var onToggleFavorite: () -> Void

    private var program: EpgProgram? {
        row.programs.first { $0.start <= now && now < $0.end }
            ?? row.programs.first { $0.start >= now }
            ?? row.programs.first
    }

    private var isLive: Bool {
        guard let program else { return false }
        return program.start <= wallNow && wallNow < program.end
    }

    private var progress: CGFloat {
        guard let program else { return 0 }
        let total = program.end.timeIntervalSince(program.start)
        guard total > 0 else { return 0 }
        let elapsed = wallNow.timeIntervalSince(program.start)
        return CGFloat(min(1, max(0, elapsed / total)))
    }

    private var displayName: String {
        ChannelNameCleanup.displayName(row.channel.name, enabled: cleanNames)
            .uppercased()
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(JumbotronBrand.stripe(for: row.channel.group))
                    .frame(width: 5)
                JumbotronLED(text: String(format: "%03d", index), size: 13, color: SportsColors.gold, glow: true)
                    .frame(width: 40, alignment: .leading)
                Text(displayName)
                    .font(JumbotronFonts.display(18))
                    .jumbotronDisplayTracking(18)
                    .foregroundStyle(SportsColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 74, alignment: .leading)
                bar
            }
            .frame(height: SportsMetrics.guideRowHeight)
            .overlay(alignment: .top) { Rectangle().fill(SportsColors.gridDot).frame(height: 2) }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(isFavorite ? "Unstar channel" : "Star channel", systemImage: isFavorite ? "star.slash" : "star.fill")
            }
        }
        .accessibilityLabel(a11y)
    }

    private var bar: some View {
        ZStack(alignment: .leading) {
            SportsColors.voidBlack
            if isLive {
                LinearGradient(
                    colors: [SportsColors.live.opacity(0.10), SportsColors.live.opacity(0.30)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(maxWidth: .infinity)
                .scaleEffect(x: progress, y: 1, anchor: .leading)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(SportsColors.live)
                        .frame(width: 2)
                        .shadow(color: SportsColors.liveGlow, radius: 4)
                }
                .frame(width: nil)
            } else {
                LinearGradient(
                    colors: [SportsColors.gold.opacity(0.08), SportsColors.gold.opacity(0.22)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 0)
            }

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text((program?.title ?? "NO LISTING").uppercased())
                            .font(JumbotronFonts.body(11, bold: true))
                            .foregroundStyle(SportsColors.text)
                            .lineLimit(1)
                        if isFavorite {
                            Text("★").foregroundStyle(SportsColors.gold).font(JumbotronFonts.body(10))
                        }
                    }
                    Text(subtitle)
                        .font(JumbotronFonts.body(8))
                        .foregroundStyle(SportsColors.muted)
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                Spacer()
                if isLive {
                    Text("LIVE")
                        .font(JumbotronFonts.digits(8))
                        .foregroundStyle(SportsColors.live)
                        .shadow(color: SportsColors.liveGlow, radius: 4)
                        .padding(.trailing, 6)
                }
            }
        }
        .frame(height: 36)
        .overlay { Rectangle().stroke(SportsColors.border, lineWidth: 1) }
        .clipped()
    }

    private var subtitle: String {
        guard let program else { return "" }
        if isLive {
            let ends = Self.hhmm.string(from: program.end)
            if let cat = program.categoryChipLabel {
                return "\(cat.uppercased()) · ENDS \(ends)"
            }
            return "ENDS \(ends)"
        }
        return program.timeRangeLabel.uppercased()
    }

    private var a11y: String {
        let title = program?.title ?? displayName
        return "\(displayName), \(title)\(isLive ? ", Live" : "")"
    }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
