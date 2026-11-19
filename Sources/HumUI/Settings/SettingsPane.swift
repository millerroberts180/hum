import Observation

/// The panes of the Settings window, in sidebar order (DESIGN.md §8).
///
/// Anything that wants to send the user to a preference calls
/// `PlayerActions.openSettingsPane` with one of these; the window opens, or comes
/// forward, on that pane.
///
/// The raw values are stored and passed to `--settings`, so they keep the
/// panes' first names: Behavior is `player`, History & Privacy is
/// `echoPrivacy`, and Hum is `about` (§13.27).
nonisolated public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case player
    case shortcuts
    case sources
    case echoPrivacy
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .player: "Behavior"
        case .shortcuts: "Shortcuts"
        case .sources: "Sources"
        case .echoPrivacy: "History & Privacy"
        case .about: "Hum"
        }
    }

    /// The pane `--settings` names: a raw value, or `hum` for the Hum pane.
    public init?(argument: String) {
        if argument == "hum" {
            self = .about
        } else {
            self.init(rawValue: argument)
        }
    }

    /// The pane's glyph, drawn white on its tinted tile in the sidebar.
    public var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .player: "rectangle.inset.filled"
        case .shortcuts: "command"
        case .sources: "music.note"
        case .echoPrivacy: "hand.raised.fill"
        case .about: "info.circle.fill"
        }
    }

    /// One line under the pane title, saying what the pane is for.
    public var summary: String {
        switch self {
        case .general: "Start-up and how Hum fits into your Mac."
        case .appearance: "The player’s style, color, and shape. Each style keeps its own look."
        case .player: "What appears when you reach for the player, and where it lives."
        case .shortcuts: "Keys that work from anywhere, and the keys inside the player."
        case .sources: "The music apps Hum plays from."
        case .echoPrivacy: "What Hum remembers about your listening. It stays on this Mac."
        case .about: "What Hum is, its version, and how to quit it."
        }
    }
}

/// One group of the Settings sidebar: a section header, or none for a pane
/// that stands alone (DESIGN.md §8).
nonisolated public struct SettingsSidebarGroup: Identifiable, Equatable, Sendable {
    public var title: String?
    public var panes: [SettingsPane]

    public var id: SettingsPane { panes[0] }

    public static let general = SettingsSidebarGroup(title: nil, panes: [.general])
    public static let player = SettingsSidebarGroup(title: "Player", panes: [.appearance, .player, .shortcuts])
    public static let music = SettingsSidebarGroup(title: "Music", panes: [.sources, .echoPrivacy])
    public static let hum = SettingsSidebarGroup(title: nil, panes: [.about])

    /// General alone; Player: Appearance, Behavior, Shortcuts; Music: Sources,
    /// History & Privacy; then Hum alone, as System Settings groups its panes.
    public static let all: [SettingsSidebarGroup] = [general, player, music, hum]
}

/// Which pane the Settings window shows. One instance lives as long as the window
/// presenter, so the window reopens where it was left unless a caller asks for a
/// specific pane.
@Observable
public final class SettingsNavigation {
    public var pane: SettingsPane

    public init(pane: SettingsPane = .general) {
        self.pane = pane
    }

    /// Route to `pane`, or stay on the current one when `pane` is `nil`.
    public func open(_ pane: SettingsPane?) {
        if let pane, pane != self.pane {
            self.pane = pane
        }
    }
}
