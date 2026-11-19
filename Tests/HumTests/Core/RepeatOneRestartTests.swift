import Foundation
@testable import HumCore
import HumSources
import Testing

/// Hum's repeat one, for an app whose own repeat is only on or off, as
/// Spotify's is (DESIGN.md §5.2, §13.24): the app's repeat stays on, and the
/// store starts the song over just before it ends.
@MainActor
@Suite("Repeat one by restarting")
struct RepeatOneRestartTests {
    let clock = TestClock()
    let sleeper = StepSleeper()
    static let first = TrackID("t1")
    static let second = TrackID("t2")

    func makePlayer(position: TimeInterval = 10, repeating: Bool = false) -> OnOffRepeatPlayer {
        let clock = clock
        return OnOffRepeatPlayer(position: position, repeating: repeating, now: { clock.now })
    }

    func makeStore(_ source: any PlaybackSource) -> NowPlayingStore {
        let clock = clock
        let sleeper = sleeper
        let store = NowPlayingStore(sources: [source], now: { clock.now }, sleep: { await sleeper.sleep($0) })
        store.start()
        return store
    }

    /// A player 10 s into a 200 s song with One just chosen, and the re-read
    /// planned for 188 s from now.
    func playingWithOne() async -> (OnOffRepeatPlayer, NowPlayingStore) {
        let player = makePlayer()
        let store = makeStore(player)
        await store.perform(.setRepeat(.one))
        await waitUntil { sleeper.isWaiting(188) }
        return (player, store)
    }

    // MARK: Choosing One

    @Test func theRepeatButtonGoesOffAllOneAndTheAppHearsOnlyOnOrOff() async throws {
        let player = makePlayer()
        let store = makeStore(player)
        #expect(store.capabilities.contains(.repeatOneByRestart))
        #expect(store.capabilities.repeatCycle == [.off, .all, .one])
        var shown: [RepeatMode?] = []
        for _ in 0..<3 {
            let next = try #require(store.capabilities.nextRepeatMode(after: store.snapshot.repeatMode ?? .off))
            await store.perform(.setRepeat(next))
            shown.append(store.snapshot.repeatMode)
        }
        #expect(shown == [.all, .one, .off])
        // One keeps the app's repeat on; the app never hears of One.
        #expect(player.performed == [.setRepeat(.all), .setRepeat(.all), .setRepeat(.off)])
        #expect(store.lastError == nil)
    }

    /// From Off, One turns the app's repeat on.
    @Test func oneFromOffTurnsTheAppsRepeatOn() async {
        let (player, store) = await playingWithOne()
        #expect(player.performed == [.setRepeat(.all)])
        #expect(player.state.snapshot.repeatMode == .all)
        #expect(store.snapshot.repeatMode == .one)
    }

    // MARK: Starting over

    @Test func theSongStartsOverALeadBeforeItEnds() async {
        let (player, store) = await playingWithOne()
        #expect(sleeper.isWaiting(188))
        #expect(player.refreshes == 0)

        clock.advance(188)
        sleeper.elapse(188)
        await waitUntil { player.performed.last == .seek(to: 0) }
        // The store asked where the app really was before it moved anything.
        #expect(player.refreshes == 1)
        #expect(player.performed == [.setRepeat(.all), .seek(to: 0)])
        #expect(store.track?.id == Self.first)
        #expect(store.position(at: clock.now) == 0)
        #expect(store.snapshot.repeatMode == .one)

        // And again next time through, 198 s on.
        await waitUntil { sleeper.isWaiting(198) }
        #expect(sleeper.isWaiting(198))
        clock.advance(198)
        sleeper.elapse(198)
        await waitUntil { player.performed.count == 3 }
        #expect(player.performed == [.setRepeat(.all), .seek(to: 0), .seek(to: 0)])
    }

