import Carbon.HIToolbox
import HumCore
import HumUI
import os

/// System-wide shortcuts through Carbon's hot key API.
///
/// `RegisterEventHotKey` is still the supported way to claim a global key chord
/// on macOS. Unlike an event tap or a global key monitor it needs no
/// Accessibility or Input Monitoring permission, it only ever sees the chords it
/// registered (never other typing), and the system rejects a chord another app
/// already owns instead of letting two apps fight over it.
final class GlobalHotKeyCenter {
    /// The raw values are the hot key identifiers. 1 was Find's, retired with it.
    enum Action: UInt32, CaseIterable {
        case togglePlayer = 2
    }

    var onAction: ((Action) -> Void)?
    /// After each registration, with the actions that have no working chord.
    var onAvailabilityChange: ((Set<Action>) -> Void)?

    /// Unregister everything while the shortcut recorder is listening, so the
    /// current chord can be typed into it.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            isSuspended ? unregisterAll() : apply()
        }
    }

    /// Actions whose chord couldn't be registered (usually because another app owns it).
    private(set) var unavailable: Set<Action> = []

    private var handler: EventHandlerRef?
    private var registered: [Action: EventHotKeyRef] = [:]
    private var chords: [Action: HotKeyChord] = [:]
    private static let signature: OSType = 0x68756D21 // "hum!"
    private let log = HumLog.app

    isolated deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    func install() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &spec, context, &handler)
        if status != noErr {
            log.error("Couldn't install the hot key handler: \(status)")
        }
    }

    /// Register the chords in `shortcuts`, replacing whatever was registered.
    func register(_ shortcuts: ShortcutSettings) {
        var next: [Action: HotKeyChord] = [:]
        next[.togglePlayer] = shortcuts.togglePlayer
        guard next != chords else { return }
        chords = next
        if !isSuspended {
            apply()
        }
    }

    func unregisterAll() {
        for reference in registered.values {
            UnregisterEventHotKey(reference)
        }
        registered = [:]
    }

    private func apply() {
        unregisterAll()
        unavailable = []
        // macOS acts on its own shortcuts first, so one registered on top of
        // them would register fine and never fire.
        let system = SystemShortcuts.current()
        for (action, chord) in chords where chord.isValidGlobalShortcut {
            if SystemShortcuts.contains(chord, in: system) {
                unavailable.insert(action)
                log.notice("\(chord.displayString, privacy: .public) is a macOS shortcut; \(String(describing: action), privacy: .public) has no global shortcut")
                continue
            }
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(chord.keyCode, chord.carbonModifiers, identifier, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                registered[action] = reference
            } else {
                unavailable.insert(action)
                log.notice("\(chord.displayString, privacy: .public) is taken; \(String(describing: action), privacy: .public) has no global shortcut")
            }
        }
        onAvailabilityChange?(unavailable)
    }

    fileprivate func handle(_ identifier: EventHotKeyID) -> Bool {
        guard identifier.signature == Self.signature, let action = Action(rawValue: identifier.id) else { return false }
        onAction?(action)
        return true
    }
}

/// Carbon calls this on the main thread, from the application event loop.
nonisolated private func hotKeyPressed(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(context).takeUnretainedValue()
    let handled = MainActor.assumeIsolated { center.handle(identifier) }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}

private extension HotKeyChord {
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
