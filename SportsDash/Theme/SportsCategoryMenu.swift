import SwiftUI

/// Toolbar category picker.
/// - iOS: native `Menu` + `Picker`
/// - tvOS: button → sheet list (Menu often fails under the Siri Remote focus engine)
struct SportsCategoryMenu: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    @State private var showPicker = false

    var body: some View {
        #if os(tvOS)
        Button {
            showPicker = true
        } label: {
            categoryLabel
        }
        .buttonStyle(.card)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List {
                    Section {
                        ForEach(options, id: \.self) { name in
                            Button {
                                selection = name
                                showPicker = false
                            } label: {
                                HStack {
                                    Text(name)
                                        .foregroundStyle(SportsColors.text)
                                        .lineLimit(2)
                                    Spacer()
                                    if name == selection {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(SportsColors.gold)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    } header: {
                        Text("\(options.count) groups")
                    }
                }
                .navigationTitle("Category")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showPicker = false }
                    }
                }
            }
        }
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
