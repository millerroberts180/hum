import Foundation
import HumCore
import Testing

@Suite("Position clock")
struct PositionClockTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func advancesOnlyWhilePlaying() {
        let playing = PositionClock(position: 10, at: start, isAdvancing: true, duration: 100)
        #expect(playing.position(at: start.addingTimeInterval(5)) == 15)

        let paused = PositionClock(position: 10, at: start, isAdvancing: false, duration: 100)
        #expect(paused.position(at: start.addingTimeInterval(5)) == 10)
    }

    @Test func clampsToDurationAndZero() {
        let clock = PositionClock(position: 95, at: start, isAdvancing: true, duration: 100)
        #expect(clock.position(at: start.addingTimeInterval(30)) == 100)
        #expect(clock.remaining(at: start.addingTimeInterval(30)) == 0)
        // A date before the anchor never runs the clock backward.
        #expect(clock.position(at: start.addingTimeInterval(-10)) == 95)
        #expect(PositionClock(position: -4).anchorPosition == 0)
    }

    @Test func progressNeedsADuration() {
        let clock = PositionClock(position: 25, at: start, isAdvancing: false, duration: 100)
        #expect(clock.progress(at: start) == 0.25)
        #expect(PositionClock(position: 25, at: start).progress(at: start) == nil)
    }

    @Test func ignoresReportsWithinTolerance() {
        var clock = PositionClock(position: 10, at: start, isAdvancing: true, duration: 100)
        let later = start.addingTimeInterval(2)
        // Interpolated 12.0; a report of 11.6 is noise.
        #expect(clock.reconcile(reported: 11.6, at: later, isAdvancing: true) == false)
        #expect(clock.position(at: later) == 12)
    }

    @Test func adoptsReportsBeyondTolerance() {
        var clock = PositionClock(position: 10, at: start, isAdvancing: true, duration: 100)
        let later = start.addingTimeInterval(2)
        let adopted = clock.reconcile(reported: 40, at: later, isAdvancing: true)
        #expect(adopted)
        #expect(clock.position(at: later) == 40)
        #expect(clock.position(at: later.addingTimeInterval(1)) == 41)
    }

    @Test func stateChangeAlwaysRebases() {
        var clock = PositionClock(position: 10, at: start, isAdvancing: true, duration: 100)
        let later = start.addingTimeInterval(3)
        let rebased = clock.reconcile(reported: 13.2, at: later, isAdvancing: false)
        #expect(rebased)
        #expect(clock.isAdvancing == false)
        #expect(clock.position(at: later.addingTimeInterval(10)) == 13.2)
    }

    @Test func pausingKeepsTheCurrentPosition() {
        var clock = PositionClock(position: 10, at: start, isAdvancing: true, duration: 100)
        clock.setAdvancing(false, at: start.addingTimeInterval(4))
        #expect(clock.position(at: start.addingTimeInterval(60)) == 14)
    }
}
