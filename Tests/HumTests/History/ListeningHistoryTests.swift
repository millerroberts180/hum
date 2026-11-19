import Foundation
@testable import HumCore
import Testing

@MainActor
@Suite("Recording listening history")
struct ListeningHistoryTests {
    let clock = TestClock(HistoryFixtures.now)
    let source: FakeSource
    let nowPlaying: NowPlayingStore
    let settings = SettingsStore(fileURL: nil)

    init() {
        let clock = clock
        source = FakeSource(state: Fixtures.state(track: Fixtures.track("t1"), position: 0, at: clock.now))
        nowPlaying = NowPlayingStore(sources: [source], preferredSourceID: nil, now: { clock.now })
        nowPlaying.start()
    }

    func makeHistory(_ store: HistoryStore? = nil) throws -> ListeningHistory {
        let clock = clock
        let history = ListeningHistory(
            store: try store ?? HistoryStore(url: nil),
            nowPlaying: nowPlaying,
            settings: settings,
            artworkCache: ArtworkCache(directory: nil),
            calendar: HistoryFixtures.calendar,
            now: { clock.now }
        )
        history.start()
        return history
    }

    /// Play for `seconds`, then report `track` (or a stop).
    func play(_ seconds: TimeInterval, thenSwitchTo track: String?) {
        clock.advance(seconds)
        source.push(Fixtures.state(track: track.map { Fixtures.track($0) }, status: track == nil ? .stopped : .playing, position: 0, at: clock.now))
    }

    func setPaused(_ paused: Bool, track: String = "t1", position: TimeInterval) {
        source.push(Fixtures.state(track: Fixtures.track(track), status: paused ? .paused : .playing, position: position, at: clock.now))
    }

    // MARK: Loading

    @Test func historyIsNotLoadedUntilEchoHasBeenRead() async throws {
        let history = try makeHistory()
        #expect(!history.hasLoaded)
        history.refresh()
        await history.settle()
        // Read, and empty: now "Nothing saved yet." is true.
        #expect(history.hasLoaded)
        #expect(history.echo.listenCount == 0)
    }

    // MARK: Recording

    @Test func aTrackChangeRecordsTheListen() async throws {
        let history = try makeHistory()
        play(120, thenSwitchTo: "t2")
        await history.settle()

        let listens = try await history.store.listens()
        #expect(listens.count == 1)
        let listen = try #require(listens.first)
        #expect(listen.trackID == TrackID("t1"))
        #expect(listen.listened == 120)
        #expect(listen.counts)
        #expect(listen.ending == .partial)
        #expect(listen.startedAt == HistoryFixtures.now)
        #expect(listen.source == source.id)
        #expect(history.revision > 0)
    }

    @Test func anEarlySwitchIsASkipAndDoesNotCount() async throws {
        let history = try makeHistory()
        play(8, thenSwitchTo: "t2")
        await history.settle()
        let listen = try #require(try await history.store.listens().first)
        #expect(listen.ending == .skipped)
        #expect(!listen.counts)
    }

    @Test func pausedTimeNeverCounts() async throws {
        let history = try makeHistory()
        clock.advance(20)
        setPaused(true, position: 20)
        clock.advance(300)
        setPaused(false, position: 20)
        play(40, thenSwitchTo: "t2")
        await history.settle()
        #expect(try await history.store.listens().first?.listened == 60)
    }

    @Test func sleepNeverCounts() async throws {
        let history = try makeHistory()
        clock.advance(30)
        history.systemWillSleep()
        // The player never reported a pause; the Mac was simply asleep.
        clock.advance(3_600)
        history.systemDidWake()
        play(30, thenSwitchTo: "t2")
        await history.settle()
        #expect(try await history.store.listens().first?.listened == 60)
    }

    // MARK: Pausing collection

    @Test func pausedCollectionRecordsNothing() async throws {
        let history = try makeHistory()
        history.setCollecting(false)
        #expect(!settings.history.isCollecting)
        play(120, thenSwitchTo: "t2")
        play(200, thenSwitchTo: "t3")
        clock.advance(100)
        setPaused(true, track: "t3", position: 100)
        await history.settle()
        history.stop()

        #expect(try await history.store.count() == 0)
        #expect(try await history.store.takePending() == nil)
    }

