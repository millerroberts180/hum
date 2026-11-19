import AppKit
import HumCore
import HumUI

/// The menu-bar item: the app's only permanent presence (DESIGN.md §5.8).
///
/// Hum's Vibrato mark as a template image, dimmed when no music app is
/// available. Its menu is lean and rebuilt each time it opens, so it always
/// reflects the current song without observing anything in between: the song,
/// the transport, Show Player (Hide Player while it shows), Listening History…,
/// Settings, and Quit.
///
/// In the Menu Bar style (§7.1) the item is the player: the cover, the title,
/// play/pause and next. A click opens the Now Playing popover; a right-click or
/// Control-click opens the lean menu, with Pop Out Player in place of Show
/// Player.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let store: NowPlayingStore
    private let settings: SettingsStore
    private let player: PlayerWindowController
    private let openSettings: () -> Void
    private let openHistory: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let playerItem = MenuBarPlayerItemView()
    /// The Menu Bar style's popover, made the first time it opens.
    private var popover: MenuBarPopover?
    private let makePopover: (_ popOut: @escaping @MainActor () -> Void) -> MenuBarPopover
    /// What the item last drew: the mark (and whether a music app was
    /// available), or the Menu Bar player.
    private var shownLook: Look?
    /// The Toggle Player shortcut, shown on Show Player only once the user has
    /// set one in Settings.
    var togglePlayerShortcut: (() -> HotKeyChord?)?
    /// Hides the item while Line Apps has the family collapsed into its line.
    /// The Menu Bar style's popover closes as it goes, having nothing to hang from.
    private lazy var lineFold = LineAppsFold(
        setHidden: { [weak self] hidden in
            if hidden { self?.popover?.close() }
            self?.statusItem.isVisible = !hidden
        },
        button: { [weak self] in self?.statusItem.button },
        name: { [weak self] in self?.statusItem.autosaveName }
    )

    private enum Look: Equatable {
        case mark(available: Bool)
        case player
    }

    init(
        store: NowPlayingStore,
        settings: SettingsStore,
        player: PlayerWindowController,
        openSettings: @escaping () -> Void,
        openHistory: @escaping () -> Void,
        makePopover: @escaping (_ popOut: @escaping @MainActor () -> Void) -> MenuBarPopover
    ) {
        self.store = store
        self.settings = settings
        self.player = player
        self.openSettings = openSettings
        self.openHistory = openHistory
        self.makePopover = makePopover
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(itemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            playerItem.embed(in: button)
        }
        playerItem.onPlayPause = { [weak self] in self?.send(.togglePlayPause) }
        playerItem.onNext = { [weak self] in self?.send(.next) }
        refreshStatusItem()
        observeChanges { [weak self] in
            self?.refreshStatusItem()
        }
        lineFold.start()
    }

    /// Whether the player lives here rather than in a window (§7.1).
    private var isMenuBarStyle: Bool { !settings.appearance.style.hasWindow }

    /// Whether Line Apps has the item collapsed into its line.
    var isCollapsedIntoLine: Bool { lineFold.isFolded }

    /// Where the item is on screen, for the window to materialize toward.
    var statusItemFrame: CGRect? {
        // Collapsed into Line Apps' line, there is nowhere here to come from.
        lineFold.isFolded ? nil : statusItem.button?.window?.frame
    }

    /// Keep the item current with what's playing and the style.
    func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let track = store.track
        let available = store.activeSource != nil && store.availability != .notInstalled
        let look: Look = isMenuBarStyle && track != nil ? .player : .mark(available: available)
        if look != shownLook {
            shownLook = look
            switch look {
            case .mark(let available):
                // VoiceOver hears that no music app is available.
                button.image = HumMark.templateImage(
                    accessibilityDescription: available ? "Hum" : "Hum, no music app available"
                )
                statusItem.length = NSStatusItem.squareLength
                playerItem.isHidden = true
            case .player:
                button.image = nil
                playerItem.isHidden = false
            }
            button.appearsDisabled = look == .mark(available: false)
        }
        if case .mark(let available) = look {
            button.setAccessibilityLabel(available ? "Hum" : "Hum, no music app available")
        }
        if let track, look == .player {
            let capabilities = store.capabilities
            playerItem.update(
                MenuBarPlayerItemView.Content(
                    title: track.title,
                    artist: track.artist,
                    isPlaying: store.isPlaying,
                    canPlayPause: capabilities.contains(.playPause),
                    canSkip: capabilities.contains(.skipNext)
                ),
                artwork: store.artwork?.cgImage
            )
            statusItem.length = playerItem.preferredWidth
            button.setAccessibilityLabel(MenuBarPlayerItemView.accessibilityLabel(title: track.title, artist: track.artist))
        }
        button.setAccessibilityHelp(isMenuBarStyle ? "Show what’s playing" : "Show the Hum menu")
        button.toolTip = track.map(Self.nowPlayingLine) ?? "Hum"
        // Leaving Menu Bar: the window takes over from the popover.
        if !isMenuBarStyle {
            popover?.close()
        }
    }

    // MARK: Clicks

    /// A click on the item. Outside Menu Bar it opens the lean menu; in Menu
    /// Bar a click opens the popover and a right-click or Control-click the
    /// menu.
    @objc private func itemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = !isMenuBarStyle
            || event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else {
            togglePopover()
        }
    }

    /// The menu, dropped from the item as a status item's menu is.
    private func showMenu() {
        popover?.close()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// The Toggle Player shortcut and Show Player in Menu Bar: open the
    /// popover, or close it if it's open.
    func togglePopover() {
        // Nothing to hang from while collapsed into Line Apps' line.
        guard let button = statusItem.button, !lineFold.isFolded else { return }
        let popover = popover ?? makePopover { [weak self] in self?.popOut() }
        if self.popover == nil {
            popover.onShownChange = { [weak self] shown in
                self?.statusItem.button?.highlight(shown)
            }
            self.popover = popover
        }
        popover.toggle(relativeTo: button)
    }

    /// Pop Out Player: the popover closes and the player comes back in the
    /// style it had before Menu Bar, materializing from here to its pin.
    func popOut() {
        popover?.close()
        Self.popOut(&settings.appearance)
    }

    /// Back to the window style Hum had before Menu Bar (Art Only if none).
    static func popOut(_ appearance: inout AppearanceSettings) {
        guard !appearance.style.hasWindow else { return }
        appearance.style = appearance.lastWindowStyle
    }

    private func send(_ command: PlaybackCommand) {
        guard store.capabilities.supports(command) else { return }
        store.send(command)
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let entry: PlayerEntry = isMenuBarStyle ? .popOut : (player.isVisible ? .hide : .show)
        let items = Self.leanMenuItems(
            track: store.track,
            transport: Transport(
                capabilities: store.capabilities,
                hasTrack: store.track != nil,
                isPlaying: store.isPlaying
            ),
            player: entry,
            shortcut: togglePlayerShortcut?()?.menuKeyEquivalent,
            actions: LeanMenuActions(
                send: { [weak self] in self?.send($0) },
                player: { [weak self] in
                    guard let self else { return }
                    if isMenuBarStyle { popOut() } else { player.toggle() }
                },
                openHistory: { [weak self] in self?.openHistory() },
                openSettings: { [weak self] in self?.openSettings() },
                quit: { NSApp.terminate(nil) }
            )
        )
        for item in items {
            menu.addItem(item)
        }
    }

    // MARK: The lean menu

    /// What the transport items show, read from the store as the menu opens.
    struct Transport {
        var capabilities: SourceCapabilities
        var hasTrack: Bool
        var isPlaying: Bool
    }

    /// The player's item: Show Player, Hide Player while it shows, or Pop
    /// Out Player in Menu Bar.
    enum PlayerEntry {
        case show, hide, popOut

        var title: String {
            switch self {
            case .show: "Show Player"
            case .hide: "Hide Player"
            case .popOut: "Pop Out Player"
            }
        }
    }

    /// What the menu's items do.
    struct LeanMenuActions {
        var send: (PlaybackCommand) -> Void
        var player: () -> Void
        var openHistory: () -> Void
        var openSettings: () -> Void
        var quit: () -> Void
    }

    /// The whole menu, in order (§5.8): the song, the transport, the player's
    /// item and Listening History…, then Settings… and Quit Hum.
    static func leanMenuItems(
        track: Track?,
        transport: Transport,
        player: PlayerEntry,
        shortcut: (key: String, modifiers: NSEvent.ModifierFlags)?,
        actions: LeanMenuActions
    ) -> [NSMenuItem] {
        var items = header(track: track)
        items += transportItems(transport, send: actions.send)
        items.append(.separator())
        let toggle = NSMenuItem(player.title, action: actions.player)
        if let shortcut {
            toggle.keyEquivalent = shortcut.key
            toggle.keyEquivalentModifierMask = shortcut.modifiers
        }
        items.append(toggle)
        items.append(NSMenuItem("Listening History…", action: actions.openHistory))
        items.append(.separator())
        items.append(NSMenuItem("Settings…", key: ",", action: actions.openSettings))
        items.append(NSMenuItem("Quit Hum", key: "q", action: actions.quit))
        return items
    }

    /// "Title — Artist", or the title alone when the source names no artist.
    static func nowPlayingLine(_ track: Track) -> String {
        track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)"
    }

    /// The widest a song line gets, so the menu stays at most about 220 pt
    /// wide whatever the song (§5.8). The menu adds about 75 pt to its widest
    /// title: its insets, and the column for ⌘, and ⌘Q.
    static let songLineWidth: CGFloat = 145

    /// The menu's plain disabled first items, in the system's disabled color as
    /// Apple's own menu info lines are: the title, then the artist, each cut
    /// short with "…" past `songLineWidth`; or Nothing Playing. Both lines show
    /// the whole song as a tooltip. They never name the app (§10).
    static func header(track: Track?) -> [NSMenuItem] {
        guard let track else {
            let nothing = NSMenuItem(title: "Nothing Playing", action: nil, keyEquivalent: "")
            nothing.isEnabled = false
            return [nothing]
        }
        return [track.title, track.artist].filter { !$0.isEmpty }.map { text in
            let shown = truncated(text, toFit: songLineWidth, in: NSFont.menuFont(ofSize: 0))
            let line = NSMenuItem(title: shown, action: nil, keyEquivalent: "")
            line.toolTip = nowPlayingLine(track)
            line.isEnabled = false
            return line
        }
    }

    /// `text` as it fits in `width` in `font`: whole, or cut at the end with
    /// "…".
    static func truncated(_ text: String, toFit width: CGFloat, in font: NSFont) -> String {
        func fits(_ candidate: String) -> Bool {
            (candidate as NSString).size(withAttributes: [.font: font]).width <= width
        }
        guard !fits(text) else { return text }
        let characters = Array(text)
        func cut(keeping count: Int) -> String {
            var kept = String(characters[..<count])
            while kept.last?.isWhitespace == true { kept.removeLast() }
            return kept + "…"
        }
        // The most characters that still fit with the ellipsis.
        var low = 0
        var high = characters.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(cut(keeping: middle)) { low = middle } else { high = middle - 1 }
        }
        return cut(keeping: low)
    }

    /// Play or Pause, Next Track, and Previous Track, as in Music's Controls
    /// menu. Transport the source can't do is hidden, not disabled.
    static func transportItems(_ transport: Transport, send: @escaping (PlaybackCommand) -> Void) -> [NSMenuItem] {
        let capabilities = transport.capabilities
        var items: [NSMenuItem] = []
        if capabilities.contains(.playPause) {
            items.append(NSMenuItem(transport.isPlaying ? "Pause" : "Play") { send(.togglePlayPause) })
        }
        if transport.hasTrack, capabilities.contains(.skipNext) {
            items.append(NSMenuItem("Next Track") { send(.next) })
        }
        if transport.hasTrack, capabilities.contains(.skipPrevious) {
            items.append(NSMenuItem("Previous Track") { send(.previous) })
        }
        return items
    }
}
