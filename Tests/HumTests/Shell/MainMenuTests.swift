import AppKit
@testable import Hum
import HumUI
import Testing

@MainActor
@Suite("App menu bar")
struct MainMenuTests {
    /// Counts the items Hum handles itself.
    final class Calls {
        var about = 0
        var settings = 0
        var help = 0
    }

    private func makeMenu(_ calls: Calls = Calls()) -> NSMenu {
        MainMenu.make(MainMenu.Actions(
            showAbout: { calls.about += 1 },
            openSettings: { calls.settings += 1 },
            showHelp: { calls.help += 1 }
        ))
    }

    /// Titles in order, with "-" for each separator.
    private func titles(_ menu: NSMenu?) -> [String] {
        (menu?.items ?? []).map { $0.isSeparatorItem ? "-" : $0.title }
    }

    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu? {
        menu.item(withTitle: title)?.submenu
    }

    @Test func theMenusAreTheStandardOnes() {
        #expect(titles(makeMenu()) == ["Hum", "Edit", "Window", "Help"])
    }

    /// Every title in every menu, submenus included.
    private func allTitles(_ menu: NSMenu) -> [String] {
        menu.items.flatMap { item in [item.title] + (item.submenu.map(allTitles) ?? []) }
    }

    /// Find and Play were removed (DESIGN.md §13.9), and the surfaces are
    /// reached in the player (⌘1–⌘3), so no menu offers them.
    @Test func noMenuOffersFindPlayOrTheSurfaces() {
        let titles = allTitles(makeMenu())
        for gone in ["Find", "Find…", "Search", "Play", "Library", "Go to Current Song", "Now", "Echo", "Status"] {
            #expect(!titles.contains(gone), "\(gone)")
        }
        #expect(!titles.contains { $0.contains("Spotify") })
    }

