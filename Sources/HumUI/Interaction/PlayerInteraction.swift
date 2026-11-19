import AppKit
import HumCore
import Observation
import SwiftUI

/// Whether the player's controls should be showing, and why.
///
/// Controls reveal for the pointer, for keyboard use, while scrubbing, and always
/// for VoiceOver (hidden controls would be unreachable). Leaving the window
/// conceals them at once (DESIGN.md §4.1); coming back mid-fade turns the fade
/// around.
@MainActor
@Observable
public final class PlayerInteraction {
    public private(set) var isPointerInside = false
    /// The user is driving the player from the keyboard.
    public var isKeyboardEngaged = false
    public var isScrubbing = false
    /// Keep controls showing regardless (setting or launch option).
    public var alwaysReveal = false
    public private(set) var isVoiceOverRunning = NSWorkspace.shared.isVoiceOverEnabled
    /// The window is on screen and not fully covered. Timelines pause otherwise.
    public var isWindowVisible = false
    /// The window is showing or on its way in. The content scales and sharpens
    /// into place toward `presentationAnchor` as this turns on, and back as it
    /// turns off.
    public internal(set) var isPresented = false
    /// The corner or edge the window materializes from: the one nearest the
    /// screen edge it sits against.
    var presentationAnchor: UnitPoint = .center
    /// A button or slider has keyboard focus, so Space, Return, and the arrows
    /// belong to it rather than to the player's shortcuts.
    public var isControlFocused: Bool { focusedControl != nil }
    private var focusedControl: UUID?
    /// A popover is open over the player, so Escape closes it first.
    var isPopoverOpen: Bool { openPopover != nil }
    private var openPopover: UUID?
    /// Increments each time Escape asks the open popover to close.
    private(set) var popoverCloseRequestCount = 0
    /// The level the volume HUD shows, or nil while it's hidden.
    private(set) var volumeHUDLevel: Double?
    /// Where on Now a vertical two-finger swipe sets the volume: the cover, in
    /// the window's top-left coordinates. Nil when Now shows no cover.
    @ObservationIgnored var volumeSwipeArea: CGRect?

    @ObservationIgnored private var volumeHUDTask: Task<Void, Never>?
    @ObservationIgnored private var voiceOverObservation: NSKeyValueObservation?
    /// Called when the pointer or keyboard engagement changes, for auto-hide timing.
    @ObservationIgnored public var onEngagementChange: (@MainActor () -> Void)?
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    /// - Parameter sleep: How the HUD's hold is waited out; tests pass their own.
    public init(sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled) { [weak self] workspace, _ in
            let enabled = workspace.isVoiceOverEnabled
            Task { @MainActor in self?.isVoiceOverRunning = enabled }
        }
    }

    /// An open popover holds the controls: it's a window of its own, so
    /// pointing at it leaves the player.
    public var isRevealed: Bool {
        alwaysReveal || isPointerInside || isKeyboardEngaged || isScrubbing || isPopoverOpen || isVoiceOverRunning
    }

    /// The user is actively using the player, so it shouldn't hide itself.
    public var isEngaged: Bool {
        isPointerInside || isKeyboardEngaged || isScrubbing || isPopoverOpen
    }

    public func pointerEntered() {
        guard !isPointerInside else { return }
        isPointerInside = true
        onEngagementChange?()
    }

    public func pointerExited() {
        guard isPointerInside else { return }
        isPointerInside = false
        onEngagementChange?()
    }

    /// Record a control gaining or losing focus. A control losing focus only
    /// clears it if it still holds it, since the next control may report first.
    func setControlFocused(_ focused: Bool, token: UUID) {
        if focused {
            focusedControl = token
        } else if focusedControl == token {
            focusedControl = nil
        }
    }

    /// Record a popover opening or closing, with the same rule as focus.
    func setPopoverOpen(_ open: Bool, token: UUID) {
        let wasOpen = isPopoverOpen
        if open {
            openPopover = token
        } else if openPopover == token {
            openPopover = nil
        }
        if isPopoverOpen != wasOpen { onEngagementChange?() }
    }

    /// Show the volume HUD at `level`, concealing it once the volume has held
    /// still for `Motion.hudHold`.
    func showVolumeHUD(level: Double) {
        volumeHUDLevel = min(1, max(0, level))
        volumeHUDTask?.cancel()
        let sleep = sleep
        volumeHUDTask = Task { [weak self] in
            try? await sleep(Motion.hudHold)
            guard !Task.isCancelled, let self else { return }
            self.volumeHUDLevel = nil
        }
    }

    /// Put the volume HUD away now, for a newer HUD.
    func hideVolumeHUD() {
        volumeHUDTask?.cancel()
        volumeHUDTask = nil
        volumeHUDLevel = nil
    }

    func closePopover() {
        guard isPopoverOpen else { return }
        popoverCloseRequestCount += 1
    }

    public func setKeyboardEngaged(_ engaged: Bool) {
        guard engaged != isKeyboardEngaged else { return }
        isKeyboardEngaged = engaged
        onEngagementChange?()
    }
}
