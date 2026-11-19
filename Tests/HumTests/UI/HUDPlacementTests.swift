import CoreGraphics
@testable import HumUI
import Testing

/// A HUD never hides what it confirms (DESIGN.md §5.8): it goes where Now marks,
/// and stays inside the player.
@Suite("HUD placement")
struct HUDPlacementTests {
    static let hud = CGSize(width: 150, height: 32)
    static let player = CGSize(width: 280, height: 280)

    @Test func itCentersOnTheBandAboveTheControls() {
        // The cover above revealed controls whose top is at 180.
        let band = CGRect(x: 0, y: 40, width: 280, height: 140)
        let center = HUDPlacement.center.center(of: Self.hud, in: band, within: Self.player)
        #expect(center == CGPoint(x: 140, y: 110))
        // Clear of the title row below the band.
        #expect(center.y + Self.hud.height / 2 < band.maxY)
    }

    @Test func inTheStripItEndsWhereTheControlsEnd() {
        let strip = CGSize(width: 360, height: 72)
        let controls = CGRect(x: 220, y: 20, width: 132, height: 32)
        let center = HUDPlacement.trailing.center(of: Self.hud, in: controls, within: strip)
        #expect(center.x + Self.hud.width / 2 == controls.maxX)
        #expect(center.y == controls.midY)
    }

    @Test func aBandNearTheEdgeStillKeepsTheHUDInside() {
        let corner = CGRect(x: 250, y: 0, width: 30, height: 20)
        let center = HUDPlacement.center.center(of: Self.hud, in: corner, within: Self.player)
        #expect(center.x + Self.hud.width / 2 <= Self.player.width - HUDPlacement.margin)
        #expect(center.y - Self.hud.height / 2 >= HUDPlacement.margin)
    }

    @Test func aHUDWiderThanThePlayerCentersOnIt() {
        let wide = CGSize(width: 400, height: 32)
        let center = HUDPlacement.trailing.center(of: wide, in: CGRect(x: 200, y: 100, width: 60, height: 40), within: Self.player)
        #expect(center.x == Self.player.width / 2)
    }
}
