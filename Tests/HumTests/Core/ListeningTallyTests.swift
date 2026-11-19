import Foundation
import HumCore
import Testing

@Suite("Listening tally")
struct ListeningTallyTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func countsOnlyTimeSpentPlaying() {
        var tally = ListeningTally()
        let a = TrackID("a")
        #expect(tally.update(track: a, isPlaying: true, at: start) == nil)
        _ = tally.update(track: a, isPlaying: false, at: start.addingTimeInterval(20))
        _ = tally.update(track: a, isPlaying: true, at: start.addingTimeInterval(100))
        let finished = tally.update(track: TrackID("b"), isPlaying: true, at: start.addingTimeInterval(110))
        #expect(finished == 30)
        #expect(tally.trackID == TrackID("b"))
        #expect(tally.listened(at: start.addingTimeInterval(115)) == 5)
    }
}
