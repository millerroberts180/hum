import AppKit
import HumCore
import SwiftUI

extension TrackMenu {
    /// The song's items for the playing song on Now, or `nil` when there's
    /// nothing to show.
    @MainActor
    static func current(_ store: NowPlayingStore) -> TrackMenu? {
        guard store.track != nil, store.activeSource != nil else { return nil }
        let menu = TrackMenu(
            capabilities: store.capabilities,
            isSaved: store.snapshot.isFavorite ?? false,
            context: .now
        )
        return menu.isEmpty ? nil : menu
    }

    /// The menu for a song on the History page or in the Listening History
    /// window (§4.4). Play Now is left out for a song the source can't start,
    /// such as one imported from elsewhere, and Copy Link and Show in App for
    /// one the app can't point at.
    @MainActor
    static func song(_ track: LibraryTrack, library: LibraryStore, request: PlayRequest? = nil) -> TrackMenu {
        var capabilities = library.capabilities
        if let id = library.sourceID, let source = library.nowPlaying.source(for: id) {
            let appCapabilities = library.nowPlaying.sourceStates[id]?.capabilities ?? []
            let song = Track(track)
            if appCapabilities.contains(.shareLink), source.shareLink(for: song) != nil {
                capabilities.insert(.shareLink)
            }
            if appCapabilities.contains(.reveal), source.revealURL(for: song) != nil {
                capabilities.insert(.reveal)
            }
        }
        let request = request ?? .track(track, in: nil)
        return TrackMenu(
            capabilities: capabilities,
            isSaved: library.isSaved(track),
            context: .history,
            canPlay: library.playBlocker(for: request) == nil
        )
    }

    /// The items as `NSMenuItem`s, for the More button.
    @MainActor
    func nsItems(perform: @escaping @MainActor (Action) -> Void) -> [NSMenuItem] {
        entries.map { entry in
            switch entry {
            case .separator: .separator()
            case .action(let action): NSMenuItem(title: title(for: action)) { perform(action) }
            }
        }
    }

    /// An `NSMenu` with the same items.
    @MainActor
    func nsMenu(perform: @escaping @MainActor (Action) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        nsItems(perform: perform).forEach(menu.addItem)
        return menu
    }
}

extension Track {
    /// The song as the source app knows it, for links.
    init(_ track: LibraryTrack) {
        self.init(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            artworkURL: track.artwork?.url,
            isExplicit: track.isExplicit
        )
    }
}

/// The target of a menu item that runs a closure. The item keeps it alive
/// through `representedObject`.
private final class MenuAction: NSObject {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}

extension NSMenuItem {
    /// An item that runs `handler`, for menus built in code.
    convenience init(title: String, handler: @escaping @MainActor () -> Void) {
        self.init(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let action = MenuAction(handler)
        target = action
        representedObject = action
    }
}

/// The same items as SwiftUI menu content, for right-click.
struct TrackMenuItems: View {
    var menu: TrackMenu
    var perform: (TrackMenu.Action) -> Void

    var body: some View {
        ForEach(Array(menu.entries.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case .separator:
                Divider()
            case .action(let action):
                Button(menu.title(for: action)) { perform(action) }
            }
        }
    }
}

/// Carries out a song's menu item.
@MainActor
enum TrackMenuPerformer {
    /// For the playing song, on Now.
    static func perform(_ action: TrackMenu.Action, store: NowPlayingStore) {
        guard let track = store.track, let source = store.activeSource else { return }
        switch action {
        case .toggleSave:
            // The menu may be all that's showing, so the HUD confirms.
            _ = store.toggleSaveAndConfirm()
        case .copyLink:
            guard let url = source.shareLink(for: track) else { return }
            copy(url)
        case .reveal:
            reveal(track, in: source)
        case .playNow:
            // Not offered on Now: the song is already playing.
            break
        }
    }

    /// For a song on the History page or in the Listening History window.
    /// `context` is the list Play Now starts the song in.
    static func perform(
        _ action: TrackMenu.Action,
        track: LibraryTrack,
        library: LibraryStore,
        context: PlaybackContext? = nil
    ) {
        switch action {
        case .playNow:
            library.play(.track(track, in: context))
        case .toggleSave:
            library.setSaved(!library.isSaved(track), track: track)
        case .copyLink, .reveal:
            guard let id = library.sourceID, let source = library.nowPlaying.source(for: id) else { return }
            if action == .copyLink {
                if let url = source.shareLink(for: Track(track)) { copy(url) }
            } else {
                reveal(Track(track), in: source)
            }
        }
    }

