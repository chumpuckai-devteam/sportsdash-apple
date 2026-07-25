import SwiftUI

/// Toolbar / chrome category picker.
/// - iOS: native `Menu` + `Picker`
/// - tvOS: caller opens `SportsCategoryPickerScreen` (focus-friendly)
struct SportsCategoryMenu: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var onOpen: (() -> Void)? = nil

    var body: some View {
        #if os(tvOS)
        Button {
            onOpen?()
        } label: {
            categoryLabel
        }
        .buttonStyle(.card)
        #else
        Menu {
            Picker("Category", selection: $selection) {
                ForEach(options, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        } label: {
            categoryLabel
        }
        .menuOrder(.fixed)
        #endif
    }

    private var categoryLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.body.weight(.semibold))
            Text(title.isEmpty ? "Category" : title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(SportsColors.gold)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        #if os(iOS)
        .sportsGlass(in: Capsule(style: .continuous))
        #endif
    }
}

/// Full-screen category list — opaque on tvOS so Guide never shows through.
struct SportsCategoryPickerScreen: View {
    @Binding var selection: String
    let options: [String]
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                // Solid base — fullScreenCover on tvOS can otherwise look translucent
                SportsColors.voidBlack
                    .ignoresSafeArea()

                List {
                    Section {
                        ForEach(options, id: \.self) { name in
                            Button {
                                selection = name
                                onDone()
                            } label: {
                                HStack(spacing: 20) {
                                    Text(name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(SportsColors.text)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if name == selection {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(SportsColors.gold)
                                            .imageScale(.large)
                                    }
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(rowBackground(selected: name == selection))
                            #if os(iOS)
                            .listRowSeparatorTint(SportsColors.border.opacity(0.5))
                            #endif
                        }
                    } header: {
                        Text("\(options.count) groups")
                            .foregroundStyle(SportsColors.muted)
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                #else
                .listStyle(.plain)
                #endif
            }
            .navigationTitle("Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDone)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rowBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(selected ? SportsColors.panelElevated : SportsColors.panel)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? SportsColors.gold.opacity(0.45) : SportsColors.border.opacity(0.35),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .padding(.vertical, 3)
    }
}
