import Foundation
import HumCore
import Testing

@MainActor
@Suite("Now playing store")
struct NowPlayingStoreTests {
    let clock = TestClock()

    func makeStore(_ sources: [FakeSource], preferred: SourceID? = nil) -> NowPlayingStore {
        let clock = clock
        let store = NowPlayingStore(sources: sources, preferredSourceID: preferred, now: { clock.now })
        store.start()
        return store
    }

    @Test func showsTheActiveSourceAndInterpolatesPosition() {
        let source = FakeSource(state: Fixtures.state(position: 10, at: clock.now))
        let store = makeStore([source])
        #expect(source.isStarted)
        #expect(store.activeSourceID == source.id)
        #expect(store.track?.id == TrackID("t1"))
        #expect(store.isPlaying)
        #expect(store.position(at: clock.now.addingTimeInterval(5)) == 15)
        #expect(store.progress(at: clock.now) == 10.0 / 200)
    }

    @Test func aReportTakenEarlierIsProjectedToNow() {
        // The source sampled the position two seconds before the store saw it.
        let source = FakeSource(state: Fixtures.state(position: 10, at: clock.now.addingTimeInterval(-2)))
        let store = makeStore([source])
        #expect(store.position(at: clock.now) == 12)
    }

    @Test func commandsShowImmediatelyAndSurviveAStaleReport() async {
        let source = FakeSource(state: Fixtures.state(at: clock.now))
        let store = makeStore([source])
        await store.perform(.pause)
        #expect(source.performed == [.pause])
        #expect(!store.isPlaying)

        // A report already in flight still says playing; the display holds.
        clock.advance(0.3)
        source.push(Fixtures.state(position: 10.3, at: clock.now))
        #expect(!store.isPlaying)

        // Long after, the source's word is final.
        clock.advance(PendingIntents.lifetime)
        source.push(Fixtures.state(position: 12, at: clock.now))
        #expect(store.isPlaying)
    }

    @Test func unsupportedCommandsNeverReachTheSource() async {
        let source = FakeSource(state: Fixtures.state(at: clock.now, capabilities: .transport))
        let store = makeStore([source])
        await store.perform(.seek(to: 30))
        await store.perform(.setFavorite(true))
        #expect(source.performed.isEmpty)
        #expect(store.lastError == .unsupported(.setFavorite(true)))
        store.setVolume(0.2)
        #expect(store.snapshot.volume == 0.5)
    }

    @Test func deniedPermissionDisablesEveryControl() async {
        let source = FakeSource(state: Fixtures.state(at: clock.now, permission: .denied))
        let store = makeStore([source])
        #expect(store.capabilities.isEmpty)
        await store.perform(.togglePlayPause)
        #expect(source.performed.isEmpty)
    }

    @Test func aClosedAppLaunchesOnlyForPlay() async {
        let closed = Fixtures.state(track: nil, status: .stopped, position: nil, at: clock.now, availability: .notRunning, capabilities: Fixtures.everything.union(.launch))
        let source = FakeSource(state: closed)
        let store = makeStore([source])

        await store.perform(.next)
        #expect(source.performed.isEmpty)
        #expect(store.lastError == .notRunning)

        await store.perform(.togglePlayPause)
        #expect(source.performed == [.play])
        #expect(!store.isLaunching)
    }

    @Test func aFailedCommandRollsBackTheOptimisticState() async {
        let source = FakeSource(state: Fixtures.state(at: clock.now))
        source.failure = .timedOut
        let store = makeStore([source])
        await store.perform(.pause)
        #expect(store.isPlaying)
        #expect(store.lastError == .timedOut)
    }

