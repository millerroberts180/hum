import Foundation
import HumCore
import Testing

@Suite("Play counting and skips")
struct PlayRulesTests {
    @Test(arguments: [
        // (listened, duration, counts)
        (29.9, 40.0, false),  // under 30 seconds never counts
        (30.0, 60.0, true),   // 30 seconds and half the song
        (30.0, 200.0, false), // 30 seconds but not half
        (149.0, 300.0, false),
        (150.0, 300.0, true),
        (239.0, 600.0, false),
        (240.0, 600.0, true), // 4 minutes counts even short of half
    ])
    func countsAPlay(listened: Double, duration: Double, counts: Bool) {
        #expect(PlayRules.counts(listened: listened, duration: duration) == counts)
    }

    @Test func unknownLengthNeedsFourMinutes() {
        #expect(!PlayRules.counts(listened: 200, duration: nil))
        #expect(PlayRules.counts(listened: 240, duration: nil))
        #expect(!PlayRules.counts(listened: 100, duration: 0))
    }

    @Test func nearlyTheWholeSongIsComplete() {
        #expect(PlayRules.ending(listened: 180, duration: 200, exit: .changedTrack, wasPlaying: true) == .completed)
        #expect(PlayRules.ending(listened: 180, duration: 200, exit: .stopped, wasPlaying: false) == .completed)
        #expect(PlayRules.ending(listened: 179, duration: 200, exit: .stopped, wasPlaying: true) == .partial)
    }

    @Test func aSkipIsAnEarlyChangeWhilePlaying() {
        #expect(PlayRules.ending(listened: 10, duration: 200, exit: .changedTrack, wasPlaying: true) == .skipped)
        #expect(PlayRules.ending(listened: 29, duration: 200, exit: .changedTrack, wasPlaying: true) == .skipped)
    }

    @Test func skipsAreCalledConservatively() {
        // Late in the song: not a skip.
        #expect(PlayRules.ending(listened: 30, duration: 200, exit: .changedTrack, wasPlaying: true) == .partial)
        // Paused first, then changed: a choice made later, not a skip.
        #expect(PlayRules.ending(listened: 10, duration: 200, exit: .changedTrack, wasPlaying: false) == .partial)
        // Playback stopped rather than moving on.
        #expect(PlayRules.ending(listened: 10, duration: 200, exit: .stopped, wasPlaying: true) == .partial)
        // A short track that nearly ran out.
        #expect(PlayRules.ending(listened: 10, duration: 18, exit: .changedTrack, wasPlaying: true) == .partial)
        // Unknown length.
        #expect(PlayRules.ending(listened: 10, duration: nil, exit: .changedTrack, wasPlaying: true) == .partial)
    }

    @Test func tinyListensAreNotKept() {
        #expect(!PlayRules.shouldRecord(listened: 1.9))
        #expect(PlayRules.shouldRecord(listened: 2))
    }

    @Test func pendingListensFinishWithTheSameRules() {
        let track = Track(id: TrackID("t"), title: "Song", artist: "Artist", album: "Album", duration: 200)
        let start = HistoryFixtures.now
        let pending = PendingListen(track: track, source: .demo, context: nil, startedAt: start, lastPlayedAt: start.addingTimeInterval(120), listened: 120)
        let listen = pending.finished(exit: .stopped, wasPlaying: false)
        #expect(listen?.counts == true)
        #expect(listen?.ending == .partial)
        #expect(listen?.endedAt == start.addingTimeInterval(120))

        let tiny = PendingListen(track: track, source: .demo, context: nil, startedAt: start, lastPlayedAt: start, listened: 1)
        #expect(tiny.finished(exit: .stopped, wasPlaying: false) == nil)
    }

    @Test func songKeysIgnoreCaseAccentsAndPunctuation() {
        #expect(SongKey.make(artist: "Beyoncé", title: "Halo") == SongKey.make(artist: "beyonce", title: "HALO"))
        #expect(SongKey.make(artist: "AC/DC", title: "T.N.T.") == SongKey.make(artist: "ac dc", title: "t n t"))
        #expect(SongKey.make(artist: "A", title: "B") != SongKey.make(artist: "A B", title: ""))
    }
}