    @Test func eachTimeThroughCountsAsAPlayInHistory() async {
        let player = makePlayer(position: 0)
        let store = makeStore(player)
        let recorder = ListeningRecorder()
        var finished: [Listen] = []
        recorder.onFinish = { finished.append($0) }
        recorder.begin(with: store.snapshot, source: store.activeSourceID, at: clock.now)
        let clock = clock
        let observation = store.addObserver { event in
            recorder.handle(event, snapshot: store.snapshot, at: clock.now)
        }
        await store.perform(.setRepeat(.one))
        for round in 1...2 {
            await waitUntil { sleeper.isWaiting(198) }
            clock.advance(198)
            sleeper.elapse(198)
            await waitUntil { finished.count == round }
        }
        #expect(finished.count == 2)
        #expect(finished.map(\.trackID) == [Self.first, Self.first])
        #expect(finished.map(\.listened) == [198, 198])
        #expect(finished.allSatisfy { $0.counts })
        // The third time through is under way.
        #expect(recorder.current?.track.id == Self.first)
        withExtendedLifetime(observation) {}
    }

    /// The song starting over isn't a new song to the player window, only to
    /// History: the event names the same track twice.
    @Test func theRestartNamesTheSameSongTwice() async {
        let (player, store) = await playingWithOne()
        var changes: [NowPlayingEvent] = []
        let observation = store.addObserver { event in
            if case .trackChanged = event { changes.append(event) }
        }
        clock.advance(188)
        sleeper.elapse(188)
        await waitUntil { !changes.isEmpty }
        guard case .trackChanged(let previous, let current, let source, let listened) = changes.first else {
            Issue.record("No track change")
            return
        }
        #expect(previous?.id == Self.first)
        #expect(current?.id == Self.first)
        #expect(source == player.id)
        #expect(listened == 188)
        #expect(changes.count == 1)
        withExtendedLifetime(observation) {}
    }

    @Test func withNoAnswerTheStoresClockDecides() async {
        let (player, store) = await playingWithOne()
        player.answersRefresh = false
        clock.advance(188)
        sleeper.elapse(188)
        await waitUntil { sleeper.isWaiting(RepeatOneRestart.rereadTimeout) }
        #expect(player.refreshes == 1)
        #expect(player.performed == [.setRepeat(.all)])

        clock.advance(RepeatOneRestart.rereadTimeout)
        sleeper.elapse(RepeatOneRestart.rereadTimeout)
        await waitUntil { player.performed.last == .seek(to: 0) }
        #expect(player.performed == [.setRepeat(.all), .seek(to: 0)])
        withExtendedLifetime(store) {}
    }

    /// The re-read finds the song somewhere else (moved in the app since the
    /// last report): nothing is moved, and the restart is planned from there.
    @Test func anAnswerFarFromTheEndPlansAgain() async {
        let (player, store) = await playingWithOne()
        clock.advance(188)
        player.seekInAppQuietly(to: 50)
        sleeper.elapse(188)
        await waitUntil { sleeper.isWaiting(148) }
        #expect(sleeper.isWaiting(148))
        #expect(player.refreshes == 1)
        #expect(player.performed == [.setRepeat(.all)])
        withExtendedLifetime(store) {}
    }

    /// The re-read finds the song paused in the app: it stays where it is.
    @Test func anAnswerThatSaysPausedLeavesTheSongAlone() async {
        let (player, store) = await playingWithOne()
        clock.advance(188)
        player.pauseInAppQuietly()
        sleeper.elapse(188)
        await waitUntil { !store.isPlaying }
        await drainMainActor()
        #expect(player.refreshes == 1)
        #expect(player.performed == [.setRepeat(.all)])
        #expect(sleeper.waiting.isEmpty)
    }

    // MARK: What calls it off

