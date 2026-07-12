import SwiftUI

struct ChannelsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                SportsColors.voidBlack.ignoresSafeArea()
                if appModel.channels.isEmpty {
                    ContentUnavailableView(
                        "No channels loaded",
                        systemImage: "tv",
                        description: Text("Add an M3U or Xtream source in Settings.")
                    )
                } else {
                    List {
                        ForEach(groupedKeys, id: \.self) { group in
                            Section(group) {
                                ForEach(grouped[group] ?? []) { ch in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ch.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(SportsColors.text)
                                        if let g = ch.group {
                                            Text(g)
                                                .font(.caption)
                                                .foregroundStyle(SportsColors.muted)
                                        }
                                    }
                                    .listRowBackground(SportsColors.panel)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Channels")
        }
    }

    private var grouped: [String: [IptvChannel]] {
        Dictionary(grouping: appModel.channels) { $0.group?.isEmpty == false ? $0.group! : "Other" }
    }

    private var groupedKeys: [String] {
        grouped.keys.sorted()
    }
}
