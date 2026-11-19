import HumCore

/// The song's items in its menu, shared by right-click and the More button
/// (DESIGN.md §4.4): Play Now, then Favorite, then Copy Link and Show in App,
/// with a separator between groups.
///
/// Pure, so the order and the capability rules can be tested: actions the source
/// can't do are left out rather than disabled, and separators between empty groups
/// collapse. The player's own section follows it on the player (`PlayerMenu`).
nonisolated struct TrackMenu: Equatable, Sendable {
    enum Context: Equatable, Sendable {
        /// The playing song, on Now. Play Now has nothing to do there.
        case now
        /// A song on the History page or in the Listening History window.
        case history
    }

    enum Action: Hashable, Sendable {
        case playNow
        case toggleSave
        case copyLink
        /// Show in App: the music app comes forward with the song shown.
        case reveal
    }

    enum Entry: Hashable, Sendable {
        case action(Action)
        case separator
    }

    var entries: [Entry]
    var isSaved: Bool

    /// - Parameter canPlay: Whether the source can start this song, for Play
    ///   Now on the History page and in the Listening History window.
    init(capabilities: SourceCapabilities, isSaved: Bool, context: Context, canPlay: Bool = true) {
        self.isSaved = isSaved
        func when(_ capability: SourceCapabilities, _ action: Action) -> [Action] {
            capabilities.contains(capability) ? [action] : []
        }
        let playNow: [Action] = context == .history && capabilities.canPlayItems && canPlay ? [.playNow] : []
        // Favorite on Now is the playing song's; for History's songs it needs a
        // source that can save any song (Music and the demo, §1.3).
        let save = context == .now ? when(.favorite, .toggleSave) : when(.saveItems, .toggleSave)
        let sections: [[Action]] = [
            playNow,
            save,
            when(.shareLink, .copyLink) + when(.reveal, .reveal),
        ]
        entries = sections
            .filter { !$0.isEmpty }
            .map { $0.map(Entry.action) }
            .reduce(into: []) { result, section in
                if !result.isEmpty { result.append(.separator) }
                result.append(contentsOf: section)
            }
    }

    var isEmpty: Bool { entries.isEmpty }

    var actions: [Action] {
        entries.compactMap { if case .action(let action) = $0 { action } else { nil } }
    }

    /// Never names the music app (§10).
    func title(for action: Action) -> String {
        switch action {
        case .playNow: "Play Now"
        case .toggleSave: SaveVocabulary.title(isSaved: isSaved)
        case .copyLink: "Copy Link"
        case .reveal: Self.revealTitle
        }
    }

    static let revealTitle = "Show in App"
}

/// The player's section of its menu, after the song's items (DESIGN.md §4.4):
/// Style ▸, Pin to ▸, Show ▸, Move to Menu Bar, then Hide Player. Pure, so the
/// order, titles and checks can be tested.
nonisolated struct PlayerMenu: Equatable, Sendable {
    /// The style the player shows, checked under Style ▸.
    var style: PlayerStyleID
    /// Where the player is pinned, checked under Pin to ▸; nil before it's placed.
    var pin: PinPosition?
    /// The surface showing, checked under Show ▸.
    var surface: Surface

    static let styleTitle = "Style"
    static let pinTitle = "Pin to"
    static let showTitle = "Show"
    static let moveToMenuBarTitle = "Move to Menu Bar"
    static let hidePlayerTitle = "Hide Player"

    /// Style ▸'s items: the window styles in §7 order.
    static var styles: [PlayerStyleID] { PlayerStyleID.windowStyles }

    /// Pin to ▸'s three groups: top, middle and bottom.
    static var pinGroups: [[PinPosition]] { PinPosition.rows }

    /// Show ▸'s items, in page order.
    static let surfaces: [Surface] = [.now, .echo, .status]

    /// "Now", "History", "Status".
    static func title(for surface: Surface) -> String {
        switch surface {
        case .now: "Now"
        case .echo: "History"
        case .status: "Status"
        }
    }

    /// The shortcut Show ▸ lists beside each surface: ⌘1, ⌘2, ⌘3.
    static func shortcutDigit(for surface: Surface) -> Character {
        switch surface {
        case .now: "1"
        case .echo: "2"
        case .status: "3"
        }
    }

    /// Pin to ▸'s symbols, shown on macOS 26 only: the place on the screen.
    static func symbol(for pin: PinPosition) -> String {
        switch pin {
        case .topLeft: "rectangle.inset.topleft.filled"
        case .top: "rectangle.tophalf.inset.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .left: "rectangle.lefthalf.inset.filled"
        case .center: "rectangle.center.inset.filled"
        case .right: "rectangle.righthalf.inset.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        }
    }
}
