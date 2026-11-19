import Foundation
import HumCore
import HumSources
import Testing

/// Spotify answers a setter before it takes the new value, so Hum holds what
/// it set against the app's next replies for a moment (§13.34).
@Suite("Holding what Hum set")
struct SetterHoldTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func reply(at offset: TimeInterval, shuffle: Bool? = false, repeatMode: RepeatMode? = .off,
               volume: Double? = 0.4, track: String = "a", position: TimeInterval? = 150,
               status: PlaybackStatus = .playing) -> PlaybackSnapshot {
        PlaybackSnapshot(
            track: Fixtures.track(track),
            status: status,
            position: position,
            timestamp: start.addingTimeInterval(offset),
            volume: volume,
            shuffle: shuffle,
            repeatMode: repeatMode
        )
    }

    @Test func aStaleReplyKeepsWhatHumSet() {
        var hold = SetterHold()
        hold.record(.setShuffle(true), track: TrackID("a"), at: start)
        hold.record(.setRepeat(.all), track: TrackID("a"), at: start)
        hold.record(.setVolume(0.8), track: TrackID("a"), at: start)
        let shown = hold.apply(to: reply(at: 0.4))
        #expect(shown.shuffle == true)
        #expect(shown.repeatMode == .all)
        #expect(shown.volume == 0.8)
        #expect(!hold.isEmpty)
    }

    @Test func aReplyThatAgreesLetsGo() {
        var hold = SetterHold()
        hold.record(.setShuffle(true), track: TrackID("a"), at: start)
        hold.record(.setVolume(0.8), track: TrackID("a"), at: start)
        _ = hold.apply(to: reply(at: 0.6, shuffle: true, volume: 0.81))
        #expect(hold.isEmpty)
        // A change made in the app straight after shows at once.
        let shown = hold.apply(to: reply(at: 0.9, shuffle: false, volume: 0.2))
        #expect(shown.shuffle == false)
        #expect(shown.volume == 0.2)
    }

    @Test func afterTheHoldTheAppsWordIsFinal() {
        var hold = SetterHold()
        hold.record(.setRepeat(.all), track: TrackID("a"), at: start)
        let shown = hold.apply(to: reply(at: SetterHold.duration + 0.1))
        #expect(shown.repeatMode == .off)
        #expect(hold.isEmpty)
    }

    @Test func aSeekHoldsThePositionForTheSameSong() {
        var hold = SetterHold()
        hold.record(.seek(to: 0), track: TrackID("a"), at: start)
        // Still near the old end: shown where the seek got to by then.
        let stale = hold.apply(to: reply(at: 0.5, position: 198.4))
        #expect(stale.position == 0.5)
        // Paused, it doesn't run on.
        let paused = hold.apply(to: reply(at: 0.7, position: 198.6, status: .paused))
        #expect(paused.position == 0)
        // Taken: within the tolerance, and the hold lets go.
        let taken = hold.apply(to: reply(at: 0.9, position: 0.8))
        #expect(taken.position == 0.8)
        #expect(hold.isEmpty)
    }

    /// A new song ends the position's hold: the store's repeat one needs to
    /// see the app play on past a restart it took too late.
    @Test func aNewSongLetsThePositionGo() {
        var hold = SetterHold()
        hold.record(.seek(to: 0), track: TrackID("a"), at: start)
        let next = hold.apply(to: reply(at: 0.5, track: "b", position: 0.3))
        #expect(next.track?.id == TrackID("b"))
        #expect(next.position == 0.3)
        #expect(hold.isEmpty)
    }

    @Test func otherCommandsHoldNothing() {
        var hold = SetterHold()
        for command: PlaybackCommand in [.play, .pause, .next, .previous, .setFavorite(true)] {
            hold.record(command, track: TrackID("a"), at: start)
        }
        #expect(hold.isEmpty)
        #expect(hold.apply(to: reply(at: 0.2)) == reply(at: 0.2))
    }
}
