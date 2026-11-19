import CoreGraphics
@testable import HumUI
import Testing

/// The seek bar's hover tag follows the pointer above the track (DESIGN.md
/// §5.10).
@Suite("Seek hover tag")
struct HoverTagPlacementTests {
    static let tag = CGSize(width: 40, height: 18)
    static let track: CGFloat = 240

    private func origin(_ pointer: CGFloat) -> CGPoint {
        HoverTagPlacement.origin(pointer: pointer, tagSize: Self.tag, trackLength: Self.track)
    }

    @Test(arguments: [60.0, 120, 180])
    func itCentersOnThePointer(pointer: CGFloat) {
        #expect(origin(pointer).x + Self.tag.width / 2 == pointer)
    }

    @Test func itMovesWithThePointer() {
        #expect(origin(150).x > origin(100).x)
    }

    @Test(arguments: [0.0, 5, 235, 240])
    func itStaysOverTheTrackNearTheEnds(pointer: CGFloat) {
        let x = origin(pointer).x
        #expect(x >= 0)
        #expect(x + Self.tag.width <= Self.track)
    }

    @Test func itSitsAboveTheTrackNotOnIt() {
        let trackTop = (SliderMetrics.hitHeight - SliderMetrics.activeThickness) / 2
        let bottom = origin(120).y + Self.tag.height
        #expect(bottom < trackTop)
        #expect(bottom > 0)
    }

    @Test func aTagWiderThanTheTrackStartsAtItsLeadingEnd() {
        let wide = HoverTagPlacement.origin(pointer: 10, tagSize: CGSize(width: 300, height: 18), trackLength: 240)
        #expect(wide.x == 0)
    }
}