    @Test func aPauseCallsOffTheRestartAndPlayPlansItAgain() async {
        let (player, store) = await playingWithOne()
        clock.advance(50)
        player.setPlayingInApp(false)
        await waitUntil { !sleeper.isWaiting(188) }
        #expect(!sleeper.isWaiting(188))
        #expect(!store.isPlaying)

        // However long it stays paused, nothing restarts.
        clock.advance(500)
        sleeper.elapseAll()
        await drainMainActor()
        #expect(player.performed == [.setRepeat(.all)])

        // Playing again from 60 s: 140 s left, so the re-read is 138 s off.
        await store.perform(.play)
        await waitUntil { sleeper.isWaiting(138) }
        #expect(sleeper.isWaiting(138))
        #expect(store.snapshot.repeatMode == .one)
    }

    @Test func aSeekPastTheRestartCallsItOffAndASeekBackPlansIt() async {
        let (player, store) = await playingWithOne()
        await store.perform(.seek(to: 199.5))
        await waitUntil { !sleeper.isWaiting(188) }
        #expect(!sleeper.isWaiting(188))
        #expect(!sleeper.waiting.contains { $0 < 1 })

        await store.perform(.seek(to: 100))
        await waitUntil { sleeper.isWaiting(98) }
        #expect(sleeper.isWaiting(98))
        #expect(player.performed == [.setRepeat(.all), .seek(to: 199.5), .seek(to: 100)])
    }

    @Test func choosingAllOrOffCallsItOff() async {
        let (player, store) = await playingWithOne()
        await store.perform(.setRepeat(.off))
        #expect(store.snapshot.repeatMode == .off)
        await waitUntil { !sleeper.isWaiting(188) }
        #expect(!sleeper.isWaiting(188))

        await store.perform(.setRepeat(.all))
        #expect(store.snapshot.repeatMode == .all)
        await drainMainActor()
        #expect(!sleeper.isWaiting(188))
        #expect(player.performed == [.setRepeat(.all), .setRepeat(.off), .setRepeat(.all)])
    }

    /// One was Hum's: turned off in the app, it ends, and turned back on
    /// there it's the app's own repeat, All.
    @Test func turningRepeatOffInTheAppEndsOne() async {
        let (player, store) = await playingWithOne()
        clock.advance(PendingIntents.lifetime)
        player.setRepeatingInApp(false)
        #expect(store.snapshot.repeatMode == .off)
        await waitUntil { !sleeper.isWaiting(188 - PendingIntents.lifetime) && !sleeper.isWaiting(188) }

        player.setRepeatingInApp(true)
        #expect(store.snapshot.repeatMode == .all)
        await drainMainActor()
        #expect(sleeper.waiting.isEmpty)
        #expect(player.performed == [.setRepeat(.all)])
    }

    /// One isn't saved: relaunched with the app's repeat on, it reads All.
    @Test func oneIsntKeptAcrossALaunch() async {
        let player = makePlayer(repeating: true)
        let store = makeStore(player)
        #expect(store.snapshot.repeatMode == .all)
        await drainMainActor()
        #expect(sleeper.waiting.isEmpty)
    }

    // MARK: Skipping

    @Test func nextAndPreviousKeepOne() async {
        let (player, store) = await playingWithOne()
        await store.perform(.next)
        #expect(store.track?.id == Self.second)
        #expect(store.snapshot.repeatMode == .one)
        // Planned again for the new song, from its start.
        await waitUntil { sleeper.isWaiting(198) && !sleeper.isWaiting(188) }
        #expect(sleeper.isWaiting(198))

        await store.perform(.previous)
        #expect(store.track?.id == Self.first)
        #expect(store.snapshot.repeatMode == .one)
        await drainMainActor()
        #expect(player.performed == [.setRepeat(.all), .next, .previous])
    }

    /// Next from Hum in the song's last seconds is a skip, not the song
    /// running out, so nothing brings it back.
    @Test func humsOwnNextNearTheEndIsLeftAlone() async {
        let (player, store) = await playingWithOne()
        clock.advance(188.5)
        await store.perform(.next)
        await drainMainActor()
        #expect(store.track?.id == Self.second)
        #expect(player.performed == [.setRepeat(.all), .next])
    }

    // MARK: When the song ends anyway

