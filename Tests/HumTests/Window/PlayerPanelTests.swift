import AppKit
@testable import HumUI
import Testing

@Suite("Who has the keyboard")
@MainActor
struct PlayerPanelTests {
    private func panel() -> PlayerPanel {
        PlayerPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    private func event(_ type: NSEvent.EventType, in panel: NSWindow) -> NSEvent? {
        switch type {
        case .keyDown:
            NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil,
                characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
            )
        default:
            NSEvent.mouseEvent(
                with: type, location: CGPoint(x: 100, y: 100), modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            )
        }
    }

    /// So AppKit doesn't hand it the keyboard when it's ordered in at launch or
    /// for a track change.
    @Test func untilSummonedItCantTakeTheKeyboard() {
        #expect(!panel().canBecomeKey)
    }

    @Test func summonedItCanTakeTheKeyboard() {
        let panel = panel()
        panel.allowKeyboard()
        #expect(panel.canBecomeKey)
    }

    @Test(arguments: [NSEvent.EventType.leftMouseDown, .rightMouseDown])
    func aClickLetsItTakeTheKeyboard(_ type: NSEvent.EventType) throws {
        let panel = panel()
        panel.sendEvent(try #require(event(type, in: panel)))
        #expect(panel.canBecomeKey)
    }

    /// AppKit makes a window key on a left click by itself; a right or middle
    /// click the panel has to take it for, so a field its menu opens (New
    /// Playlist…) gets the typing.
    @Test(arguments: [NSEvent.EventType.rightMouseDown, .otherMouseDown])
    func aRightClickTakesTheKeyboardAtOnce(_ type: NSEvent.EventType) throws {
        let panel = panel()
        var taken = 0
        panel.takeKeyForClick = { _ in taken += 1 }
        panel.sendEvent(try #require(event(type, in: panel)))
        #expect(taken == 1)
    }

    @Test func aLeftClickOrAKeyPressLeavesThatToAppKit() throws {
        let panel = panel()
        var taken = 0
        panel.takeKeyForClick = { _ in taken += 1 }
        panel.sendEvent(try #require(event(.leftMouseDown, in: panel)))
        panel.sendEvent(try #require(event(.keyDown, in: panel)))
        #expect(taken == 0)
    }

    @Test func aKeyPressAloneDoesnt() throws {
        let panel = panel()
        panel.sendEvent(try #require(event(.keyDown, in: panel)))
        #expect(!panel.canBecomeKey)
    }

    /// VoiceOver introduces it as a window, not a system dialog.
    @Test func itReadsAsAFloatingWindow() {
        let panel = panel()
        #expect(panel.accessibilityRole() == .window)
        #expect(panel.accessibilitySubrole() == .floatingWindow)
    }

    @Test func hiddenItHasToBeSummonedAgain() {
        let panel = panel()
        panel.allowKeyboard()
        panel.orderOut(nil)
        #expect(!panel.canBecomeKey)
    }
}
