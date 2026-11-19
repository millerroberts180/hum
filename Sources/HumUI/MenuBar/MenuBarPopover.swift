import AppKit
import HumCore
import SwiftUI

/// The Menu Bar style's Now Playing popover (DESIGN.md §7.1): a system
/// `.transient` popover under the status item, holding `MenuBarNowView` with
/// the player's environment. Esc or a click outside closes it.
///
/// Hum is an agent app that's never frontmost, so the popover comes forward
/// with it for as long as it's open, which is what takes Esc; once it closes,
/// the app that was in front gets the keyboard back.
public final class MenuBarPopover: NSObject, NSPopoverDelegate {
    /// Called when the popover opens or closes, for the item's highlight.
    public var onShownChange: ((Bool) -> Void)?

    private let popover = NSPopover()
    private let interaction = PlayerInteraction()
    /// The app that was in front when the popover opened, to hand the
    /// keyboard back to.
    private var previousApp: NSRunningApplication?

    public init(
        store: NowPlayingStore,
        settings: SettingsStore,
        actions: PlayerActions,
        services: AppServices,
        popOut: @escaping @MainActor () -> Void
    ) {
        super.init()
        // The popover's controls always show; it's never hovered into.
        interaction.alwaysReveal = true
        interaction.isPresented = true
        interaction.isWindowVisible = true
        let host = NSHostingController(rootView: MenuBarPopoverContent(
            store: store,
            settings: settings,
            pager: SurfacePager(surface: .now),
            interaction: interaction,
            actions: actions,
            services: services,
            popOut: popOut
        ))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        let launchAppearance = LaunchOptions.current.appearance
        observeChanges { [weak self, weak settings] in
            guard let self, let settings else { return }
            // Follows Hum's Light, Dark, or System choice, like the player.
            self.popover.appearance = switch launchAppearance ?? settings.appearance.mode {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    public var isShown: Bool { popover.isShown }

    /// Open the popover under `view` (the status item's button), or close it
    /// if it's open.
    public func toggle(relativeTo view: NSView) {
        if popover.isShown {
            close()
        } else {
            show(relativeTo: view)
        }
    }

    public func show(relativeTo view: NSView) {
        guard !popover.isShown else { return }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        NSApp.activate()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        interaction.isPresented = true
        onShownChange?(true)
    }

    public func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    // MARK: NSPopoverDelegate

    public func popoverDidClose(_ notification: Notification) {
        interaction.closePopover()
        onShownChange?(false)
        // Hand the keyboard back, unless another of Hum's windows (Settings,
        // History) is open and the user is working there.
        let hasOtherWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if let previousApp, !hasOtherWindow, NSApp.isActive {
            previousApp.activate()
        }
        previousApp = nil
    }
}

/// The popover's root view, with the player's shared objects in its
/// environment, as `PlayerWindowContent` has them.
struct MenuBarPopoverContent: View {
    let store: NowPlayingStore
    let settings: SettingsStore
    let pager: SurfacePager
    let interaction: PlayerInteraction
    let actions: PlayerActions
    let services: AppServices
    let popOut: @MainActor () -> Void

    var body: some View {
        services.inject(
            MenuBarNowView(popOut: popOut)
                .modifier(PlayerLookProvider())
                .environment(store)
                .environment(settings)
                .environment(pager)
                .environment(interaction)
                .environment(\.playerActions, actions)
        )
    }
}
