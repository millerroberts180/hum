import Foundation
import HumCore
import Testing

@Suite("Pending intents")
struct PendingIntentsTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    func snapshot(_ status: PlaybackStatus, position: TimeInterval? = 10, at date: Date) -> PlaybackSnapshot {
        PlaybackSnapshot(track: Fixtures.track(), status: status, position: position, timestamp: date, volume: 0.5, shuffle: false)
    }

    @Test func overridesAStaleReportUntilConfirmed() {
        var intents = PendingIntents()
        let playing = snapshot(.playing, at: start)
        intents.record(.togglePlayPause, current: playing, at: start)

        // A report sent before the command landed still says playing.
        let stale = intents.apply(to: playing, at: start.addingTimeInterval(0.2))
        #expect(stale.status == .paused)
        #expect(intents.status != nil)

        // The source confirms; the intent is spent.
        let confirmed = intents.apply(to: snapshot(.paused, at: start), at: start.addingTimeInterval(0.4))
        #expect(confirmed.status == .paused)
        #expect(intents.isEmpty)
    }

    @Test func theSourceWinsAfterTheDeadline() {
        var intents = PendingIntents()
        intents.record(.pause, current: snapshot(.playing, at: start), at: start)
        let late = start.addingTimeInterval(PendingIntents.lifetime + 0.01)
        #expect(intents.apply(to: snapshot(.playing, at: late), at: late).status == .playing)
        #expect(intents.isEmpty)
    }

    @Test func seekHoldsUntilTheReportIsNearTheTarget() {
        var intents = PendingIntents()
        intents.record(.seek(to: 90), current: snapshot(.playing, at: start), at: start)

        let early = start.addingTimeInterval(0.5)
        let held = intents.apply(to: snapshot(.playing, position: 12, at: early), at: early)
        #expect(held.position == 90.5)
        #expect(intents.seek != nil)

        let confirmed = start.addingTimeInterval(0.8)
        _ = intents.apply(to: snapshot(.playing, position: 90.6, at: confirmed), at: confirmed)
        #expect(intents.seek == nil)
    }

    @Test func volumeConfirmsWithinASmallTolerance() {
        var intents = PendingIntents()
        intents.record(.setVolume(0.8), current: snapshot(.playing, at: start), at: start)
        var reported = snapshot(.playing, at: start)
        reported.volume = 0.79
        #expect(intents.apply(to: reported, at: start.addingTimeInterval(0.1)).volume == 0.79)
        #expect(intents.volume == nil)
    }

    @Test func skippingDropsIntentsForTheOldTrack() {
        var intents = PendingIntents()
        let current = snapshot(.playing, at: start)
        intents.record(.seek(to: 30), current: current, at: start)
        intents.record(.setFavorite(true), current: current, at: start)
        intents.record(.setShuffle(true), current: current, at: start)
        intents.record(.next, current: current, at: start)
        #expect(intents.seek == nil)
        #expect(intents.favorite == nil)
        #expect(intents.shuffle?.value == true)
    }
}
