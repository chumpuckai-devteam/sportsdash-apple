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
            SportsTVFocused { focused in
                categoryLabel(focused: focused)
            }
        }
        .sportsTVFocusClean()
        #else
        Menu {
            Picker("Category", selection: $selection) {
                ForEach(options, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        } label: {
            categoryLabel(focused: false)
        }
        .menuOrder(.fixed)
        #endif
    }

    private func categoryLabel(focused: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.body.weight(.semibold))
            Text(title.isEmpty ? "Category" : title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        #if os(tvOS)
        .frame(minHeight: SportsTVMetrics.minFocusSize)
        .background {
            Capsule(style: .continuous)
                .fill(focused ? SportsColors.gold : SportsColors.panelElevated)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(focused ? SportsColors.goldDim : SportsColors.border.opacity(0.4), lineWidth: focused ? 2 : 1)
        }
        .clipShape(Capsule(style: .continuous))
        .scaleEffect(focused ? SportsTVMetrics.chipFocusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        #else
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
                SportsColors.voidBlack
                    .ignoresSafeArea()

                List {
                    Section {
                        ForEach(options, id: \.self) { name in
                            Button {
                                selection = name
                                onDone()
                            } label: {
                                #if os(tvOS)
                                SportsTVFocused { focused in
                                    categoryRow(name: name, focused: focused)
                                }
                                #else
                                categoryRow(name: name, focused: false)
                                #endif
                            }
                            #if os(tvOS)
                            .sportsTVFocusClean()
                            .listRowBackground(Color.clear)
                            #else
                            .buttonStyle(.plain)
                            .listRowBackground(rowBackground(selected: name == selection))
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
                        #if os(tvOS)
                        .sportsTVFocusClean()
                        #endif
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func categoryRow(name: String, focused: Bool) -> some View {
        let selected = name == selection
        return HStack(spacing: 20) {
            Text(name)
                .font(.body.weight(.semibold))
                .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.text)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(focused ? SportsColors.voidBlack : SportsColors.gold)
                    .imageScale(.large)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(minHeight: SportsTVMetrics.minFocusSize, alignment: .leading)
        .contentShape(Rectangle())
        #if os(tvOS)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(focused ? SportsColors.gold : (selected ? SportsColors.panelElevated : SportsColors.panel))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    focused ? SportsColors.goldDim : (selected ? SportsColors.gold.opacity(0.45) : SportsColors.border.opacity(0.35)),
                    lineWidth: focused || selected ? 2 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(focused ? SportsTVMetrics.focusScale : 1.0)
        .animation(SportsTVFocusMotion.animation, value: focused)
        #endif
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
