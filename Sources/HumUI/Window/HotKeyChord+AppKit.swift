import AppKit
import HumCore

extension HotKeyChord.Modifiers {
    /// The Control, Option, Shift, and Command keys held in `flags`. Caps Lock,
    /// Fn, and the numeric-pad flag are ignored.
    public init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: HotKeyChord.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}

extension PlayerKeyCommand.KeyPress {
    init(_ event: NSEvent) {
        self.init(
            keyCode: event.keyCode,
            character: (event.charactersIgnoringModifiers ?? "").lowercased(),
            modifiers: HotKeyChord.Modifiers(event.modifierFlags)
        )
    }
}

extension HotKeyChord {
    /// The chord as a menu item's key equivalent, so a menu can show a shortcut
    /// the user set in Settings. `nil` for a key a menu can't show.
    public var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard let key = Self.menuKey(for: keyLabel) else { return nil }
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return (key, flags)
    }

    static func menuKey(for label: String) -> String? {
        func function(_ key: Int) -> String? {
            UnicodeScalar(key).map { String(Character($0)) }
        }
        switch label {
        case "Space": return " "
        case "↩": return "\r"
        case "⇥": return "\t"
        case "←": return function(NSLeftArrowFunctionKey)
        case "→": return function(NSRightArrowFunctionKey)
        case "↑": return function(NSUpArrowFunctionKey)
        case "↓": return function(NSDownArrowFunctionKey)
        default:
            if label.count > 1, label.first == "F", let number = Int(label.dropFirst()), (1...20).contains(number) {
                return function(NSF1FunctionKey + number - 1)
            }
            return label.count == 1 ? label.lowercased() : nil
        }
    }
}
