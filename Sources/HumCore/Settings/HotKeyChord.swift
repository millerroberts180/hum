/// A key plus modifiers, stored as a hardware key code so it works on any layout.
public struct HotKeyChord: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// Symbols in the order macOS menus show them.
        public var symbols: String {
            var result = ""
            if contains(.control) { result += "⌃" }
            if contains(.option) { result += "⌥" }
            if contains(.shift) { result += "⇧" }
            if contains(.command) { result += "⌘" }
            return result
        }
    }

    /// A virtual key code (`kVK_*`).
    public var keyCode: UInt32
    public var modifiers: Modifiers
    /// What the key prints, for display ("K", "Space", "F5").
    public var keyLabel: String

    public init(keyCode: UInt32, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    public var displayString: String {
        modifiers.symbols + keyLabel
    }

    /// A global shortcut needs ⌘, ⌥, or ⌃; shift alone would steal ordinary typing.
    public var isValidGlobalShortcut: Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty
    }
}
