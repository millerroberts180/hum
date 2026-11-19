import Carbon.HIToolbox
import HumCore
@testable import HumUI
import Testing

@Suite("Shortcut conflicts")
struct ShortcutConflictTests {
    private let controlOptionP = HotKeyChord(keyCode: 35, modifiers: [.control, .option], keyLabel: "P")
    private let optionCommandK = HotKeyChord(keyCode: 40, modifiers: [.option, .command], keyLabel: "K")
    private var taken: ShortcutConflict.Taken {
        ShortcutConflict.Taken(chord: optionCommandK, what: "shows or hides the player")
    }

    @Test func anotherGlobalShortcutIsTurnedDown() {
        let conflict = ShortcutConflict.check(optionCommandK, character: "k", others: [taken])
        #expect(conflict == .otherShortcut(what: "shows or hides the player"))
    }

    @Test func aDifferentChordOnTheSameKeyIsFine() {
        let shifted = HotKeyChord(keyCode: 40, modifiers: [.option, .command, .shift], keyLabel: "K")
        #expect(ShortcutConflict.check(shifted, character: "k", others: [taken]) == nil)
        #expect(ShortcutConflict.check(controlOptionP, character: "p", others: [taken]) == nil)
    }

    @Test(arguments: [
        (UInt32(13), "w"), // ⌘W, hide the player
        (UInt32(43), ","), // ⌘, Settings
        (UInt32(18), "1"), // ⌘1, Now
        (UInt32(20), "3"), // ⌘3, Status
        (UInt32(124), ""), // ⌘→, next track
    ])
    func keysThePlayerUsesAreTurnedDown(keyCode: UInt32, character: String) {
        let chord = HotKeyChord(keyCode: keyCode, modifiers: [.command], keyLabel: character.uppercased())
        #expect(ShortcutConflict.check(chord, character: character, others: []) == .player)
    }

    static let keysFindAndPlayUsed: [(UInt32, String, HotKeyChord.Modifiers)] = [
        (40, "k", [.command]), // ⌘K
        (3, "f", [.command]), // ⌘F
        (40, "k", [.option, .command]), // ⌥⌘K
        (37, "l", [.command]), // ⌘L
        (36, "\r", [.command]), // ⌘↩
    ]

    /// Find's and Play's keys went with them (DESIGN.md §4.3), so they're
    /// free for Toggle Player.
    @Test(arguments: ShortcutConflictTests.keysFindAndPlayUsed)
    func keysFindAndPlayUsedAreFree(keyCode: UInt32, character: String, modifiers: HotKeyChord.Modifiers) {
        let chord = HotKeyChord(keyCode: keyCode, modifiers: modifiers, keyLabel: character.uppercased())
        #expect(ShortcutConflict.check(chord, character: character, others: []) == nil)
    }

    @Test func favoriteIsAPlayerKeyEvenAsTypedWithShift() {
        let chord = HotKeyChord(keyCode: 11, modifiers: [.option, .shift], keyLabel: "B")
        #expect(ShortcutConflict.check(chord, character: "B", others: []) == .player)
    }

    @Test func messagesSayWhatHappenedAndWhatIsStillSet() {
        let previous = HotKeyChord(keyCode: 35, modifiers: [.control, .option], keyLabel: "P")
        #expect(
            ShortcutConflict.otherShortcut(what: "shows or hides the player").message(for: optionCommandK, keeping: previous)
                == "⌥⌘K already shows or hides the player. ⌃⌥P is still the shortcut."
        )
        #expect(
            ShortcutConflict.unavailable.message(for: controlOptionP, keeping: nil)
                == "⌃⌥P is in use by macOS or another app. No shortcut is set."
        )
        let commandW = HotKeyChord(keyCode: 13, modifiers: [.command], keyLabel: "W")
        #expect(
            ShortcutConflict.player.message(for: commandW, keeping: optionCommandK)
                == "⌘W is already used in the player. ⌥⌘K is still the shortcut."
        )
        #expect(
            ShortcutConflict.unavailableMessage(for: optionCommandK)
                == "⌥⌘K is in use by macOS or another app, so it doesn’t work right now."
        )
    }

    @Test func noMessageShoutsOrApologizes() {
        let messages = [
            ShortcutConflict.player.message(for: controlOptionP, keeping: nil),
            ShortcutConflict.unavailable.message(for: controlOptionP, keeping: optionCommandK),
            ShortcutConflict.unavailableMessage(for: controlOptionP),
        ]
        for message in messages {
            #expect(!message.contains("!"))
            #expect(!message.localizedCaseInsensitiveContains("sorry"))
            #expect(!message.localizedCaseInsensitiveContains("oops"))
        }
    }
}

@Suite("macOS shortcuts")
struct SystemShortcutsTests {
    private func entry(code: Int, modifiers: Int, enabled: Bool = true) -> [String: Any] {
        [
            kHISymbolicHotKeyCode as String: code,
            kHISymbolicHotKeyModifiers as String: modifiers,
            kHISymbolicHotKeyEnabled as String: enabled,
        ]
    }

    @Test func enabledEntriesAreRead() {
        // ⌘Space, and ⌃⌘Space.
        let entries = SystemShortcuts.entries(from: [
            entry(code: 49, modifiers: cmdKey),
            entry(code: 49, modifiers: cmdKey | controlKey),
        ])
        #expect(entries == [
            SystemShortcuts.Entry(keyCode: 49, modifiers: [.command]),
            SystemShortcuts.Entry(keyCode: 49, modifiers: [.command, .control]),
        ])
    }

    @Test func turnedOffAndKeylessEntriesAreLeftOut() {
        let entries = SystemShortcuts.entries(from: [
            entry(code: 49, modifiers: cmdKey, enabled: false),
            entry(code: 0xFFFF, modifiers: cmdKey),
            [kHISymbolicHotKeyCode as String: 12],
        ])
        #expect(entries.isEmpty)
    }

    /// F-keys come with the function-key bit, which a recorded chord never has.
    @Test func theFunctionKeyBitIsIgnored() {
        let entries = SystemShortcuts.entries(from: [entry(code: 120, modifiers: controlKey | (1 << 17))])
        let controlF2 = HotKeyChord(keyCode: 120, modifiers: [.control], keyLabel: "F2")
        #expect(SystemShortcuts.contains(controlF2, in: entries))
    }

    @Test func aChordMatchesOnlyWithTheSameModifiers() {
        let entries = SystemShortcuts.entries(from: [entry(code: 40, modifiers: cmdKey | shiftKey)])
        let optionCommandK = HotKeyChord(keyCode: 40, modifiers: [.option, .command], keyLabel: "K")
        #expect(!SystemShortcuts.contains(optionCommandK, in: entries))
        let shiftCommandK = HotKeyChord(keyCode: 40, modifiers: [.shift, .command], keyLabel: "K")
        #expect(SystemShortcuts.contains(shiftCommandK, in: entries))
    }
}

@Suite("Global shortcut status")
@MainActor
struct GlobalShortcutStatusTests {
    @Test func startsWithEverythingAvailable() {
        #expect(GlobalShortcutStatus().unavailable.isEmpty)
    }

    @Test func reportsWhatTheAppLastHeard() {
        let status = GlobalShortcutStatus()
        status.update(unavailable: [.togglePlayer])
        #expect(status.unavailable == [.togglePlayer])
        status.update(unavailable: [])
        #expect(status.unavailable.isEmpty)
    }
}
