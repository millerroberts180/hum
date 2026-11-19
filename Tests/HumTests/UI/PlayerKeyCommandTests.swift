import Foundation
import HumCore
@testable import HumUI
import Testing

@Suite("Player key commands")
struct PlayerKeyCommandTests {
    typealias Key = PlayerKeyCommand.KeyCode

    static func press(_ keyCode: UInt16, _ character: String = "", _ modifiers: HotKeyChord.Modifiers = []) -> PlayerKeyCommand.KeyPress {
        PlayerKeyCommand.KeyPress(keyCode: keyCode, character: character, modifiers: modifiers)
    }

    static func resolve(
        _ key: PlayerKeyCommand.KeyPress,
        editing: Bool = false,
        focused: Bool = false
    ) -> PlayerKeyCommand? {
        PlayerKeyCommand.resolve(key, isEditingText: editing, controlHasFocus: focused)
    }

    @Test func commandDigitsShowSurfaces() {
        // ⌘1–⌘3, by the ANSI digit keys.
        let digits: [(UInt16, String, Surface)] = [(18, "1", .now), (19, "2", .echo), (20, "3", .status)]
        for (keyCode, character, surface) in digits {
            #expect(Self.resolve(Self.press(keyCode, character, .command)) == .showSurface(surface))
        }
        // By character too, for layouts where the digits sit elsewhere.
        #expect(Self.resolve(Self.press(99, "3", .command)) == .showSurface(.status))
        // There's no fourth surface.
        #expect(Self.resolve(Self.press(21, "4", .command)) == nil)
    }

    @Test func commandShortcutsWorkEvenWhileTyping() {
        for editing in [false, true] {
            #expect(Self.resolve(Self.press(43, ",", .command), editing: editing) == .openSettings)
            #expect(Self.resolve(Self.press(13, "w", .command), editing: editing) == .hidePlayer)
            #expect(Self.resolve(Self.press(19, "2", .command), editing: editing) == .showSurface(.echo))
        }
    }

    /// ⌘K, ⌘F, ⌥⌘K, ⌘L, ⌘↩ and ⌥↩ went with Find and Play (DESIGN.md §4.3).
    @Test func findAndPlayKeysAreGone() {
        #expect(Self.resolve(Self.press(40, "k", .command)) == nil)
        #expect(Self.resolve(Self.press(3, "f", .command)) == nil)
        #expect(Self.resolve(Self.press(40, "k", [.command, .option])) == nil)
        #expect(Self.resolve(Self.press(37, "l", .command)) == nil)
        #expect(Self.resolve(Self.press(Key.returnKey, "\r", .command)) == nil)
        #expect(Self.resolve(Self.press(Key.returnKey, "\r", .option)) == nil)
        #expect(Self.resolve(Self.press(Key.returnKey, "\r")) == nil)
    }

    @Test func commandArrowsControlPlayback() {
        #expect(Self.resolve(Self.press(Key.leftArrow, "", .command)) == .previousTrack)
        #expect(Self.resolve(Self.press(Key.rightArrow, "", .command)) == .nextTrack)
        #expect(Self.resolve(Self.press(Key.upArrow, "", .command)) == .volumeUp)
        #expect(Self.resolve(Self.press(Key.downArrow, "", .command)) == .volumeDown)
        // A text field keeps its own arrow shortcuts.
        #expect(Self.resolve(Self.press(Key.leftArrow, "", .command), editing: true) == nil)
    }

    @Test func optionShiftBSaves() {
        #expect(Self.resolve(Self.press(Key.b, "b", [.option, .shift])) == .toggleFavorite)
        #expect(Self.resolve(Self.press(Key.b, "b", [.option, .shift]), editing: true) == nil)
        #expect(Self.resolve(Self.press(Key.b, "b", .option)) == nil)
    }

    @Test func bareKeysPageAndPlay() {
        #expect(Self.resolve(Self.press(Key.space, " ")) == .playPause)
        #expect(Self.resolve(Self.press(Key.leftArrow)) == .previousSurface)
        #expect(Self.resolve(Self.press(Key.rightArrow)) == .nextSurface)
        #expect(Self.resolve(Self.press(Key.escape)) == .dismiss)
        #expect(Self.resolve(Self.press(0, "a")) == nil)
    }

    @Test func aFocusedControlKeepsSpaceAndArrows() {
        #expect(Self.resolve(Self.press(Key.space, " "), focused: true) == nil)
        #expect(Self.resolve(Self.press(Key.leftArrow), focused: true) == nil)
        #expect(Self.resolve(Self.press(Key.rightArrow), focused: true) == nil)
        // Escape still backs out, and Command shortcuts still apply.
        #expect(Self.resolve(Self.press(Key.escape), focused: true) == .dismiss)
        #expect(Self.resolve(Self.press(Key.rightArrow, "", .command), focused: true) == .nextTrack)
    }

    @Test func escapeClosesAnOpenPopoverFirst() {
        let escape = Self.press(Key.escape)
        #expect(PlayerKeyCommand.resolve(escape, isEditingText: false, controlHasFocus: true, popoverIsOpen: true) == .closePopover)
        #expect(PlayerKeyCommand.resolve(escape, isEditingText: false, popoverIsOpen: true) == .closePopover)
        // Other keys are unchanged by it.
        #expect(PlayerKeyCommand.resolve(Self.press(Key.space, " "), isEditingText: false, controlHasFocus: true, popoverIsOpen: true) == nil)
    }

    @Test @MainActor func onlyTheOpenPopoverIsAskedToClose() {
        let interaction = PlayerInteraction()
        interaction.closePopover()
        #expect(interaction.popoverCloseRequestCount == 0)

        let volume = UUID(), other = UUID()
        interaction.setPopoverOpen(true, token: volume)
        #expect(interaction.isPopoverOpen)
        interaction.closePopover()
        #expect(interaction.popoverCloseRequestCount == 1)

        // A stale close from something else doesn't clear it.
        interaction.setPopoverOpen(false, token: other)
        #expect(interaction.isPopoverOpen)
        interaction.setPopoverOpen(false, token: volume)
        #expect(!interaction.isPopoverOpen)
    }

    @Test func typingKeepsBareKeys() {
        #expect(Self.resolve(Self.press(Key.space, " "), editing: true) == nil)
        #expect(Self.resolve(Self.press(Key.escape), editing: true) == nil)
        #expect(Self.resolve(Self.press(Key.leftArrow), editing: true) == nil)
    }
}
