/// Global shortcuts. `nil` means turned off.
///
/// Find's global shortcut went with Find (DESIGN.md §4.3). A saved one is left
/// out when the settings are read, so it does nothing and is never handed to
/// Toggle Player.
public struct ShortcutSettings: Codable, Equatable, Sendable {
    /// Shows or hides the player. No default.
    public var togglePlayer: HotKeyChord?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case togglePlayer
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        togglePlayer = (try? container.decodeIfPresent(HotKeyChord.self, forKey: .togglePlayer)) ?? nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(togglePlayer, forKey: .togglePlayer)
    }
}
