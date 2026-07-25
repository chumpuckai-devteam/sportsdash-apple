import SwiftUI

/// Toolbar / chrome category picker.
/// - iOS: native `Menu` + `Picker`
/// - tvOS: caller should prefer `SportsCategoryPickerLink` / full-screen list
///   (toolbar Menu + sheet are unreliable under Siri Remote focus).
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

/// Full-screen category list — reliable on tvOS focus engine.
struct SportsCategoryPickerScreen: View {
    @Binding var selection: String
    let options: [String]
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options, id: \.self) { name in
                        Button {
                            selection = name
                            onDone()
                        } label: {
                            HStack(spacing: 16) {
                                Text(name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(SportsColors.text)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if name == selection {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(SportsColors.gold)
                                        .imageScale(.large)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(options.count) groups")
                }
            }
            .navigationTitle("Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDone)
                }
            }
        }
    }
}