    /// The restart was missed (the Mac slept through it) and the app moved on
    /// by itself: Hum goes back with Previous Track, once.
    @Test func ifTheSongEndsAnywayItGoesBackOnce() async {
        let (player, store) = await playingWithOne()
        clock.advance(189.8)
        player.moveOnInApp()
        await waitUntil { player.performed.contains(.previous) }
        await waitUntil { store.track?.id == Self.first }
        #expect(store.track?.id == Self.first)
        #expect(store.snapshot.repeatMode == .one)
        await drainMainActor()
        #expect(player.performed == [.setRepeat(.all), .previous])
    }

    /// Spotify answers the seek before it takes it, so the song can still end
    /// first, though Hum's clock already reads 0: Hum goes back to it (§13.34).
    @Test func aRestartTheAppTookTooLateGoesBack() async {
        let (player, store) = await playingWithOne()
        player.takesSeeksTooLate = true
        clock.advance(188)
        sleeper.elapse(188)
        await waitUntil { player.performed.last == .seek(to: 0) }
        #expect(store.position(at: clock.now) == 0)

        // The song's real end, 2 s on: the app plays the next song.
        clock.advance(2)
        player.moveOnInApp()
        await waitUntil { player.performed.contains(.previous) }
        await waitUntil { store.track?.id == Self.first }
        #expect(store.track?.id == Self.first)
        #expect(store.snapshot.repeatMode == .one)
        await drainMainActor()
        #expect(player.performed == [.setRepeat(.all), .seek(to: 0), .previous])
    }

    /// Once the restart has had time to land, a skip in the app is the
    /// listener's own.
    @Test func aSkipInTheAppAfterARestartIsLeftAlone() async {
        let (player, store) = await playingWithOne()
        clock.advance(188)
        sleeper.elapse(188)
        await waitUntil { player.performed.last == .seek(to: 0) }
        clock.advance(10)
        player.moveOnInApp()
        await drainMainActor()
        #expect(store.track?.id == Self.second)
        #expect(player.performed == [.setRepeat(.all), .seek(to: 0)])
    }

    /// Next chosen in the app itself, well before the end, is the listener's
    /// own skip.
    @Test func aSkipInTheAppIsLeftAlone() async {
        let (player, store) = await playingWithOne()
        clock.advance(50)
        player.moveOnInApp()
        await drainMainActor()
        #expect(store.track?.id == Self.second)
        #expect(store.snapshot.repeatMode == .one)
        #expect(player.performed == [.setRepeat(.all)])
    }

    @Test func withOneOffASongEndingIsLeftAlone() async {
        let player = makePlayer()
        let store = makeStore(player)
        await store.perform(.setRepeat(.all))
        clock.advance(189.8)
        player.moveOnInApp()
        await drainMainActor()
        #expect(store.track?.id == Self.second)
        #expect(player.performed == [.setRepeat(.all)])
        #expect(sleeper.waiting.isEmpty)
    }

    // MARK: Apps with their own repeat one

    @Test func musicAndTheDemoRepeatOneThemselves() async {
        #expect(MusicApp.capabilities.contains(.repeatOne))
        #expect(!MusicApp.capabilities.contains(.repeatOneByRestart))
        #expect(!DemoSource.capabilities.contains(.repeatOneByRestart))
        #expect(!DemoSource.spotifyCapabilities.contains(.repeatOneByRestart))
        #expect(SpotifyApp.capabilities.contains(.repeatOneByRestart))

        // A source with its own repeat one is sent One, and nothing is planned.
        let source = FakeSource(state: Fixtures.state(at: clock.now))
        source.stateAfterCommand = { command, state in
            var state = state
            if case .setRepeat(let mode) = command { state.snapshot.repeatMode = mode }
            return state
        }
        let store = makeStore(source)
        await store.perform(.setRepeat(.one))
        #expect(source.performed == [.setRepeat(.one)])
        #expect(store.snapshot.repeatMode == .one)
        await drainMainActor()
        #expect(sleeper.waiting.isEmpty)

        // The demo as Spotify keeps its own, too.
        let clock = clock
        let demo = DemoSource(startsPlaying: true, followsSpotify: true, latency: .zero, now: { clock.now })
        let demoStore = makeStore(demo)
        await demoStore.perform(.setRepeat(.one))
        #expect(demo.state.snapshot.repeatMode == .one)
        #expect(demoStore.snapshot.repeatMode == .one)
        demoStore.stop()
    }

