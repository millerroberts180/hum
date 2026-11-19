import AppKit
import HumCore
import SwiftUI

/// Opens the Settings window, creating it on first use and keeping it, so
/// reopening is instant and the window remembers its pane.
///
/// Settings is a utility window (DESIGN.md §8, §13.26): it comes to the front
/// and takes the keyboard while Hum stays a menu-bar app, with no Dock icon
/// or menu bar of its own. `windowIdentifier` tells `DockPresence` to leave it
/// out.
public final class SettingsWindowPresenter {
    /// Tagged on the Settings window, so it never brings the Dock icon.
    public static let windowIdentifier = NSUserInterfaceItemIdentifier("HumSettingsWindow")

    private let settings: SettingsStore
    private let store: NowPlayingStore
    private let actions: PlayerActions
    private let services: AppServices
    /// The pane on screen. Callers route through `show(pane:)`.
    public let navigation = SettingsNavigation()
    private var window: NSWindow?

    public init(settings: SettingsStore, store: NowPlayingStore, actions: PlayerActions, services: AppServices = AppServices()) {
        self.settings = settings
        self.store = store
        self.actions = actions
        self.services = services
    }

    public func show() {
        show(pane: nil)
    }

    /// Bring Settings forward on `pane`, or on whichever pane it last showed.
    ///
    /// - Parameter activate: Make Hum the active app and Settings the key
    ///   window, as Settings… in a menu does. `--settings` passes `false`: the
    ///   window comes to the front without taking the keyboard from the app in
    ///   use, and becomes key when clicked.
    public func show(pane: SettingsPane?, activate: Bool = true) {
        navigation.open(pane)
        let window = window ?? makeWindow()
        self.window = window
        if activate {
            // Hum is a menu-bar app, so it has to come forward for its window
            // to. It stays one: activating gives it no Dock icon.
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        // Activation can be declined while another app is in use; the window
        // still comes to the front.
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let content = services.inject(
            SettingsView()
                .environment(navigation)
                .environment(settings)
                .environment(store)
                .environment(\.playerActions, actions)
        )
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        // The pane's `navigationTitle` becomes the window's title, in its toolbar.
        controller.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: SettingsMetrics.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Hum Settings"
        window.identifier = Self.windowIdentifier
        // A unified toolbar with the pane's name, and the sidebar running up
        // beside it, as in System Settings.
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        // The panes add no toolbar items, so SwiftUI makes no toolbar, and
        // without one macOS 15 centers the title over the detail column. An
        // empty toolbar puts it leading in the unified bar, as System Settings
        // has it; SwiftUI still fills in the sidebar's part.
        window.toolbar = NSToolbar()
        // Size before centering: the hosting controller sizes the window only once
        // its view loads, and centering an empty window puts the real one off-center.
        window.setContentSize(controller.view.fittingSize)
        ClearOfPlayer.center(window)
        let launchAppearance = LaunchOptions.current.appearance
        observeChanges { [weak self, weak window] in
            guard let self, let window else { return }
            // Follows Hum's Light, Dark, or System choice, like the player.
            window.appearance = switch launchAppearance ?? self.settings.appearance.mode {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
        return window
    }
}
