import HumCore
import SwiftUI

/// The Settings window: a sidebar of tinted panes in groups, and the current
/// pane's grouped form, with the pane's name as the window title (DESIGN.md §8).
/// Every control applies as it changes; there's no Save button.
struct SettingsView: View {
    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            List(selection: selection) {
                // Written out, not a `ForEach` of sections: on macOS 15 the
                // sidebar then draws a group's header inside its first row's
                // selection.
                section(.general)
                section(.player)
                section(.music)
                section(.hum)
            }
            .listStyle(.sidebar)
            // On the list itself: removed any further out, the toggle takes
            // the column's width with it on macOS 15, and the sidebar shrinks
            // to its narrowest and cuts off "History & Privacy".
            .toolbar(removing: .sidebarToggle)
            // Not `contentMargins`: SwiftUI applies that only from the window's
            // second update, so the first row would open against the title bar.
            .safeAreaPadding(.top, SettingsMetrics.sidebarTopInset)
            .navigationSplitViewColumnWidth(SettingsMetrics.sidebarWidth)
        } detail: {
            pane(navigation.pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The window's title, in its unified toolbar, as in System Settings.
                .navigationTitle(navigation.pane.title)
        }
        .frame(width: SettingsMetrics.windowSize.width, height: SettingsMetrics.windowSize.height)
    }

    /// The sidebar's selection. A sidebar list can deselect, which Settings never
    /// wants, so a `nil` write is ignored.
    private var selection: Binding<SettingsPane?> {
        Binding {
            navigation.pane
        } set: { pane in
            navigation.open(pane)
        }
    }

    private func section(_ group: SettingsSidebarGroup) -> some View {
        Section {
            ForEach(group.panes) { pane in
                SettingsSidebarRow(pane: pane)
            }
        } header: {
            if let title = group.title { Text(title) }
        }
    }

    @ViewBuilder
    private func pane(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .player: PlayerSettingsPane()
        case .shortcuts: ShortcutsSettingsPane()
        case .sources: SourcesSettingsPane()
        case .echoPrivacy: EchoPrivacySettingsPane()
        case .about: HumSettingsPane()
        }
    }
}
