import AppKit
import HumCore

/// App-level actions a view can trigger without knowing who handles them.
nonisolated public struct PlayerActions: Sendable {
    public var openSettings: @MainActor @Sendable () -> Void
    /// Open Settings on a specific pane, as "History Settings…" does.
    public var openSettingsPane: @MainActor @Sendable (SettingsPane) -> Void
    public var hidePlayer: @MainActor @Sendable () -> Void
    /// Page the player to a surface, as Show ▸ in the player's menu does.
    public var showSurface: @MainActor @Sendable (Surface) -> Void
    /// Pause global shortcuts while the shortcut recorder listens for a new chord.
    public var suspendGlobalShortcuts: @MainActor @Sendable (Bool) -> Void
    /// Pop up a native menu below a control, given the control's frame in the
    /// SwiftUI global coordinate space, as the More button does.
    var popUpMenu: @MainActor @Sendable (NSMenu, CGRect) -> Void
    /// The pointer started, moved, or finished dragging the window by its content.
    var windowDrag: @MainActor @Sendable (WindowDragPhase) -> Void

    public init(
        openSettings: @escaping @MainActor @Sendable () -> Void = {},
        openSettingsPane: @escaping @MainActor @Sendable (SettingsPane) -> Void = { _ in },
        hidePlayer: @escaping @MainActor @Sendable () -> Void = {},
        showSurface: @escaping @MainActor @Sendable (Surface) -> Void = { _ in },
        suspendGlobalShortcuts: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        self.openSettings = openSettings
        self.openSettingsPane = openSettingsPane
        self.hidePlayer = hidePlayer
        self.showSurface = showSurface
        self.suspendGlobalShortcuts = suspendGlobalShortcuts
        popUpMenu = { menu, _ in
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        windowDrag = { _ in }
    }
}

/// A content drag that moves the window. The window follows the pointer's screen
/// location, so it's independent of the window moving underneath; the
/// translation only says where the drag started.
nonisolated enum WindowDragPhase: Sendable {
    case changed(translation: CGSize)
    case ended
}