    @Test func theAppMenuHasTheStandardItemsInOrder() {
        let app = submenu("Hum", in: makeMenu())
        #expect(titles(app) == [
            "About Hum", "-",
            "Settings…", "-",
            "Services", "-",
            "Hide Hum", "Hide Others", "Show All", "-",
            "Quit Hum",
        ])
        #expect(app?.item(withTitle: "Services")?.submenu != nil)
    }

    @Test func appMenuKeyEquivalents() throws {
        let app = try #require(submenu("Hum", in: makeMenu()))
        let expected: [(String, String, NSEvent.ModifierFlags)] = [
            ("Settings…", ",", [.command]),
            ("Hide Hum", "h", [.command]),
            ("Hide Others", "h", [.command, .option]),
            ("Quit Hum", "q", [.command]),
        ]
        for (title, key, modifiers) in expected {
            let item = try #require(app.item(withTitle: title))
            #expect(item.keyEquivalent == key, "\(title)")
            #expect(item.keyEquivalentModifierMask == modifiers, "\(title)")
        }
        #expect(app.item(withTitle: "About Hum")?.keyEquivalent == "")
        #expect(app.item(withTitle: "Show All")?.keyEquivalent == "")
    }

    @Test func standardItemsGoToTheApplication() {
        let app = submenu("Hum", in: makeMenu())
        #expect(app?.item(withTitle: "Hide Hum")?.action == #selector(NSApplication.hide(_:)))
        #expect(app?.item(withTitle: "Hide Others")?.action == #selector(NSApplication.hideOtherApplications(_:)))
        #expect(app?.item(withTitle: "Show All")?.action == #selector(NSApplication.unhideAllApplications(_:)))
        #expect(app?.item(withTitle: "Quit Hum")?.action == #selector(NSApplication.terminate(_:)))
    }

    @Test func aboutSettingsAndHelpRunHumsActions() throws {
        let calls = Calls()
        let menu = makeMenu(calls)
        for title in ["About Hum", "Settings…"] {
            let item = try #require(submenu("Hum", in: menu)?.item(withTitle: title))
            _ = (item.target as AnyObject?)?.perform(item.action, with: item)
        }
        let help = try #require(submenu("Help", in: menu)?.item(withTitle: "Hum Help"))
        _ = (help.target as AnyObject?)?.perform(help.action, with: help)
        #expect(calls.about == 1)
        #expect(calls.settings == 1)
        #expect(calls.help == 1)
    }

    /// The standard About panel is gone (DESIGN.md §13.26): About Hum opens
    /// Settings on the Hum pane, as the app delegate wires it.
    @Test func aboutHumOpensSettingsOnTheHumPane() throws {
        var opened: [SettingsPane?] = []
        let menu = MainMenu.make(MainMenu.Actions(
            showAbout: { AppCommands.showAbout { opened.append($0) } },
            openSettings: {},
            showHelp: nil
        ))
        let item = try #require(submenu("Hum", in: menu)?.item(withTitle: "About Hum"))
        _ = (item.target as AnyObject?)?.perform(item.action, with: item)
        #expect(opened == [.about])
        #expect(SettingsPane.about.title == "Hum")
    }

    @Test func theEditMenuServesTextFields() {
        let edit = submenu("Edit", in: makeMenu())
        #expect(titles(edit) == ["Undo", "Redo", "-", "Cut", "Copy", "Paste", "Select All"])
        #expect(edit?.item(withTitle: "Redo")?.keyEquivalentModifierMask == [.command, .shift])
        #expect(edit?.item(withTitle: "Select All")?.keyEquivalent == "a")
    }

    @Test func theWindowMenuClosesMinimizesAndZooms() {
        let window = submenu("Window", in: makeMenu())
        #expect(titles(window) == ["Close", "Minimize", "Zoom", "-", "Bring All to Front"])
        #expect(window?.item(withTitle: "Close")?.keyEquivalent == "w")
        #expect(window?.item(withTitle: "Minimize")?.keyEquivalent == "m")
        #expect(window?.item(withTitle: "Bring All to Front")?.action == #selector(NSApplication.arrangeInFront(_:)))
    }

    @Test func helpIsHumHelpOnCommandQuestionMark() {
        let help = submenu("Help", in: makeMenu())
        #expect(titles(help) == ["Hum Help"])
        #expect(help?.item(withTitle: "Hum Help")?.keyEquivalent == "?")
        #expect(help?.item(withTitle: "Hum Help")?.keyEquivalentModifierMask == [.command])
    }

    /// The Help menu after AppKit validates it, as it does before showing it
    /// or matching ⌘?. Validation needs the application object: without
    /// one, AppKit disables every item.
    private func validatedHelpMenu(_ menu: NSMenu) throws -> NSMenu {
        _ = NSApplication.shared
        let help = try #require(submenu("Help", in: menu))
        help.update()
        return help
    }

    @Test func humHelpIsDisabledWhenThereIsNoPage() throws {
        let menu = MainMenu.make(MainMenu.Actions(showAbout: {}, openSettings: {}, showHelp: nil))
        let item = try #require(try validatedHelpMenu(menu).item(withTitle: "Hum Help"))
        #expect(!item.isEnabled)
        #expect(item.keyEquivalent == "?")
    }

    @Test func humHelpIsEnabledWithAPage() throws {
        #expect(try validatedHelpMenu(makeMenu()).item(withTitle: "Hum Help")?.isEnabled == true)
    }

    /// A made-up app bundle in its own temporary folder, with or without the
    /// help page. The caller removes `folder`.
    private func makeApp(withHelp: Bool) throws -> (folder: URL, bundle: Bundle) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("hum-help-\(UUID().uuidString)")
        let app = folder.appendingPathComponent("Test.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        if withHelp {
            let help = resources.appendingPathComponent("Help")
            try FileManager.default.createDirectory(at: help, withIntermediateDirectories: true)
            try Data("<html></html>".utf8).write(to: help.appendingPathComponent("index.html"))
        }
        return (folder, try #require(Bundle(url: app)))
    }

    @Test func theHelpPageIsFoundInsideTheAppBundle() throws {
        let app = try makeApp(withHelp: true)
        defer { try? FileManager.default.removeItem(at: app.folder) }
        let page = try #require(AppCommands.helpPage(in: app.bundle))
        #expect(page.lastPathComponent == "index.html")
        #expect(page.deletingLastPathComponent().lastPathComponent == "Help")
        // Only checked, never run: running it would open a browser.
        #expect(AppCommands.showHelp(in: app.bundle) != nil)
    }

    @Test func thereIsNothingToOpenWithoutTheHelpPage() throws {
        let app = try makeApp(withHelp: false)
        defer { try? FileManager.default.removeItem(at: app.folder) }
        #expect(AppCommands.helpPage(in: app.bundle) == nil)
        #expect(AppCommands.showHelp(in: app.bundle) == nil)
    }
}
