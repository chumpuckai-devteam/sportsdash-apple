import SwiftUI

/// Toolbar / chrome category picker for long IPTV group lists.
/// - iOS: button opens searchable sheet (caller `onOpen`, or internal sheet fallback)
/// - tvOS: caller opens `SportsCategoryPickerScreen` via `onOpen` (focus-friendly fullScreen)
struct SportsCategoryMenu: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var onOpen: (() -> Void)? = nil

    @State private var showPicker = false

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
        Button {
            if let onOpen {
                onOpen()
            } else {
                showPicker = true
            }
        } label: {
            categoryLabel(focused: false)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens searchable category list")
        .sheet(isPresented: $showPicker) {
            SportsCategoryPickerScreen(
                selection: $selection,
                options: options,
                onDone: { showPicker = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
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

/// Searchable category list — iOS sheet + tvOS fullScreenCover.
struct SportsCategoryPickerScreen: View {
    @Binding var selection: String
    let options: [String]
    var onDone: () -> Void

    @State private var query = ""
    #if os(tvOS)
    @FocusState private var searchFocused: Bool
    #endif

    /// Case-insensitive substring filter over group names.
    private var filtered: [String] {
        Self.filteredGroups(options: options, query: query)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var headerText: String {
        if trimmedQuery.isEmpty {
            return "\(options.count) groups"
        }
        return "\(filtered.count) of \(options.count) groups"
    }

    /// Pure filter helper (testable / shared).
    static func filteredGroups(options: [String], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return options }
        return options.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SportsColors.voidBlack
                    .ignoresSafeArea()

                List {
                    Section {
                        if filtered.isEmpty {
                            emptyRow
                        } else {
                            ForEach(filtered, id: \.self) { name in
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
                        }
                    } header: {
                        Text(headerText)
                            .foregroundStyle(SportsColors.muted)
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .searchable(text: $query, prompt: "Search groups")
                #else
                .listStyle(.plain)
                #endif
            }
            .navigationTitle("Category")
            #if os(tvOS)
            .safeAreaInset(edge: .top) {
                tvSearchField
            }
            #endif
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

    @ViewBuilder
    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(SportsColors.text)
            Text(emptySubtitle)
                .font(.subheadline)
                .foregroundStyle(SportsColors.muted)
            if !trimmedQuery.isEmpty {
                Button("Clear search") { query = "" }
                    #if os(tvOS)
                    .sportsTVFocusClean()
                    #endif
            }
        }
        .padding(.vertical, 8)
        #if os(iOS)
        .listRowBackground(SportsColors.panel)
        #else
        .listRowBackground(Color.clear)
        #endif
    }

    private var emptyTitle: String {
        options.isEmpty ? "No categories" : "No groups match"
    }

    private var emptySubtitle: String {
        if options.isEmpty {
            return "Load a playlist with groups to pick a category."
        }
        if trimmedQuery.isEmpty {
            return "Nothing to show."
        }
        return "Nothing matches “\(trimmedQuery)”."
    }

    #if os(tvOS)
    private var tvSearchField: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(searchFocused ? SportsColors.voidBlack : SportsColors.gold)
            TextField("Search groups", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .foregroundStyle(searchFocused ? SportsColors.voidBlack : SportsColors.text)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(searchFocused ? SportsColors.voidBlack.opacity(0.75) : SportsColors.muted)
                }
                .sportsTVFocusClean()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(minHeight: SportsTVMetrics.minFocusSize)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(searchFocused ? SportsColors.gold : SportsColors.panelElevated)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    searchFocused ? SportsColors.goldDim : SportsColors.border.opacity(0.4),
                    lineWidth: searchFocused ? 2 : 1
                )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .animation(SportsTVFocusMotion.animation, value: searchFocused)
    }
    #endif

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
