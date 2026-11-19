import AppKit
@testable import Hum
import HumUI
import Testing

@MainActor
@Suite("Dock icon and menu bar")
struct DockPresenceTests {
    typealias Facts = DockPresence.WindowFacts

    static let settings = Facts(isVisible: true, isTitled: true, isPanel: false, isSheet: false, isSettings: true)
    static let history = Facts(isVisible: true, isTitled: true, isPanel: false, isSheet: false)
    static let player = Facts(isVisible: true, isTitled: false, isPanel: true, isSheet: false)
    static let popover = Facts(isVisible: true, isTitled: false, isPanel: true, isSheet: false)
    /// An alert, or an open panel run on its own.
    static let plainPanel = Facts(isVisible: true, isTitled: true, isPanel: true, isSheet: false)
    /// A save panel or confirmation dialog on Listening History.
    static let sheet = Facts(isVisible: true, isTitled: true, isPanel: true, isSheet: true)

    /// The app's windows by name, opened and closed one step at a time.
    struct Screen {
        var windows: [String: Facts] = [:]

        mutating func open(_ name: String, _ facts: Facts) -> NSApplication.ActivationPolicy {
            windows[name] = facts
            return policy
        }

        mutating func close(_ name: String) -> NSApplication.ActivationPolicy {
            windows[name]?.isVisible = false
            return policy
        }

        mutating func minimize(_ name: String) -> NSApplication.ActivationPolicy {
            windows[name]?.isVisible = false
            windows[name]?.isMiniaturized = true
            return policy
        }

        var policy: NSApplication.ActivationPolicy { DockPresence.policy(for: windows.values) }
    }

    @Test func withNoWindowsHumStaysInTheMenuBar() {
        #expect(DockPresence.policy(for: []) == .accessory)
    }

    /// Settings is a utility window (DESIGN.md §13.26): alone, it never
    /// brings the Dock icon.
    @Test func settingsAloneNeverBringsTheDockIcon() {
        var screen = Screen()
        #expect(screen.open("player", Self.player) == .accessory)
        #expect(screen.open("settings", Self.settings) == .accessory)
        #expect(screen.minimize("settings") == .accessory, "minimized, it's still Settings")
        #expect(screen.open("settings", Self.settings) == .accessory)
        #expect(screen.close("settings") == .accessory)
    }

    @Test func listeningHistoryAloneBringsItUntilItCloses() {
        var screen = Screen()
        #expect(screen.open("player", Self.player) == .accessory)
        #expect(screen.open("history", Self.history) == .regular)
        #expect(screen.close("history") == .accessory)
        #expect(screen.open("history", Self.history) == .regular, "reopening counts again")
        #expect(screen.close("history") == .accessory)
    }

    /// With both open, the Dock icon follows History alone: it goes when
    /// History closes, even with Settings still open.
    @Test(arguments: [["settings", "history"], ["history", "settings"]])
    func withBothOpenItFollowsHistory(opening order: [String]) {
        var screen = Screen()
        _ = screen.open("player", Self.player)
        for name in order {
            _ = screen.open(name, name == "history" ? Self.history : Self.settings)
        }
        #expect(screen.policy == .regular)
        #expect(screen.close("history") == .accessory, "Settings is still open")
        #expect(screen.open("history", Self.history) == .regular)
        #expect(screen.close("settings") == .regular, "History is still open")
        #expect(screen.close("history") == .accessory)
    }

    /// Closing History hands the front to the Settings window still open, not
    /// to another app.
    @Test func closingHistoryLeavesSettingsInFront() {
        var screen = Screen()
        _ = screen.open("player", Self.player)
        _ = screen.open("settings", Self.settings)
        _ = screen.open("history", Self.history)
        let policy = screen.close("history")
        #expect(policy == .accessory)
        #expect(DockPresence.settingsTakesTheFront(after: policy, wasActive: true, windows: screen.windows.values))
        #expect(!DockPresence.settingsTakesTheFront(after: policy, wasActive: false, windows: screen.windows.values), "Hum wasn't in front")
        #expect(!DockPresence.settingsTakesTheFront(after: .regular, wasActive: true, windows: screen.windows.values), "a regular app keeps the front")
        _ = screen.minimize("settings")
        #expect(!DockPresence.settingsTakesTheFront(after: policy, wasActive: true, windows: screen.windows.values), "a minimized Settings stays in the Dock")
        _ = screen.close("settings")
        #expect(!DockPresence.settingsTakesTheFront(after: policy, wasActive: true, windows: screen.windows.values), "no Settings to come forward")
    }

    @Test func withNeitherOpenItStaysAway() {
        var screen = Screen()
        #expect(screen.open("player", Self.player) == .accessory)
        #expect(screen.open("popover", Self.popover) == .accessory)
        #expect(screen.open("alert", Self.plainPanel) == .accessory)
        #expect(screen.close("player") == .accessory)
    }

    @Test func thePlayerAndItsPopoversNeverCount() {
        var screen = Screen()
        #expect(screen.open("player", Self.player) == .accessory)
        #expect(screen.open("popover", Self.popover) == .accessory)
        #expect(screen.open("history", Self.history) == .regular)
        #expect(screen.close("history") == .accessory, "the player and popover are still open")
    }

    @Test func aSheetLeavesItToItsWindow() {
        var screen = Screen()
        #expect(screen.open("history", Self.history) == .regular)
        #expect(screen.open("save", Self.sheet) == .regular)
        #expect(screen.close("history") == .accessory, "the sheet alone doesn't keep it")
    }

    @Test func aMinimizedWindowIsStillOpen() {
        var screen = Screen()
        #expect(screen.open("history", Self.history) == .regular)
        #expect(screen.minimize("history") == .regular, "it's in the Dock")
        #expect(screen.open("history", Self.history) == .regular)
        #expect(screen.close("history") == .accessory)
    }

    @Test func factsComeFromTheWindow() {
        let titled = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        let player = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        let settings = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        settings.identifier = SettingsWindowPresenter.windowIdentifier

        #expect(Facts(titled) == Facts(isVisible: false, isTitled: true, isPanel: false, isSheet: false))
        #expect(Facts(player) == Facts(isVisible: false, isTitled: false, isPanel: true, isSheet: false))
        #expect(Facts(settings).isSettings)
        #expect(!Facts(titled).isSettings)
        // Never shown, so none of them counts yet.
        #expect(DockPresence.policy(for: [titled, player, settings].map(Facts.init)) == .accessory)
    }
}
