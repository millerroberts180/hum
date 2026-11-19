@testable import HumUI
import Testing

/// The seek bar holds still while scrubbing and follows the song again after
/// (DESIGN.md §5.2, §5.10).
@Suite("Seek scrub")
struct SeekScrubTests {
    @Test func aKeyStepIsAWholeEdit() {
        let events = SliderEvent.keyStep(from: 0.5, by: 0.1)
        #expect(events.first == .editingChanged(true))
        #expect(events.last == .editingChanged(false))
        #expect(events.contains(.committed(0.6)))
    }

    @Test(arguments: [(0.98, 0.1, 1.0), (0.02, -0.1, 0.0)])
    func keyStepsClampAtTheEnds(from: Double, by: Double, expected: Double) {
        #expect(SliderEvent.keyStep(from: from, by: by).contains(.committed(expected)))
    }

    @Test func theBarMovesAgainAfterAKeySeek() {
        var scrub = SeekScrub()
        for event in SliderEvent.keyStep(from: 0.4, by: 0.05) {
            scrub.apply(event)
        }
        #expect(!scrub.isHolding)
        #expect(scrub.fraction == nil)
    }

    @Test func aDragHoldsTheBarUntilRelease() {
        var scrub = SeekScrub()
        scrub.apply(.editingChanged(true))
        scrub.apply(.changed(0.3))
        #expect(scrub.isHolding)
        #expect(scrub.fraction == 0.3)
        scrub.apply(.committed(0.3))
        #expect(scrub.isHolding)
        scrub.apply(.editingChanged(false))
        #expect(!scrub.isHolding)
    }
}
