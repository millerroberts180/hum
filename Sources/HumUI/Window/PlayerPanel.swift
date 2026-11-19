import AppKit

/// The player's window: borderless, floating, and non-activating, so clicking it
/// never pulls focus away from the app the user is working in. It becomes key
/// only once it's been clicked or summoned, so the keyboard works then.
final class PlayerPanel: NSPanel {
    /// Offered every key press first. Return `true` to consume it.
    var keyHandler: ((NSEvent) -> Bool)?
    var onKeyStatusChange: ((Bool) -> Void)?

    /// Whether the panel may take the keyboard. AppKit makes a window that can
    /// become key its app's key window when it's ordered in, and a
    /// non-activating panel that's key gets the keystrokes even while another
    /// app is frontmost. So the player may take the keyboard only after a click
    /// or `allowKeyboard()`, and gives that up once the keyboard goes elsewhere:
    /// appearing on its own (at launch, for a track change) leaves it with the
    /// app the user is typing in.
    private(set) var allowsKeyboard = false

    /// Let the panel take the keyboard, for when the user summons it.
    func allowKeyboard() {
        allowsKeyboard = true
    }

    /// How a right or middle click makes the panel key. Tests watch it.
    var takeKeyForClick: (PlayerPanel) -> Void = { $0.makeKey() }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        animationBehavior = .none
        contentAspectRatio = NSSize(width: 1, height: 1)
        title = "Hum"
        // SwiftUI adds controls after the panel first draws (a page's header
        // buttons, a list's rows). A key-view loop AppKit built only once
        // leaves them out, so Tab would stop short of them.
        autorecalculatesKeyViewLoop = true
    }

    override var canBecomeKey: Bool { allowsKeyboard }
    override var canBecomeMain: Bool { false }

    /// A borderless non-activating panel reads to VoiceOver as a system
    /// dialog, which is an alert's role. The player is a window that floats
    /// (DESIGN.md §9).
    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        .floatingWindow
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if keyHandler?(event) == true { return }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // Before AppKit handles the click, which is when a clicked window
            // becomes key.
            allowsKeyboard = true
            // AppKit does that for a left click only. A right-click is a click
            // too (DESIGN.md §4.5), so typing after it belongs here, not in
            // the app in front.
            if event.type != .leftMouseDown, !isKeyWindow {
                takeKeyForClick(self)
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func becomeKey() {
        super.becomeKey()
        onKeyStatusChange?(true)
    }

    override func resignKey() {
        super.resignKey()
        // Once the new key window is known: one of the player's own (a popover)
        // keeps the permission, so the keyboard can come back when it closes.
        DispatchQueue.main.async { [weak self] in
            guard let self, !isKeyWindow else { return }
            if let key = NSApp.keyWindow, sequence(first: key, next: \.parent).contains(where: { $0 === self }) {
                return
            }
            allowsKeyboard = false
        }
        onKeyStatusChange?(false)
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        allowsKeyboard = false
    }
}
