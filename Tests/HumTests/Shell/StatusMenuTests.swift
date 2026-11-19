import AppKit
@testable import Hum
import HumCore
import Testing

@MainActor
@Suite("Menu-bar menu")
struct StatusMenuTests {
    /// What the items did.
    final class Calls {
        var commands: [PlaybackCommand] = []
        var player = 0
        var history = 0
        var settings = 0
        var quit = 0
    }

    private static let everything: SourceCapabilities = [.transport, .shuffle, .repeatAll, .repeatOne]
    private static let song = Track(id: TrackID("a"), title: "Song", artist: "Band")

    private func items(
        track: Track? = song,
        _ capabilities: SourceCapabilities = everything,
        isPlaying: Bool = true,
        player: MenuBarController.PlayerEntry = .show,
        shortcut: (key: String, modifiers: NSEvent.ModifierFlags)? = nil,
        calls: Calls = Calls()
    ) -> [NSMenuItem] {
        MenuBarController.leanMenuItems(
            track: track,
            transport: MenuBarController.Transport(
                capabilities: capabilities,
                hasTrack: track != nil,
                isPlaying: isPlaying
            ),
            player: player,
            shortcut: shortcut,
            actions: MenuBarController.LeanMenuActions(
                send: { calls.commands.append($0) },
                player: { calls.player += 1 },
                openHistory: { calls.history += 1 },
                openSettings: { calls.settings += 1 },
                quit: { calls.quit += 1 }
            )
        )
    }