    private static func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    private static func reveal(_ track: Track, in source: any PlaybackSource) {
        if let url = source.revealURL(for: track) {
            NSWorkspace.shared.open(url)
        } else if let bundleID = source.appBundleIdentifier,
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

// MARK: - The player's section

extension PlayerMenu {
    /// What the player shows now.
    @MainActor
    static func current(settings: SettingsStore?, sizing: PlayerSizing?, pager: SurfacePager?) -> PlayerMenu {
        PlayerMenu(
            style: settings?.appearance.style ?? .artOnly,
            pin: sizing?.pin,
            surface: pager?.current ?? .now
        )
    }

    /// The section as `NSMenuItem`s, for the More button. It starts with a
    /// separator after the song's items.
    @MainActor
    func nsItems(_ commands: PlayerMenuCommands, startsWithSeparator: Bool = true) -> [NSMenuItem] {
        let styleItem = NSMenuItem(title: Self.styleTitle, action: nil, keyEquivalent: "")
        styleItem.submenu = submenu(Self.styles.map { style in
            item(style.title, isOn: style == self.style) { commands.setStyle(style) }
        })

        let pinItem = NSMenuItem(title: Self.pinTitle, action: nil, keyEquivalent: "")
        pinItem.submenu = submenu(Self.pinGroups.enumerated().flatMap { index, group in
            let items = group.map { position in
                let item = item(position.title, isOn: position == pin) { commands.pin(position) }
                if #available(macOS 26, *) {
                    item.image = NSImage(systemSymbolName: Self.symbol(for: position), accessibilityDescription: nil)
                }
                return item
            }
            return index == 0 ? items : [.separator()] + items
        })

        let showItem = NSMenuItem(title: Self.showTitle, action: nil, keyEquivalent: "")
        showItem.submenu = submenu(Self.surfaces.map { surface in
            let item = item(Self.title(for: surface), isOn: surface == self.surface) { commands.show(surface) }
            // Shown only: the player's own key handling acts on ⌘1–⌘3.
            item.keyEquivalent = String(Self.shortcutDigit(for: surface))
            item.keyEquivalentModifierMask = .command
            return item
        })

        return (startsWithSeparator ? [.separator()] : []) + [
            styleItem,
            pinItem,
            showItem,
            NSMenuItem(title: Self.moveToMenuBarTitle) { commands.setStyle(.menuBar) },
            .separator(),
            NSMenuItem(title: Self.hidePlayerTitle) { commands.hidePlayer() },
        ]
    }

    @MainActor
    private func item(_ title: String, isOn: Bool, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, handler: handler)
        item.state = isOn ? .on : .off
        return item
    }

    @MainActor
    private func submenu(_ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        return menu
    }
}

/// What the player section's items do.
struct PlayerMenuCommands {
    var setStyle: @MainActor (PlayerStyleID) -> Void
    var pin: @MainActor (PinPosition) -> Void
    var show: @MainActor (Surface) -> Void
    var hidePlayer: @MainActor () -> Void

    @MainActor
    init(settings: SettingsStore?, sizing: PlayerSizing?, actions: PlayerActions) {
        setStyle = { settings?.appearance.style = $0 }
        pin = { sizing?.pin(to: $0) }
        show = { actions.showSurface($0) }
        hidePlayer = { actions.hidePlayer() }
    }
}

/// The player section as SwiftUI menu content, for right-click anywhere on
/// the player that isn't a song row (§4.4). History and Status put it after their
/// own items, with the separator.
struct PlayerMenuItems: View {
    var startsWithSeparator = true

    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(PlayerSizing.self) private var sizing: PlayerSizing?
    @Environment(SurfacePager.self) private var pager: SurfacePager?
    @Environment(\.playerActions) private var actions

    var body: some View {
        let menu = PlayerMenu.current(settings: settings, sizing: sizing, pager: pager)
        let commands = PlayerMenuCommands(settings: settings, sizing: sizing, actions: actions)
        if startsWithSeparator { Divider() }
        Menu(PlayerMenu.styleTitle) {
            ForEach(PlayerMenu.styles, id: \.self) { style in
                check(style.title, isOn: style == menu.style) { commands.setStyle(style) }
            }
        }
        Menu(PlayerMenu.pinTitle) {
            ForEach(Array(PlayerMenu.pinGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.self) { position in
                    check(position.title, symbol: PlayerMenu.symbol(for: position), isOn: position == menu.pin) {
                        commands.pin(position)
                    }
                }
            }
        }
        Menu(PlayerMenu.showTitle) {
            ForEach(PlayerMenu.surfaces, id: \.self) { surface in
                check(PlayerMenu.title(for: surface), isOn: surface == menu.surface) { commands.show(surface) }
                    // Shown only: the player's own key handling acts on ⌘1–⌘3.
                    .keyboardShortcut(KeyEquivalent(PlayerMenu.shortcutDigit(for: surface)), modifiers: .command)
            }
        }
        Button(PlayerMenu.moveToMenuBarTitle) { commands.setStyle(.menuBar) }
        Divider()
        Button(PlayerMenu.hidePlayerTitle) { commands.hidePlayer() }
    }

    /// A checkable item; choosing the checked one does nothing new.
    private func check(_ title: String, symbol: String? = nil, isOn: Bool, action: @escaping @MainActor () -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            if #available(macOS 26, *), let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
    }
}

// MARK: - Now's menu

extension View {
    /// Now's right-click menu (§4.4): the playing song's items, when there's a
    /// song, then the player section.
    func nowContextMenu(_ menu: TrackMenu?) -> some View {
        modifier(NowContextMenu(menu: menu))
    }
}

private struct NowContextMenu: ViewModifier {
    var menu: TrackMenu?

    @Environment(NowPlayingStore.self) private var store

    func body(content: Content) -> some View {
        content.contextMenu {
            if let menu {
                TrackMenuItems(menu: menu) { TrackMenuPerformer.perform($0, store: store) }
            }
            PlayerMenuItems(startsWithSeparator: menu != nil)
        }
    }
}
