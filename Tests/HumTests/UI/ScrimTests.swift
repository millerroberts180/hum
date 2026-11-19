import CoreGraphics
@testable import HumUI
import Testing

@Suite("Controls scrim")
struct ScrimTests {
    @Test func shortControlsGetTheStandardBand() {
        #expect(abs(Scrim.bandHeight(side: 440, contentHeight: 80) - 198) < 0.001)
    }

    @Test func tallControlsGetARampAboveThem() {
        #expect(Scrim.bandHeight(side: 440, contentHeight: 300) == 300 + Spacing.xxl)
        #expect(Scrim.bandHeight(side: 200, contentHeight: 190) == 200)
    }

    @Test func everyLineOfTextSitsOnTheFullDarkening() {
        let band = Scrim.bandHeight(side: 440, contentHeight: 300)
        let ramp = Double((band - 300) / band)
        #expect(Scrim.opacity(at: 0, peak: Scrim.peak, ramp: ramp) == 0)
        #expect(Scrim.opacity(at: ramp / 2, peak: Scrim.peak, ramp: ramp) < Scrim.peak)
        // From the top of the controls down, the scrim is at its peak.
        for location in [ramp, 0.5, 1] {
            #expect(Scrim.opacity(at: location, peak: Scrim.peak, ramp: ramp) == Scrim.peak)
        }
    }

    @Test func theRampRisesSteadily() {
        let samples = stride(from: 0.0, through: 0.3, by: 0.01).map {
            Scrim.opacity(at: $0, peak: Scrim.peak, ramp: 0.3)
        }
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }
}