    /// Titles in order, with "-" for each separator.
    private func titles(_ items: [NSMenuItem]) -> [String] {
        items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    private func choose(_ item: NSMenuItem?) {
        guard let item else { return }
        _ = (item.target as AnyObject?)?.perform(item.action, with: item)
    }

    private func item(_ title: String, in items: [NSMenuItem]) -> NSMenuItem? {
        items.first { $0.title == title }
    }

    @Test func theMenuIsTheSongTheTransportThePlayerHistorySettingsAndQuit() {
        #expect(titles(items()) == [
            "Song", "Band",
            "Pause", "Next Track", "Previous Track", "-",
            "Show Player", "Listening History…", "-",
            "Settings…", "Quit Hum",
        ])
        #expect(items(isPlaying: false)[2].title == "Play")
    }

    @Test func withNothingPlayingItSaysSo() {
        #expect(titles(items(track: nil, isPlaying: false)) == [
            "Nothing Playing",
            "Play", "-",
            "Show Player", "Listening History…", "-",
            "Settings…", "Quit Hum",
        ])
    }

    @Test func transportTheSourceCantDoIsHidden() {
        let rest = ["-", "Show Player", "Listening History…", "-", "Settings…", "Quit Hum"]
        #expect(titles(items([.playPause])) == ["Song", "Band", "Pause"] + rest)
        #expect(titles(items([.playPause, .skipNext])) == ["Song", "Band", "Pause", "Next Track"] + rest)
        #expect(titles(items([])) == ["Song", "Band"] + rest)
    }

    /// Shuffle, Repeat, the surfaces and About Hum live on the player and in
    /// Settings › Hum (DESIGN.md §5.8).
    @Test func whatLeftTheMenuStaysOut() {
        let all = titles(items())
        for gone in ["Shuffle", "Repeat", "Now", "History", "Echo", "Status", "About Hum", "Find…", "Play…"] {
            #expect(!all.contains(gone), "\(gone)")
        }
        #expect(items().allSatisfy { $0.submenu == nil })
    }

    /// The title, then the artist, as plain disabled items the system draws in
    /// its disabled color, with the whole song as their tooltip (DESIGN.md §5.8).
    @Test func theSongIsTwoDisabledLinesWithNoSubtitle() {
        let lines = MenuBarController.header(track: Self.song)
        #expect(lines.map(\.title) == ["Song", "Band"])
        for line in lines {
            #expect(!line.isEnabled)
            #expect(line.action == nil)
            #expect(line.subtitle == nil)
            #expect(line.attributedTitle == nil)
            #expect(line.toolTip == "Song — Band")
        }

        let nothing = MenuBarController.header(track: nil)
        #expect(nothing.map(\.title) == ["Nothing Playing"])
        #expect(nothing.allSatisfy { !$0.isEnabled && $0.toolTip == nil && $0.subtitle == nil })
        #expect(items().allSatisfy { $0.subtitle == nil })
    }

    /// A long title and artist are each cut short with "…", so the menu stays
    /// at most about 220 pt wide (DESIGN.md §5.8, §13.25).
    @Test func aLongSongIsCutShortSoTheMenuStaysNarrow() throws {
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let long = Track(
            id: TrackID("long"),
            title: "An Extraordinarily Long Song Title That Goes On and On Past Any Menu",
            artist: "The Very Long-Named Orchestra and Choir of Somewhere Far Away"
        )
        // Uncut, the lines would be far wider than the menu allows.
        #expect(width(long.title) > 2 * MenuBarController.songLineWidth)
        #expect(width(long.artist) > 2 * MenuBarController.songLineWidth)

        let lines = MenuBarController.header(track: long)
        try #require(lines.count == 2)
        for (line, whole) in zip(lines, [long.title, long.artist]) {
            #expect(line.title.hasSuffix("…"))
            #expect(whole.hasPrefix(String(line.title.dropLast())))
            #expect(width(line.title) <= MenuBarController.songLineWidth)
            // As much as fits: up to the next character that isn't a space
            // wouldn't.
            let kept = line.title.dropLast().count
            let spaces = whole.dropFirst(kept).prefix { $0.isWhitespace }.count
            let more = String(whole.prefix(kept + spaces + 1)) + "…"
            #expect(width(more) > MenuBarController.songLineWidth)
            #expect(line.toolTip == "\(long.title) — \(long.artist)")
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items(track: long) { menu.addItem(item) }
        #expect(menu.size.width < 230)
        // A short song isn't cut.
        #expect(MenuBarController.header(track: Self.song).map(\.title) == ["Song", "Band"])
    }

    @Test func truncationCutsAtTheEndAndDropsTrailingSpace() {
        let font = NSFont.menuFont(ofSize: 0)
        #expect(MenuBarController.truncated("Song", toFit: 200, in: font) == "Song")
        #expect(MenuBarController.truncated("", toFit: 10, in: font) == "")
        let width = ("Lorem…" as NSString).size(withAttributes: [.font: font]).width
        #expect(MenuBarController.truncated("Lorem ipsum", toFit: width, in: font) == "Lorem…")
        // Too narrow for anything but the ellipsis.
        #expect(MenuBarController.truncated("Lorem ipsum", toFit: 1, in: font) == "…")
    }

    @Test func noItemNamesTheMusicApp() {
        for track in [Self.song, nil] {
            for title in titles(items(track: track)) {
                #expect(!title.contains("Spotify"), "\(title)")
                #expect(!title.contains("Music"), "\(title)")
            }
        }
    }

    @Test func aTrackWithNoArtistIsJustItsTitle() {
        let track = Track(id: TrackID("a"), title: "Song", artist: "")
        #expect(MenuBarController.nowPlayingLine(track) == "Song")
        let lines = MenuBarController.header(track: track)
        #expect(lines.map(\.title) == ["Song"])
        #expect(lines.first?.toolTip == "Song")
    }

    @Test func thePlayerItemSaysWhatItWillDo() {
        #expect(item("Hide Player", in: items(player: .hide)) != nil)
        #expect(item("Show Player", in: items(player: .hide)) == nil)
        // In Menu Bar the player lives in the item, so the menu brings it out.
        let menuBar = titles(items(player: .popOut))
        #expect(menuBar.contains("Pop Out Player"))
        #expect(!menuBar.contains("Show Player"))
        #expect(!menuBar.contains("Hide Player"))
    }

    /// Listening History… follows the player's item, whatever it's titled.
    @Test func listeningHistoryFollowsThePlayerItem() {
        for entry in [MenuBarController.PlayerEntry.show, .hide, .popOut] {
            let all = titles(items(player: entry))
            let player = all.firstIndex(of: entry.title)
            #expect(player != nil, "\(entry.title)")
            #expect(all.firstIndex(of: "Listening History…") == player.map { $0 + 1 }, "\(entry.title)")
        }
    }

    @Test func thePlayerItemCarriesTheShortcutOnlyOnceOneIsSet() {
        #expect(item("Show Player", in: items())?.keyEquivalent == "")
        let shortcut = (key: "p", modifiers: NSEvent.ModifierFlags([.control, .option]))
        for entry in [MenuBarController.PlayerEntry.show, .hide, .popOut] {
            let toggle = item(entry.title, in: items(player: entry, shortcut: shortcut))
            #expect(toggle?.keyEquivalent == "p", "\(entry.title)")
            #expect(toggle?.keyEquivalentModifierMask == [.control, .option], "\(entry.title)")
        }
        // Nothing else takes it.
        let others = items(shortcut: shortcut).filter { $0.title != "Show Player" && $0.keyEquivalent == "p" }
        #expect(others.isEmpty)
    }

    @Test func settingsAndQuitHaveTheirStandardKeys() throws {
        let all = items()
        let settings = try #require(item("Settings…", in: all))
        #expect(settings.keyEquivalent == ",")
        #expect(settings.keyEquivalentModifierMask == [.command])
        let quit = try #require(item("Quit Hum", in: all))
        #expect(quit.keyEquivalent == "q")
        #expect(quit.keyEquivalentModifierMask == [.command])
        for title in ["Pause", "Next Track", "Previous Track", "Show Player", "Listening History…"] {
            #expect(item(title, in: all)?.keyEquivalent == "", "\(title)")
        }
    }

    @Test func eachItemDoesItsJob() {
        let calls = Calls()
        let all = items(calls: calls)
        choose(item("Listening History…", in: all))
        #expect(calls.history == 1)
        #expect(calls.player == 0)
        #expect(calls.settings == 0)
        for title in ["Pause", "Next Track", "Previous Track", "Show Player", "Settings…", "Quit Hum"] {
            choose(item(title, in: all))
        }
        #expect(calls.commands == [.togglePlayPause, .next, .previous])
        #expect(calls.player == 1)
        #expect(calls.history == 1)
        #expect(calls.settings == 1)
        #expect(calls.quit == 1)
        // The song itself does nothing.
        #expect(all[0].action == nil)
        #expect(all[1].action == nil)
    }

    // MARK: Menu Bar in and out

    @Test func popOutReturnsToTheStyleBeforeMenuBar() {
        var appearance = AppearanceSettings()
        appearance.style = .text
        appearance.style = .menuBar
        #expect(appearance.lastWindowStyle == .text)
        MenuBarController.popOut(&appearance)
        #expect(appearance.style == .text)

        // And round again from another style.
        appearance.style = .strip
        appearance.style = .menuBar
        MenuBarController.popOut(&appearance)
        #expect(appearance.style == .strip)
    }

    @Test func popOutWithNoEarlierStyleGoesToArtOnly() throws {
        let json = #"{ "style": "menuBar" }"#
        var appearance = try JSONDecoder().decode(AppearanceSettings.self, from: Data(json.utf8))
        #expect(appearance.style == .menuBar)
        MenuBarController.popOut(&appearance)
        #expect(appearance.style == .artOnly)
    }

    /// A style remembered from before Glass, Data and Session were retired
    /// (DESIGN.md §13.19) pops out as Art Only.
    @Test(arguments: ["glass", "data", "session"])
    func popOutToARetiredStyleGoesToArtOnly(retired: String) throws {
        let json = #"{ "style": "menuBar", "lastWindowStyle": "\#(retired)" }"#
        var appearance = try JSONDecoder().decode(AppearanceSettings.self, from: Data(json.utf8))
        #expect(appearance.style == .menuBar)
        MenuBarController.popOut(&appearance)
        #expect(appearance.style == .artOnly)
    }

    @Test func popOutLeavesAWindowStyleAlone() {
        var appearance = AppearanceSettings()
        appearance.style = .title
        appearance.lastWindowStyle = .strip
        MenuBarController.popOut(&appearance)
        #expect(appearance.style == .title)
    }

    @Test func theMenuBarRememberedStyleSurvivesARelaunch() throws {
        var appearance = AppearanceSettings()
        appearance.style = .bigArt
        appearance.style = .menuBar
        let data = try JSONEncoder().encode(appearance)
        var reloaded = try JSONDecoder().decode(AppearanceSettings.self, from: data)
        #expect(reloaded.style == .menuBar)
        MenuBarController.popOut(&reloaded)
        #expect(reloaded.style == .bigArt)
    }
}
