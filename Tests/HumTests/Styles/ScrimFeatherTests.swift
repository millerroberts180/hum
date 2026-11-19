import CoreGraphics
@testable import HumUI
import Testing

@Suite("Scrim feather")
struct ScrimFeatherTests {
    @Test func theFeatherRisesAboveTheBandButNeverPastTheCover() {
        for side in [168.0, 240, 280, 380, 640] as [CGFloat] {
            let band = Scrim.bandHeight(side: side, contentHeight: 60)
            let feathered = Scrim.featheredHeight(side: side, contentHeight: 60)
            #expect(feathered > band || band == side)
            #expect(feathered <= side)
        }
        #expect(Scrim.featheredHeight(side: 200, contentHeight: 400) == 200)
    }

    @Test func theFeatherGrowsWithThePlayer() {
        let small = Scrim.featheredHeight(side: 280, contentHeight: 60) - Scrim.bandHeight(side: 280, contentHeight: 60)
        let large = Scrim.featheredHeight(side: 640, contentHeight: 60) - Scrim.bandHeight(side: 640, contentHeight: 60)
        #expect(large > small)
    }

    @Test func theControlsSitOnTheFullDarkening() {
        let height = Scrim.featheredHeight(side: 400, contentHeight: 120)
        let ramp = Scrim.ramp(height: height, contentHeight: 120)
        let controlsTop = Double((height - 120) / height)
        #expect(abs(ramp - controlsTop) < 0.0001)
        #expect(Scrim.opacity(at: controlsTop, peak: Scrim.peak, ramp: ramp) == Scrim.peak)
        #expect(Scrim.ramp(height: 0, contentHeight: 10) == 1)
    }

    @Test func theRiseStartsAndEndsWithoutAnEdge() {
        let ramp = 0.6
        // Smootherstep is flat at both ends, so the top of the scrim has no line.
        let first = Scrim.rise(at: ramp * 0.02, ramp: ramp)
        let last = 1 - Scrim.rise(at: ramp * 0.98, ramp: ramp)
        #expect(first < 0.001)
        #expect(last < 0.001)
        #expect(Scrim.rise(at: 0, ramp: ramp) == 0)
        #expect(Scrim.rise(at: ramp, ramp: ramp) == 1)
    }
}
