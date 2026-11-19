/// One of the nine places the player can be pinned on a display, named as macOS's
/// Window › Move & Resize commands name them (DESIGN.md §4.5).
public enum PinPosition: String, Codable, Sendable, CaseIterable, Identifiable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .topLeft: "Top Left"
        case .top: "Top"
        case .topRight: "Top Right"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomLeft: "Bottom Left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom Right"
        }
    }

    /// Where the position sits horizontally: -1 leading, 0 middle, 1 trailing.
    public var column: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: -1
        case .top, .center, .bottom: 0
        case .topRight, .right, .bottomRight: 1
        }
    }

    /// Where the position sits vertically: 1 top, 0 middle, -1 bottom.
    public var row: Int {
        switch self {
        case .topLeft, .top, .topRight: 1
        case .left, .center, .right: 0
        case .bottomLeft, .bottom, .bottomRight: -1
        }
    }

    /// The top position in the same column, where Under Menu Bar tucks the player.
    public var tuckPosition: PinPosition {
        switch column {
        case -1: .topLeft
        case 0: .top
        default: .topRight
        }
    }

    /// The menu's three groups: the top row, the middle row, the bottom row.
    public static let rows: [[PinPosition]] = [
        [.topLeft, .top, .topRight],
        [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight],
    ]

    /// Where a player with no pin yet starts.
    public static let initial = PinPosition.topRight
}
