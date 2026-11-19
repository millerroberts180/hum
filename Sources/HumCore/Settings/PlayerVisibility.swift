/// When the player window is on screen. The stored values are the ones from
/// before the titles changed, so saved settings carry over.
public enum PlayerVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Always on screen until the user hides it.
    case pinned
    /// Appears for a few seconds when the track changes, then tucks itself away.
    case trackChanges
    /// Lives under the menu bar: slides down from it when summoned and back up
    /// into it when the user clicks elsewhere.
    case tucked
    /// Hidden until summoned with the shortcut or the menu; hides again when the
    /// user clicks elsewhere.
    case summoned

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pinned: "Always"
        case .trackChanges: "On Track Change"
        case .tucked: "Under Menu Bar"
        case .summoned: "On Request"
        }
    }
}