    // MARK: The pieces

    @Test func theReReadIsPlannedALeadBeforeTheEnd() {
        let date = clock.now
        let playing = PositionClock(position: 10, at: date, isAdvancing: true, duration: 200)
        var one = RepeatOneRestart()
        #expect(one.plan(track: Self.first, isPlaying: true, clock: playing, at: date) == nil)

        #expect(one.choose(.one, for: .spotifyApp) == .all)
        #expect(one.isOn(for: .spotifyApp))
        #expect(!one.isOn(for: .musicApp))
        #expect(!one.isOn(for: nil))
        let plan = one.plan(track: Self.first, isPlaying: true, clock: playing, at: date)
        #expect(plan == RepeatOneRestart.Plan(track: Self.first, at: date.addingTimeInterval(188)))
        #expect(one.plan(track: Self.first, isPlaying: false, clock: playing, at: date) == nil)
        #expect(one.plan(track: nil, isPlaying: true, clock: playing, at: date) == nil)
        let unknownLength = PositionClock(position: 10, at: date, isAdvancing: true, duration: nil)
        #expect(one.plan(track: Self.first, isPlaying: true, clock: unknownLength, at: date) == nil)
        // Past the moment, no plan.
        #expect(one.plan(track: Self.first, isPlaying: true, clock: playing, at: date.addingTimeInterval(188.5)) == nil)

        #expect(one.choose(.all, for: .spotifyApp) == .all)
        #expect(!one.isOn(for: .spotifyApp))
        #expect(one.choose(.off, for: .spotifyApp) == .off)
    }

    @Test func aFreshReportNearTheEndSaysStartOver() {
        let date = clock.now
        func report(_ track: TrackID, _ status: PlaybackStatus, at position: TimeInterval, takenBefore lag: TimeInterval = 0) -> PlaybackSnapshot {
            PlaybackSnapshot(
                track: Track(id: track, title: "Song", artist: "Band", duration: 200),
                status: status,
                position: position,
                timestamp: date.addingTimeInterval(-lag)
            )
        }
        #expect(RepeatOneRestart.shouldRestart(Self.first, after: report(Self.first, .playing, at: 199), at: date))
        // Taken a moment before: it has gone on since.
        #expect(RepeatOneRestart.shouldRestart(Self.first, after: report(Self.first, .playing, at: 197.5, takenBefore: 0.6), at: date))
        #expect(RepeatOneRestart.shouldRestart(Self.first, after: report(Self.first, .playing, at: 197.2), at: date))
        #expect(!RepeatOneRestart.shouldRestart(Self.first, after: report(Self.first, .playing, at: 190), at: date))
        #expect(!RepeatOneRestart.shouldRestart(Self.first, after: report(Self.first, .paused, at: 199), at: date))
        #expect(!RepeatOneRestart.shouldRestart(Self.first, after: report(Self.second, .playing, at: 199), at: date))
    }

