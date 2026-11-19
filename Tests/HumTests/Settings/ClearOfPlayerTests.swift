import CoreGraphics
@testable import HumUI
import Testing

@Suite("Windows open clear of the player")
struct ClearOfPlayerTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let centered = CGRect(x: 370, y: 187.5, width: 700, height: 500)

    @Test func aWindowAwayFromThePlayerStaysCentered() {
        let corner = CGRect(x: 1100, y: 20, width: 320, height: 320)
        #expect(ClearOfPlayer.frame(centered: centered, player: corner, in: screen) == centered)
        #expect(ClearOfPlayer.frame(centered: centered, player: nil, in: screen) == centered)
    }

    @Test func aWindowUnderThePlayerMovesBesideIt() {
        let player = CGRect(x: 900, y: 300, width: 320, height: 320)
        let placed = ClearOfPlayer.frame(centered: centered, player: player, in: screen)
        #expect(placed == CGRect(x: 184, y: 187.5, width: 700, height: 500), "to the left, a gap away")
    }

    @Test func theNearestClearSideWins() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let centered = CGRect(x: 520, y: 400, width: 400, height: 300)
        let player = CGRect(x: 560, y: 600, width: 320, height: 120)
        let placed = ClearOfPlayer.frame(centered: centered, player: player, in: screen)
        #expect(placed == CGRect(x: 520, y: 284, width: 400, height: 300), "below moves it least")
    }

    @Test func withNoRoomItStaysCentered() {
        let large = CGRect(x: 20, y: 12.5, width: 1400, height: 850)
        let player = CGRect(x: 600, y: 300, width: 240, height: 240)
        #expect(ClearOfPlayer.frame(centered: large, player: player, in: screen) == large)
    }

    @Test func itStaysOnTheScreensVisibleFrame() {
        let menuBarScreen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let tall = CGRect(x: 370, y: 100, width: 700, height: 760)
        let player = CGRect(x: 380, y: 300, width: 300, height: 300)
        let placed = ClearOfPlayer.frame(centered: tall, player: player, in: menuBarScreen)
        #expect(menuBarScreen.contains(placed))
        #expect(!placed.intersects(player))
        #expect(placed.minX == player.maxX + 16)
    }
}
