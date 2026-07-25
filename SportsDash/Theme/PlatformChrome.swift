import SwiftUI

// MARK: - Platform-safe chrome (iOS APIs stubbed on tvOS)

extension View {
    /// iOS: hide default List/Form scroll background. tvOS: no-op.
    @ViewBuilder
    func sportsHideScrollBackground() -> some View {
        #if os(iOS)
        self.scrollContentBackground(.hidden)
        #else
        self
        #endif
    }

    @ViewBuilder
    func sportsNavTitleMode(large: Bool = false) -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(large ? .large : .inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func sportsInsetGroupedList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.grouped)
        #endif
    }

    @ViewBuilder
    func sportsRefreshable(_ action: @escaping @Sendable () async -> Void) -> some View {
        #if os(iOS)
        self.refreshable { await action() }
        #else
        self
        #endif
    }

    @ViewBuilder
    func sportsSheetChrome() -> some View {
        #if os(iOS)
        self
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground { SportsColors.voidBlack }
        #else
        self
        #endif
    }

    @ViewBuilder
    func sportsHiddenNavBarBackground() -> some View {
        #if os(iOS)
        self.toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Full-screen cover on iOS; sheet on tvOS.
    @ViewBuilder
    func sportsPlayerCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item, content: content)
        #else
        self.sheet(item: item, content: content)
        #endif
    }
}

enum SportsToolbarPlacement {
    #if os(iOS)
    static var leading: ToolbarItemPlacement { .topBarLeading }
    static var trailing: ToolbarItemPlacement { .topBarTrailing }
    #else
    static var leading: ToolbarItemPlacement { .topBarLeading }
    static var trailing: ToolbarItemPlacement { .topBarTrailing }
    #endif
}
