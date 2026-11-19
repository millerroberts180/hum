import HumCore

/// What a key press in the player does (DESIGN.md §4.3).
///
/// Pure: the window turns an `NSEvent` into a `KeyPress` and this decides.
/// - While a text field is being edited, only Command shortcuts are taken, so
///   typing (and Space, arrows, and Escape) belongs to the field.
/// - While a button or slider has keyboard focus, Space, Return, and the bare
///   arrows belong to it.
/// - While a popover is open, Escape closes it rather than the player.
///
/// Find's keys (⌘K, ⌘F) and Play's (⌘L, ⌘↩, ⌥↩) went with them (§13.9).
nonisolated enum PlayerKeyCommand: Equatable, Sendable {
    /// ⌘1–⌘3: Now, Echo, Status.
    case showSurface(Surface)
    case nextSurface
    case previousSurface
    case openSettings
    /// Escape: back to Now (shrinking a short style back to its shape), or
    /// out of the way if already there.
    case dismiss
    /// Escape with a popover open, such as the volume slider: close it, and
    /// focus goes back to the button that opened it.
    case closePopover
    case hidePlayer
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    /// ⌥⇧B: Favorite, where the source can save the playing song.
    case toggleFavorite

    struct KeyPress: Equatable, Sendable {
        var keyCode: UInt16
        /// The character the key produces without modifiers, lowercased.
        var character: String
        var modifiers: HotKeyChord.Modifiers
    }

    /// Virtual key codes for keys matched by position rather than character.
    enum KeyCode {
        static let b: UInt16 = 11
        static let returnKey: UInt16 = 36
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
        /// The number row's 1 through 3.
        static let digits: [UInt16] = [18, 19, 20]
    }

    static func resolve(
        _ key: KeyPress,
        isEditingText: Bool,
        controlHasFocus: Bool = false,
        popoverIsOpen: Bool = false
    ) -> PlayerKeyCommand? {
        let command = key.modifiers == [.command]
        let plain = key.modifiers.isEmpty

        if command {
            if let index = KeyCode.digits.firstIndex(of: key.keyCode) ?? ["1", "2", "3"].firstIndex(of: key.character),
               let surface = Surface(index: index) {
                return .showSurface(surface)
            }
            switch key.character {
            case ",": return .openSettings
            case "w": return .hidePlayer
            default: break
            }
        }

        guard !isEditingText else { return nil }

        if command {
            switch key.keyCode {
            case KeyCode.leftArrow: return .previousTrack
            case KeyCode.rightArrow: return .nextTrack
            case KeyCode.upArrow: return .volumeUp
            case KeyCode.downArrow: return .volumeDown
            default: return nil
            }
        }

        if key.modifiers == [.option, .shift], key.keyCode == KeyCode.b || key.character == "b" {
            return .toggleFavorite
        }

        guard plain else { return nil }
        if key.keyCode == KeyCode.escape { return popoverIsOpen ? .closePopover : .dismiss }
        guard !controlHasFocus else { return nil }
        switch key.keyCode {
        case KeyCode.leftArrow: return .previousSurface
        case KeyCode.rightArrow: return .nextSurface
        case KeyCode.space: return .playPause
        default: return nil
        }
    }
}