    @Test func aSongRanOutOnlyNearItsEndAndWithoutHumsSkip() {
        let date = clock.now
        var one = RepeatOneRestart()
        func ranOut(remaining: TimeInterval?, next: TrackID? = Self.second, source: SourceID = .spotifyApp) -> Bool {
            one.ranOut(previous: Self.first, remaining: remaining, next: next, source: source, at: date)
        }
        #expect(!ranOut(remaining: 0.5))
        _ = one.choose(.one, for: .spotifyApp)
        #expect(ranOut(remaining: 0.5))
        #expect(ranOut(remaining: RepeatOneRestart.endWindow))
        #expect(!ranOut(remaining: 30))
        #expect(!ranOut(remaining: nil))
        #expect(!ranOut(remaining: 0.5, next: nil))
        #expect(!ranOut(remaining: 0.5, next: Self.first))
        #expect(!ranOut(remaining: 0.5, source: .musicApp))
        one.lastSkipAt = date.addingTimeInterval(-1)
        #expect(!ranOut(remaining: 0.5))
        one.lastSkipAt = date.addingTimeInterval(-RepeatOneRestart.skipWindow - 1)
        #expect(ranOut(remaining: 0.5))

        // Just sent back to 0, the clock reads the song's start; the app
        // playing on regardless still counts until a moment past the old end.
        one.willRestart(Self.first, remaining: 1.5, at: date.addingTimeInterval(-1))
        #expect(ranOut(remaining: 199))
        #expect(!one.ranOut(previous: Self.first, remaining: 199, next: Self.second, source: .spotifyApp,
                            at: date.addingTimeInterval(2.5)))
        #expect(!one.ranOut(previous: Self.second, remaining: 199, next: Self.first, source: .spotifyApp, at: date))
        one.lastSkipAt = date
        #expect(!ranOut(remaining: 199))
        one.lastSkipAt = nil
        one.songChanged()
        #expect(!ranOut(remaining: 199))
    }

    @Test func theTallyStartsOverForTheSameSong() {
        let start = clock.now
        var tally = ListeningTally()
        _ = tally.update(track: Self.first, isPlaying: true, at: start)
        #expect(tally.restart(at: start.addingTimeInterval(199)) == 199)
        #expect(tally.trackID == Self.first)
        #expect(tally.listened(at: start.addingTimeInterval(209)) == 10)
        // Paused, it starts over at zero and stays there.
        _ = tally.update(track: Self.first, isPlaying: false, at: start.addingTimeInterval(210))
        #expect(tally.restart(at: start.addingTimeInterval(300)) == 11)
        #expect(tally.listened(at: start.addingTimeInterval(400)) == 0)
    }
}

// MARK: - Test doubles

/// A player whose own repeat is only on or off, as Spotify's app is, with
/// Spotify's capabilities. It confirms each command as the app would, and
/// answers a refresh with a fresh report only while `answersRefresh` is on.
@MainActor
final class OnOffRepeatPlayer: PlaybackSource {
    let id = SourceID.spotifyApp
    let displayName = "On or Off"
    let appBundleIdentifier: String? = nil
    var onStateChange: (@MainActor (SourceState) -> Void)?
    private(set) var state: SourceState
    private(set) var performed: [PlaybackCommand] = []
    private(set) var refreshes = 0
    var answersRefresh = true
    /// Confirms a seek as Spotify does, reporting the new position, but goes
    /// on playing from where it was.
    var takesSeeksTooLate = false
    private var claimedSeek: (position: TimeInterval, at: Date)?

    private let tracks = [Fixtures.track("t1"), Fixtures.track("t2")]
    private let now: @MainActor () -> Date
    private var index = 0
    private var status: PlaybackStatus = .playing
    private var anchorPosition: TimeInterval
    private var anchorDate: Date
    private var repeating: Bool

    init(position: TimeInterval, repeating: Bool, now: @escaping @MainActor () -> Date) {
        self.now = now
        self.repeating = repeating
        anchorPosition = position
        anchorDate = now()
        state = SourceState(availability: .running, permission: .notRequired, capabilities: SpotifyApp.capabilities)
        state = makeState()
    }

    func start() {}
    func stop() {}
    func requestAutomationPermission() async {}
    func artwork(for track: Track) async -> Data? { nil }

    func refresh() {
        refreshes += 1
        if answersRefresh { publish() }
    }