    @Test func pausingDropsTheListenInProgress() async throws {
        let history = try makeHistory()
        clock.advance(100)
        setPaused(true, position: 100)
        await history.settle()
        history.setCollecting(false)
        await history.settle()
        #expect(try await history.store.takePending() == nil)

        // Resuming starts fresh from now.
        history.setCollecting(true)
        setPaused(false, position: 100)
        play(50, thenSwitchTo: "t2")
        await history.settle()
        let listens = try await history.store.listens()
        #expect(listens.map(\.listened) == [50])
    }

    // MARK: Quitting and crashing

    @Test func quittingStoresTheListenInProgress() async throws {
        let history = try makeHistory()
        clock.advance(100)
        await history.settle()
        history.stop()

        let listen = try #require(try await history.store.listens().first)
        #expect(listen.listened == 100)
        #expect(listen.ending == .partial)
        #expect(try await history.store.takePending() == nil)
    }

    @Test func aPauseCheckpointsTheListen() async throws {
        let history = try makeHistory()
        clock.advance(100)
        setPaused(true, position: 100)
        await history.settle()
        let pending = try #require(try await history.store.takePending())
        #expect(pending.trackID == TrackID("t1"))
        #expect(pending.listened == 100)
    }

    @Test func aListenInterruptedByACrashIsRecovered() async throws {
        let store = try HistoryStore(url: nil)
        let track = Fixtures.track("lost")
        let start = HistoryFixtures.daysAgo(1)
        try await store.savePending(PendingListen(track: track, source: .demo, context: nil, startedAt: start, lastPlayedAt: start.addingTimeInterval(150), listened: 150))

        let history = try makeHistory(store)
        await history.settle()
        let listen = try #require(try await store.listens().first)
        #expect(listen.trackID == TrackID("lost"))
        #expect(listen.listened == 150)
        #expect(listen.endedAt == start.addingTimeInterval(150))
        #expect(listen.counts)
    }

    @Test func aRecoveredListenThatWasAlreadyStoredIsKeptOnce() async throws {
        let store = try HistoryStore(url: nil)
        let track = Fixtures.track("once")
        let start = HistoryFixtures.daysAgo(1)
        let pending = PendingListen(track: track, source: .demo, context: nil, startedAt: start, lastPlayedAt: start.addingTimeInterval(150), listened: 150)
        try await store.insert(#require(pending.finished(exit: .stopped, wasPlaying: false)))
        try await store.savePending(pending)

        let history = try makeHistory(store)
        await history.settle()
        #expect(try await store.count() == 1)
    }

    // MARK: Removing and erasing

    @Test func aRemovedListenCanBeUndone() async throws {
        let history = try makeHistory()
        play(120, thenSwitchTo: "t2")
        await history.settle()
        let listen = try #require(try await history.store.listens().first)

        history.remove([listen])
        await history.settle()
        #expect(try await history.store.count() == 0)
        #expect(history.lastRemoved == [listen])

        history.undoRemove()
        await history.settle()
        #expect(try await history.store.listens() == [listen])
        #expect(history.lastRemoved.isEmpty)
    }

    @Test func restoringAnOlderRemovalKeepsTheLatestUndo() async throws {
        let history = try makeHistory()
        play(120, thenSwitchTo: "t2")
        play(120, thenSwitchTo: "t3")
        await history.settle()
        let listens = try await history.store.listens()
        history.remove([listens[0]])
        await history.settle()
        history.remove([listens[1]])
        await history.settle()

        history.restore([listens[0]])
        await history.settle()
        #expect(history.lastRemoved == [listens[1]])
        #expect(try await history.store.listens() == [listens[0]])
    }

    @Test func erasingStartsTheListenInProgressOver() async throws {
        let history = try makeHistory()
        play(120, thenSwitchTo: "t2")
        clock.advance(100)
        history.eraseAll()
        play(50, thenSwitchTo: "t3")
        await history.settle()

        let listens = try await history.store.listens()
        #expect(listens.map(\.trackID) == [TrackID("t2")])
        #expect(listens.first?.listened == 50)
        #expect(try await history.store.trackedSince() == listens.first?.startedAt)
    }
}
