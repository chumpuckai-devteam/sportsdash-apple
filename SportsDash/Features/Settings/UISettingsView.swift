import SwiftUI

/// User interface settings — theme, guide layout, launch tab, name cleanup.
struct UISettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    private var themeBinding: Binding<AppThemeMode> {
        PrefsBinding.field(appModel, get: \.theme) { $0.theme = $1 }
    }

    private var guideBinding: Binding<GuideLayoutMode> {
        PrefsBinding.field(appModel, get: \.guideLayout) { $0.guideLayout = $1 }
    }

    private var cleanNamesBinding: Binding<Bool> {
        PrefsBinding.field(appModel, get: \.cleanUpNames) { $0.cleanUpNames = $1 }
    }

    private var launchBinding: Binding<LaunchTab> {
        PrefsBinding.field(appModel, get: \.launchTab) { $0.launchTab = $1 }
    }

    var body: some View {
        Form {
            Section {
                Picker("App launch action", selection: launchBinding) {
                    ForEach(LaunchTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                Toggle(isOn: cleanNamesBinding) {
                    Label("Clean up names", systemImage: "text.badge.xmark")
                }
                .tint(SportsColors.gold)
                Text("Hides common quality tags (4K, FHD, HEVC…) from channel labels.")
                    .font(.caption)
                    .foregroundStyle(SportsColors.muted)
            } header: {
                Text("Advanced customizations")
            }

            Section {
                ForEach(AppThemeMode.allCases) { mode in
                    Button {
                        var p = appModel.playerPrefs
                        p.theme = mode
                        appModel.setPlayerPrefs(p)
                    } label: {
                        HStack {
                            Text(mode.label).foregroundStyle(SportsColors.text)
                            Spacer()
                            if appModel.playerPrefs.theme == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SportsColors.gold)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(SportsColors.muted)
                            }
                        }
                    }
                }
            } header: {
                Text("Theme")
            }

            Section {
                ForEach(GuideLayoutMode.allCases) { mode in
                    Button {
                        var p = appModel.playerPrefs
                        p.guideLayout = mode
                        appModel.setPlayerPrefs(p)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.label).foregroundStyle(SportsColors.text)
                                Text(mode == .list ? "Channel × time guide" : "Card-style Now / Next")
                                    .font(.caption)
                                    .foregroundStyle(SportsColors.muted)
                            }
                            Spacer()
                            if appModel.playerPrefs.guideLayout == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SportsColors.gold)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(SportsColors.muted)
                            }
                        }
                    }
                }
            } header: {
                Text("EPG layout")
            }
        }
        .scrollContentBackground(.hidden)
        .background(SportsColors.voidBlack)
        .navigationTitle("User interface")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
