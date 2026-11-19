/// The curated player styles (DESIGN.md §7). `NowStyleSwitch` picks each one's
/// Now layout; see the Styles section of docs/ARCHITECTURE.md.
///
/// Text and Strip were called Minimal and Compact before the 2026-11-07
/// redesign; their stored values stay `minimal` and `compact` so saved settings
/// carry over. Glass, Data and Session were retired on 2026-11-08 (§13.19); a
/// saved `glass`, `data` or `session` no longer decodes, so it opens as the
/// default, Art Only.
public enum PlayerStyleID: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The cover alone; everything appears on hover.
    case artOnly
    /// A short bar: the cover with the title and artist, controls on hover.
    case title
    /// A capsule of words: the title and artist, the transport on hover.
    case text = "minimal"
    /// A slim bar: the cover, a seek notch, and the transport, always shown.
    case strip = "compact"
    /// A landscape card: the cover at the leading edge, the title and every
    /// control beside it, always shown.
    case wide
    /// A portrait card: the cover inset on it, the same controls below it.
    /// Rebuilt on 2026-11-09 (§13.29); the stored value stays `bigArt`.
    case bigArt
    /// No window: the player lives in the menu bar (DESIGN.md §7.1).
    case menuBar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .artOnly: "Art Only"
        case .title: "Title"
        case .text: "Text"
        case .strip: "Strip"
        case .wide: "Wide"
        case .bigArt: "Big Art"
        case .menuBar: "Menu Bar"
        }
    }

    /// Whether the style shows the player in a window. Menu Bar doesn't.
    public var hasWindow: Bool { self != .menuBar }

    /// The styles that show a window, in display order: the Style ▸ menu's items.
    public static var windowStyles: [PlayerStyleID] { allCases.filter(\.hasWindow) }
}
