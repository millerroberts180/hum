import Carbon.HIToolbox
import HumCore
import Observation

/// Which global shortcuts macOS turned down, as the app last heard when it
/// registered them. Settings reads it to say why a shortcut doesn't work.
@Observable
public final class GlobalShortcutStatus {
    public enum Action: Hashable, Sendable {
        case togglePlayer
    }

    public private(set) var unavailable: Set<Action> = []

    public init() {}

    /// Called by the app after each registration.
    public func update(unavailable: Set<Action>) {
        guard unavailable != self.unavailable else { return }
        self.unavailable = unavailable
    }
}

/// Why a recorded shortcut can't be used. The recorder keeps the previous one
/// and says which of these it was (DESIGN.md §10: plain and factual).
nonisolated enum ShortcutConflict: Equatable, Sendable {
    /// One of Hum's other global shortcuts, which a new one mustn't repeat.
    struct Taken: Sendable {
        var chord: HotKeyChord
        /// Finishes "already …", as in "shows or hides the player".
        var what: String
    }

    /// Hum's other global shortcut has it.
    case otherShortcut(what: String)
    /// A key inside the player; as a global shortcut it would stop working there.
    case player
    /// macOS or another app has it, so it couldn't be registered.
    case unavailable

    /// The clash Hum can see before trying: the other global shortcut, or a
    /// key the player uses (DESIGN.md §4.3).
    static func check(
        _ chord: HotKeyChord,
        character: String,
        others: [Taken]
    ) -> ShortcutConflict? {
        if let other = others.first(where: { $0.chord.keyCode == chord.keyCode && $0.chord.modifiers == chord.modifiers }) {
            return .otherShortcut(what: other.what)
        }
        let press = PlayerKeyCommand.KeyPress(
            keyCode: UInt16(truncatingIfNeeded: chord.keyCode),
            character: character.lowercased(),
            modifiers: chord.modifiers
        )
        if PlayerKeyCommand.resolve(press, isEditingText: false) != nil {
            return .player
        }
        return nil
    }

    /// The line under the recorder: what went wrong, then what's still set.
    func message(for chord: HotKeyChord, keeping previous: HotKeyChord?) -> String {
        let reason = switch self {
        case .otherShortcut(let what): "\(chord.displayString) already \(what)."
        case .player: "\(chord.displayString) is already used in the player."
        case .unavailable: "\(chord.displayString) is in use by macOS or another app."
        }
        let kept = previous.map { "\($0.displayString) is still the shortcut." } ?? "No shortcut is set."
        return "\(reason) \(kept)"
    }

    /// The line under the recorder when the saved shortcut itself is turned
    /// down, for instance by an app opened since it was set.
    static func unavailableMessage(for chord: HotKeyChord) -> String {
        "\(chord.displayString) is in use by macOS or another app, so it doesn’t work right now."
    }
}

/// The system-wide shortcuts macOS has turned on (Spotlight, screenshots,
/// Mission Control, and so on), from `CopySymbolicHotKeys`. The system acts on
/// these before any app, so a hot key registered on top of one never fires.
nonisolated public enum SystemShortcuts {
    public struct Entry: Hashable, Sendable {
        public var keyCode: UInt32
        public var modifiers: HotKeyChord.Modifiers

        public init(keyCode: UInt32, modifiers: HotKeyChord.Modifiers) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// From the Carbon modifier bits the system reports. The function-key
        /// bit is left out: F-keys carry it, and a recorded chord never does.
        init(keyCode: UInt32, carbonModifiers: Int) {
            var modifiers: HotKeyChord.Modifiers = []
            if carbonModifiers & cmdKey != 0 { modifiers.insert(.command) }
            if carbonModifiers & optionKey != 0 { modifiers.insert(.option) }
            if carbonModifiers & controlKey != 0 { modifiers.insert(.control) }
            if carbonModifiers & shiftKey != 0 { modifiers.insert(.shift) }
            self.init(keyCode: keyCode, modifiers: modifiers)
        }
    }

    /// The enabled system shortcuts right now. Main thread only; not cheap, so
    /// once per registration rather than per chord.
    @MainActor
    public static func current() -> Set<Entry> {
        var copied: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&copied) == noErr,
              let dictionaries = copied?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return entries(from: dictionaries)
    }

    /// The enabled entries of a `CopySymbolicHotKeys` result.
    static func entries(from dictionaries: [[String: Any]]) -> Set<Entry> {
        var result: Set<Entry> = []
        for dictionary in dictionaries {
            guard (dictionary[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = dictionary[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = dictionary[kHISymbolicHotKeyModifiers as String] as? Int,
                  // Entries without a key use 0xFFFF.
                  code >= 0, code < 0xFFFF else { continue }
            result.insert(Entry(keyCode: UInt32(code), carbonModifiers: modifiers))
        }
        return result
    }

    public static func contains(_ chord: HotKeyChord, in entries: Set<Entry>) -> Bool {
        entries.contains(Entry(keyCode: chord.keyCode, modifiers: chord.modifiers))
    }
}
