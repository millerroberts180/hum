import Foundation
import HumCore
import Testing

@Suite("Shortcuts")
struct HotKeyChordTests {
    @Test func anOptionCommandChordReadsAsTheMenusShowIt() {
        let chord = HotKeyChord(keyCode: 40, modifiers: [.command, .option], keyLabel: "K")
        #expect(chord.displayString == "⌥⌘K")
        #expect(chord.isValidGlobalShortcut)
    }

    /// Toggle Player is the only global shortcut, and it has no default.
    @Test func noGlobalShortcutIsSetUntilTheUserSetsOne() {
        #expect(ShortcutSettings().togglePlayer == nil)
    }

    /// Find's global shortcut was removed with Find (DESIGN.md §4.3). One
    /// saved before is read and dropped: it does nothing, and it never
    /// becomes Toggle Player's.
    @Test func aSavedFindShortcutIsIgnored() throws {
        let json = """
        {
          "openFind": { "keyCode": 40, "modifiers": 10, "keyLabel": "K" },
          "togglePlayer": { "keyCode": 35, "modifiers": 3, "keyLabel": "P" }
        }
        """
        let settings = try JSONDecoder().decode(ShortcutSettings.self, from: Data(json.utf8))
        #expect(settings.togglePlayer == HotKeyChord(keyCode: 35, modifiers: [.control, .option], keyLabel: "P"))
        let written = try #require(String(data: JSONEncoder().encode(settings), encoding: .utf8))
        #expect(!written.contains("openFind"))
    }

    @Test func aSavedFindShortcutAloneLeavesTogglePlayerOff() throws {
        let json = #"{ "openFind": { "keyCode": 40, "modifiers": 10, "keyLabel": "K" } }"#
        let settings = try JSONDecoder().decode(ShortcutSettings.self, from: Data(json.utf8))
        #expect(settings.togglePlayer == nil)
    }

    @Test func symbolsFollowMenuOrder() {
        let chord = HotKeyChord(keyCode: 1, modifiers: [.command, .shift, .control, .option], keyLabel: "S")
        #expect(chord.displayString == "⌃⌥⇧⌘S")
    }

    @Test func aGlobalShortcutNeedsAModifierBeyondShift() {
        #expect(!HotKeyChord(keyCode: 40, modifiers: [], keyLabel: "K").isValidGlobalShortcut)
        #expect(!HotKeyChord(keyCode: 40, modifiers: [.shift], keyLabel: "K").isValidGlobalShortcut)
        #expect(HotKeyChord(keyCode: 40, modifiers: [.control], keyLabel: "K").isValidGlobalShortcut)
    }

    @Test func roundTripsThroughJSON() throws {
        let chord = HotKeyChord(keyCode: 96, modifiers: [.control, .command], keyLabel: "F5")
        let data = try JSONEncoder().encode(chord)
        #expect(try JSONDecoder().decode(HotKeyChord.self, from: data) == chord)
    }
}
