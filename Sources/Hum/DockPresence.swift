import AppKit
import HumCore
import HumUI

/// Hum is a menu-bar app, with no Dock icon or menu bar of its own. While the
/// Listening History window is open it becomes an ordinary app, so the Dock
/// icon and the Hum, Edit, Window, and Help menus appear; when it closes it
/// goes back (DESIGN.md §13.26). Settings is a utility window and never
/// counts, whatever else is open; nor do the player and its popovers, so they
/// never bring the Dock icon or activate Hum.
@MainActor
final class DockPresence {
    /// What decides whether a window brings the Dock icon.
    nonisolated struct WindowFacts: Equatable, Sendable {
        var isVisible: Bool
        var isMiniaturized = false
        var isTitled: Bool
        var isPanel: Bool
        var isSheet: Bool
        var isSettings = false
    }

    /// Listening History is a titled window, and the only one that counts.
    /// Settings is titled too but tagged, so it's left out. The player is a
    /// borderless panel; popovers, menus, and tooltips are untitled; alerts
    /// and open and save panels are panels or sheets.
    nonisolated static func bringsDockIcon(_ window: WindowFacts) -> Bool {
        // A minimized window is still open, in the Dock.
        guard window.isVisible || window.isMiniaturized, !window.isSheet, !window.isSettings else { return false }
        return window.isTitled && !window.isPanel
    }

    nonisolated static func policy(for windows: some Sequence<WindowFacts>) -> NSApplication.ActivationPolicy {
        windows.contains(where: bringsDockIcon) ? .regular : .accessory
    }

    /// Going back to a menu-bar app gives up the front. When Hum had it and
    /// Settings is still open, Settings takes it back, as an app's next window
    /// does when one closes.
    nonisolated static func settingsTakesTheFront(
        after policy: NSApplication.ActivationPolicy,
        wasActive: Bool,
        windows: some Sequence<WindowFacts>
    ) -> Bool {
        policy == .accessory && wasActive && windows.contains { $0.isSettings && $0.isVisible }
    }

    private var observers: [any NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let changes = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSApplication.didUnhideNotification,
        ]
        observers = changes.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        // A closing window is still on screen; look again once it's gone.
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAfterClose() }
        })
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func updateAfterClose() {
        Task { [weak self] in self?.update() }
    }

    private func update() {
        // Hide Hum takes every window off screen until it's shown again.
        guard !NSApp.isHidden else { return }
        let facts = NSApp.windows.map(WindowFacts.init)
        let policy = Self.policy(for: facts)
        guard policy != NSApp.activationPolicy() else { return }
        let wasActive = NSApp.isActive
        NSApp.setActivationPolicy(policy)
        HumLog.app.debug("Dock icon \(policy == .regular ? "shown" : "hidden", privacy: .public)")
        if policy == .regular, NSApp.isActive {
            // Already in front as a menu-bar app: activate again so the menu
            // bar switches to Hum's.
            NSApp.activate()
        } else if Self.settingsTakesTheFront(after: policy, wasActive: wasActive, windows: facts),
                  let settings = NSApp.windows.first(where: { $0.isVisible && $0.identifier == SettingsWindowPresenter.windowIdentifier }) {
            NSApp.activate()
            settings.makeKeyAndOrderFront(nil)
        }
    }
}

extension DockPresence.WindowFacts {
    init(_ window: NSWindow) {
        self.init(
            isVisible: window.isVisible,
            isMiniaturized: window.isMiniaturized,
            isTitled: window.styleMask.contains(.titled),
            isPanel: window is NSPanel,
            isSheet: window.isSheet,
            isSettings: window.identifier == SettingsWindowPresenter.windowIdentifier
        )
    }
}