    @Test func aCommandTheSourceIgnoresTwiceEarnsAWarning() async {
        let source = FakeSource(state: Fixtures.state(at: clock.now))
        let store = makeStore([source])

        // Once: the display quietly reverts at the deadline.
        await store.perform(.pause)
        clock.advance(PendingIntents.lifetime + 0.1)
        source.push(Fixtures.state(position: 12, at: clock.now))
        #expect(store.isPlaying)
        #expect(store.warning == nil)

        // Twice in a row: say so.
        await store.perform(.pause)
        clock.advance(PendingIntents.lifetime + 0.1)
        source.push(Fixtures.state(position: 14, at: clock.now))
        #expect(store.isPlaying)
        #expect(store.warning != nil)

        store.dismissWarning()
        #expect(store.warning == nil)
    }

    @Test func undeterminedPermissionIsRequestedOnFirstUse() async {
        let source = FakeSource(state: Fixtures.state(at: clock.now, permission: .notDetermined))
        let store = makeStore([source])
        #expect(source.permissionRequests == 0)
        await store.perform(.pause)
        #expect(source.permissionRequests == 1)
        // The fake never grants it, so nothing is sent.
        #expect(source.performed.isEmpty)
    }

    @Test func seekingMovesTheClock() async {
        let source = FakeSource(state: Fixtures.state(position: 10, at: clock.now))
        let store = makeStore([source])
        await store.perform(.seek(to: 120))
        #expect(store.position(at: clock.now) == 120)
        #expect(source.performed == [.seek(to: 120)])
    }

    /// A pause between reports keeps the position the song reached, rather
    /// than snapping back to the last report while the source confirms it.
    @Test func aPauseKeepsThePositionReachedSinceTheLastReport() async {
        let source = FakeSource(state: Fixtures.state(position: 10, at: clock.now))
        let store = makeStore([source])
        clock.advance(1.5)
        await store.perform(.pause)
        #expect(!store.isPlaying)
        #expect(store.position(at: clock.now) == 11.5)
        #expect(store.position(at: clock.now.addingTimeInterval(5)) == 11.5)
    }

    /// A play from paused starts where the source paused, rather than running
    /// the time it sat paused forward.
    @Test func aPlayFromPausedStartsAtTheReportedPosition() async {
        let source = FakeSource(state: Fixtures.state(status: .paused, position: 10, at: clock.now))
        let store = makeStore([source])
        clock.advance(1.5)
        await store.perform(.play)
        #expect(store.isPlaying)
        #expect(store.position(at: clock.now) == 10)
        #expect(store.position(at: clock.now.addingTimeInterval(2)) == 12)
    }

    @Test func reportsTrackChangesWithListeningTime() {
        let source = FakeSource(state: Fixtures.state(at: clock.now))
        let store = makeStore([source])
        var events: [NowPlayingEvent] = []
        let observation = store.addObserver { events.append($0) }

        clock.advance(30)
        source.push(Fixtures.state(track: Fixtures.track("t2"), position: 0, at: clock.now))
        let expected = NowPlayingEvent.trackChanged(
            previous: Fixtures.track("t1"),
            current: Fixtures.track("t2"),
            source: source.id,
            listened: 30
        )
        #expect(events.contains(expected))

        observation.cancel()
        events.removeAll()
        source.push(Fixtures.state(track: Fixtures.track("t3"), position: 0, at: clock.now))
        #expect(events.isEmpty)
    }

    @Test func followsTheSourceThatStartsPlaying() {
        let first = FakeSource(id: SourceID("a"), state: Fixtures.state(status: .paused, at: clock.now))
        let second = FakeSource(id: SourceID("b"), state: Fixtures.state(track: Fixtures.track("b1"), status: .paused, at: clock.now))
        let store = makeStore([first, second])
        #expect(store.activeSourceID == first.id)

        second.push(Fixtures.state(track: Fixtures.track("b1"), status: .playing, at: clock.now))
        #expect(store.activeSourceID == second.id)
        #expect(store.lastActiveSourceID == second.id)
        #expect(store.track?.id == TrackID("b1"))

        store.preferredSourceID = first.id
        #expect(store.activeSourceID == first.id)
    }
}
