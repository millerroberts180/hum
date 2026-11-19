import AppKit
import HumCore
@testable import HumUI
import Testing

@MainActor
@Suite("Summoning the player in Menu Bar")
struct MenuBarSummonTests {
    /// A player in `style` that's never started or shown.
    func makePlayer(style: PlayerStyleID) -> PlayerWindowController {
        let settings = SettingsStore(fileURL: nil)
        settings.appearance.style = style
        return PlayerWindowController(
            store: NowPlayingStore(sources: []),
            settings: settings,
            launchOptions: LaunchOptions(),
            actions: PlayerActions()
        )
    }

    /// A widget's Show link, the Dock and Show ▸ open the popover; only the
    /// Toggle Player shortcut may close it (DESIGN.md §7.1, §7.3).
    @Test func showAsksToOpenThePopoverAndToggleToToggleIt() {
        let player = makePlayer(style: .menuBar)
        var summons: [PlayerWindowController.Summon] = []
        player.onSummonInMenuBar = { summons.append($0) }
        player.show()
        player.show()
        player.go(to: .now)
        player.toggle()
        #expect(summons == [.show, .show, .show, .toggle])
        #expect(!player.isVisible)
    }

    @Test func showLeavesAnOpenPopoverOpen() {
        #expect(PlayerWindowController.Summon.show.togglesPopover(isShown: false))
        #expect(!PlayerWindowController.Summon.show.togglesPopover(isShown: true))
        #expect(PlayerWindowController.Summon.toggle.togglesPopover(isShown: false))
        #expect(PlayerWindowController.Summon.toggle.togglesPopover(isShown: true))
    }

    /// Outside Menu Bar there's a window to show, so the popover isn't asked.
    @Test func aWindowStyleNeverSummonsThePopover() {
        let player = makePlayer(style: .artOnly)
        var summons: [PlayerWindowController.Summon] = []
        player.onSummonInMenuBar = { summons.append($0) }
        player.hide()
        #expect(summons.isEmpty)
    }
}
