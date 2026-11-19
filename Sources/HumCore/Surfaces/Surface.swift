/// The three pages of the player, in swipe order.
public enum Surface: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The current track: artwork, progress, and controls.
    case now
    /// A small, personal view of the current song and session.
    case echo
    /// Which music app Hum follows, and whether each one lets Hum control it.
    case status

    public var id: String { rawValue }

    /// Also reads the names settings saved before: `"pulse"`, before the
    /// surface became `echo`, and `"play"` and `"find"`, the surfaces that were
    /// removed, which open on Now (DESIGN.md §13.9).
    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        guard let surface = Surface(storedValue: rawValue) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown surface \(rawValue)"))
        }
        self = surface
    }

    /// The surface a stored or typed name stands for, including the old names.
    public init?(storedValue: String) {
        switch storedValue {
        case "pulse": self = .echo
        case "play", "find": self = .now
        default: self.init(rawValue: storedValue)
        }
    }

    public var index: Int {
        Surface.allCases.firstIndex(of: self)!
    }

    public init?(index: Int) {
        guard Surface.allCases.indices.contains(index) else { return nil }
        self = Surface.allCases[index]
    }

    public var title: String {
        switch self {
        case .now: "Now"
        // The History page (DESIGN.md §13.23); it keeps `echo` wherever it's
        // stored or named in code.
        case .echo: "History"
        case .status: "Status"
        }
    }

    /// An SF Symbol name.
    public var systemImage: String {
        switch self {
        case .now: "play.circle"
        case .echo: "waveform.path"
        case .status: "antenna.radiowaves.left.and.right"
        }
    }
}
