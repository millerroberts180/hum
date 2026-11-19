/// Where the accent color (active toggles, the filled Save glyph, focus details)
/// comes from.
public enum AccentSource: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The accent chosen in System Settings.
    case system
    /// The current cover's palette accent; System for covers without one.
    case album
    /// A color the user picked.
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .album: "Album"
        case .custom: "Custom"
        }
    }
}
