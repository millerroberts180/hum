import Foundation
@testable import HumCore
import Testing

@MainActor
@Suite("Listening recorder")
final class ListeningRecorderTests {
    let start = HistoryFixtures.now
    let recorder = ListeningRecorder()
    var finished: [Listen] = []
    var checkpoints: [PendingListen?] = []

    init() {
        recorder.onFinish = { [unowned self] in finished.append($0) }
        recorder.onCheckpoint = { [unowned self] in checkpoints.append($0) }
    }

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func snapshot(_ id: String? = "t1", status: PlaybackStatus = .playing, context: PlaybackContext? = nil, duration: TimeInterval? = 200) -> PlaybackSnapshot {
        PlaybackSnapshot(track: id.map { Fixtures.track($0, duration: duration) }, status: status, context: context)
    }

    /// Change from the current track to `next` (or stop) at `seconds`.
    func change(to next: String?, at seconds: TimeInterval, storeListened: TimeInterval = .greatestFiniteMagnitude) {
        recorder.handle(
            .trackChanged(previous: recorder.current?.track, current: next.map { Fixtures.track($0) }, source: .demo, listened: storeListened),
            snapshot: snapshot(next, status: next == nil ? .stopped : .playing),
            at: at(seconds)
        )
    }

    // MARK: Beginning

    @Test func beginsOnlyWithATrackAndASource() {
        recorder.begin(with: snapshot(nil), source: .demo, at: start)
        #expect(recorder.current == nil)
        recorder.begin(with: snapshot(), source: nil, at: start)
        #expect(recorder.current == nil)
        recorder.begin(with: snapshot(), source: .demo, at: start)
        #expect(recorder.current?.track.id == TrackID("t1"))
        #expect(recorder.current?.runningSince == start)
    }

    @Test func aPausedTrackStartsCountingWhenItPlays() throws {
        recorder.begin(with: snapshot(status: .paused), source: .demo, at: start)
        #expect(recorder.current?.runningSince == nil)
        recorder.setPlaying(true, at: at(30))
        change(to: "t2", at: 130)
        let listen = try #require(finished.first)
        #expect(listen.startedAt == at(30))
        #expect(listen.listened == 100)
    }

    // MARK: Finishing

    @Test func aTrackChangeFinishesTheListenAndFollowsTheNextOne() throws {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        change(to: "t2", at: 120)
        let listen = try #require(finished.first)
        #expect(finished.count == 1)
        #expect(listen.trackID == TrackID("t1"))
        #expect(listen.source == .demo)
        #expect(listen.listened == 120)
        #expect(listen.startedAt == start)
        #expect(listen.endedAt == at(120))
        #expect(listen.ending == .partial)
        #expect(listen.counts)
        #expect(listen.origin == .tracked)
        #expect(recorder.current?.track.id == TrackID("t2"))
        #expect(recorder.current?.startedAt == at(120))
        // The finished listen no longer needs a checkpoint.
        #expect(checkpoints.last == .some(nil))
    }

    @Test func anEarlyChangeIsASkipThatDoesNotCount() throws {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        change(to: "t2", at: 8)
        let listen = try #require(finished.first)
        #expect(listen.ending == .skipped)
        #expect(!listen.counts)
    }

    @Test func playingNearlyToTheEndCompletes() throws {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        change(to: "t2", at: 190)
        #expect(try #require(finished.first).ending == .completed)
    }

    @Test func stoppingFinishesWithoutFollowingAnything() throws {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        change(to: nil, at: 15)
        let listen = try #require(finished.first)
        // A stop is never a skip, however early.
        #expect(listen.ending == .partial)
        #expect(recorder.current == nil)
    }

    @Test func listensTooShortToKeepAreDropped() {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        change(to: "t2", at: 1)
        #expect(finished.isEmpty)
        #expect(recorder.current?.track.id == TrackID("t2"))
    }

    @Test func theStoresSmallerCountWins() throws {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        // The store saw 50 seconds; the wall clock says 500 (a sleep it missed).
        change(to: "t2", at: 500, storeListened: 50)
        #expect(try #require(finished.first).listened == 50)
    }

    // MARK: Pauses and sleep

    @Test func pausedTimeIsLeftOutAndCheckpointed() throws {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        recorder.handle(.statusChanged(.paused, source: .demo), snapshot: snapshot(status: .paused), at: at(40))
        let checkpoint = try #require(checkpoints.last ?? nil)
        #expect(checkpoint.listened == 40)
        #expect(checkpoint.lastPlayedAt == at(40))

        recorder.handle(.statusChanged(.playing, source: .demo), snapshot: snapshot(), at: at(400))
        change(to: "t2", at: 420)
        let listen = try #require(finished.first)
        #expect(listen.listened == 60)
        // The span still runs from the start to the end, pauses included.
        #expect(listen.endedAt == at(420))
    }

    @Test func sleepStopsTheCountUntilWake() throws {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        recorder.systemWillSleep(at: at(30))
        // Playing again while asleep doesn't count.
        recorder.setPlaying(true, at: at(60))
        #expect(recorder.current?.runningSince == nil)
        recorder.systemDidWake(isPlaying: true, at: at(3_600))
        change(to: "t2", at: 3_620)
        #expect(try #require(finished.first).listened == 50)
    }

    @Test func wakingWhilePausedStaysPaused() {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        recorder.systemWillSleep(at: at(30))
        recorder.systemDidWake(isPlaying: false, at: at(90))
        #expect(recorder.current?.runningSince == nil)
        #expect(recorder.provisional(at: at(200))?.listened == 30)
    }

    // MARK: Late details

    @Test func aLateContextAndDurationAreKeptForTheSameTrack() throws {
        recorder.begin(with: snapshot(duration: nil), source: .demo, at: start)
        let playlist = PlaybackContext(kind: .playlist, name: "Late Shift", identifier: "p1")
        recorder.noteSnapshot(snapshot("other", context: PlaybackContext(kind: .album, name: "Wrong", identifier: "a1")))
        #expect(recorder.current?.context == nil)
        recorder.noteSnapshot(snapshot(context: playlist, duration: 180))
        #expect(recorder.current?.context == playlist)
        #expect(recorder.current?.track.duration == 180)

        change(to: "t2", at: 170)
        let listen = try #require(finished.first)
        #expect(listen.context == playlist)
        #expect(listen.duration == 180)
        #expect(listen.ending == .completed)
    }

    // MARK: Stopping and the trail

    @Test func finishingForStopHandsTheListenBack() throws {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        let listen = try #require(recorder.finishForStop(at: at(90)))
        #expect(listen.listened == 90)
        #expect(listen.ending == .partial)
        #expect(finished.isEmpty)
        #expect(recorder.current == nil)
        #expect(recorder.finishForStop(at: at(100)) == nil)
    }

    @Test func discardingKeepsNothing() {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        recorder.discard()
        #expect(recorder.current == nil)
        #expect(checkpoints.last == .some(nil))
        change(to: "t2", at: 120)
        #expect(finished.isEmpty)
    }

    @Test func theProvisionalListenIsWhatsBeenHeardSoFar() throws {
        recorder.begin(with: snapshot(), source: .demo, at: start)
        let early = try #require(recorder.provisional(at: at(20)))
        #expect(early.listened == 20)
        #expect(!early.counts)
        #expect(early.ending == .partial)
        let later = try #require(recorder.provisional(at: at(110)))
        #expect(later.counts)
        #expect(later.endedAt == at(110))
        #expect(recorder.pending(at: at(110))?.lastPlayedAt == at(110))
    }
}