    func perform(_ command: PlaybackCommand) async throws {
        performed.append(command)
        let date = now()
        switch command {
        case .play: setPlaying(true, at: date)
        case .pause: setPlaying(false, at: date)
        case .togglePlayPause: setPlaying(!status.isPlaying, at: date)
        case .next: go(to: index + 1, at: date)
        case .previous:
            if position(at: date) > 3 { seek(to: 0, at: date) } else { go(to: index - 1, at: date) }
        case .seek(let target):
            if takesSeeksTooLate { claimedSeek = (target, date) } else { seek(to: target, at: date) }
        // The app has no repeat one to set.
        case .setRepeat(.one): throw PlaybackError.unsupported(command)
        case .setRepeat(let mode): repeating = mode == .all
        default: throw PlaybackError.unsupported(command)
        }
        publish()
    }

    /// The app moves on to the next song by itself: the song ran out, or the
    /// listener chose Next there.
    func moveOnInApp() {
        go(to: index + 1, at: now())
        publish()
    }

    func setRepeatingInApp(_ on: Bool) {
        repeating = on
        publish()
    }

    func setPlayingInApp(_ playing: Bool) {
        setPlaying(playing, at: now())
        publish()
    }

    /// Moves within the song without reporting it, as between polls.
    func seekInAppQuietly(to target: TimeInterval) {
        seek(to: target, at: now())
    }

    /// Pauses without reporting it, as between polls.
    func pauseInAppQuietly() {
        setPlaying(false, at: now())
    }

    private var track: Track { tracks[index] }

    private func position(at date: Date) -> TimeInterval {
        let elapsed = status.isPlaying ? max(0, date.timeIntervalSince(anchorDate)) : 0
        return min(track.duration ?? 0, anchorPosition + elapsed)
    }

    private func seek(to target: TimeInterval, at date: Date) {
        anchorPosition = target
        anchorDate = date
    }

    private func setPlaying(_ playing: Bool, at date: Date) {
        seek(to: position(at: date), at: date)
        status = playing ? .playing : .paused
    }

    private func go(to newIndex: Int, at date: Date) {
        index = (newIndex + tracks.count) % tracks.count
        claimedSeek = nil
        seek(to: 0, at: date)
    }

    /// Where the app says it is: a seek it claimed to take, run on from then.
    private func reportedPosition(at date: Date) -> TimeInterval {
        guard let claimedSeek else { return position(at: date) }
        let elapsed = status.isPlaying ? max(0, date.timeIntervalSince(claimedSeek.at)) : 0
        return claimedSeek.position + elapsed
    }

    private func publish() {
        state = makeState()
        onStateChange?(state)
    }

    private func makeState() -> SourceState {
        let date = now()
        var next = state
        next.snapshot = PlaybackSnapshot(
            track: track,
            status: status,
            position: reportedPosition(at: date),
            timestamp: date,
            volume: 0.5,
            shuffle: false,
            repeatMode: repeating ? .all : .off
        )
        return next
    }
}

/// Sleeps a test ends by hand, picked by how long they asked for. A
/// cancelled sleep ends at once.
@MainActor
final class StepSleeper {
    private var pending: [(id: Int, seconds: TimeInterval, continuation: CheckedContinuation<Void, Never>)] = []
    private var nextID = 0

    /// How long each sleep waiting now asked for, in seconds.
    var waiting: [TimeInterval] { pending.map(\.seconds) }

    func isWaiting(_ seconds: TimeInterval) -> Bool {
        waiting.contains { abs($0 - seconds) < 0.001 }
    }

    func sleep(_ duration: Duration) async {
        let id = nextID
        nextID += 1
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending.append((id, seconds, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.end { $0.id == id } }
        }
    }

    /// Ends every sleep that asked for `seconds`.
    func elapse(_ seconds: TimeInterval) {
        end { abs($0.seconds - seconds) < 0.001 }
    }

    func elapseAll() {
        end { _ in true }
    }

    private func end(where matches: ((id: Int, seconds: TimeInterval)) -> Bool) {
        let ended = pending.filter { matches(($0.id, $0.seconds)) }
        pending.removeAll { matches(($0.id, $0.seconds)) }
        for sleep in ended { sleep.continuation.resume() }
    }
}
