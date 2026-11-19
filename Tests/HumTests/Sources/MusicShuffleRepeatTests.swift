import Foundation
@testable import HumCore
@testable import HumSources
import Testing

/// The checks §13.34 added for Spotify, run for Music too. Music has its own
/// repeat one, so Hum sends it each mode as it is and never starts a song over
/// itself; what Hum sets holds against a late reply, and what changes in Music
/// shows on the player.
@MainActor
@Suite("Music's shuffle and repeat")
struct MusicShuffleRepeatTests {
    let clock = TestClock()
    let sleeper = StepSleeper()

    /// A stand-in for Music: its capabilities, playing 10 s into a 200 s song.
    /// It reports each shuffle and repeat Hum sets, unless `takesSettersLate`.
    func makeMusic(repeatMode: RepeatMode = .off, shuffle: Bool = false, takesSettersLate: Bool = false) -> FakeSource {
        var state = Fixtures.state(at: clock.now, capabilities: MusicApp.capabilities)
        state.snapshot.repeatMode = repeatMode
        state.snapshot.shuffle = shuffle
        let music = FakeSource(id: .musicApp, displayName: "Music", appBundleIdentifier: MusicApp.bundleIdentifier, state: state)
        if !takesSettersLate {
            music.stateAfterCommand = { command, state in
                var state = state
                switch command {
                case .setRepeat(let mode): state.snapshot.repeatMode = mode
                case .setShuffle(let on): state.snapshot.shuffle = on
                default: break
                }
                return state
            }
        }
        return music
    }

    func makeStore(_ source: any PlaybackSource) -> NowPlayingStore {
        let clock = clock
        let sleeper = sleeper
        let store = NowPlayingStore(sources: [source], now: { clock.now }, sleep: { await sleeper.sleep($0) })
        store.start()
        return store
    }

    /// `music`'s state as Music reports it now, changed by `change`.
    func report(_ music: FakeSource, _ change: (inout PlaybackSnapshot) -> Void) -> SourceState {
        var state = music.state
        state.snapshot.timestamp = clock.now
        change(&state.snapshot)
        return state
    }

    // MARK: What Music is told

    @Test func musicIsToldEachModeByName() {
        #expect(MusicApp.commandScript(for: .setRepeat(.off))?.contains("set song repeat to off") == true)
        #expect(MusicApp.commandScript(for: .setRepeat(.all))?.contains("set song repeat to all") == true)
        #expect(MusicApp.commandScript(for: .setRepeat(.one))?.contains("set song repeat to one") == true)
        #expect(MusicApp.commandScript(for: .setShuffle(true))?.contains("set shuffle enabled to true") == true)
        #expect(MusicApp.commandScript(for: .setShuffle(false))?.contains("set shuffle enabled to false") == true)
        // Spotify, by contrast, hears only on or off.
        #expect(SpotifyApp.commandScript(for: .setRepeat(.one)) == nil)
        #expect(SpotifyApp.commandScript(for: .setRepeat(.all))?.contains("set repeating to true") == true)
    }

    @Test(arguments: [("off", RepeatMode.off), ("all", .all), ("one", .one), ("One", .one)])
    func musicsAnswerNamesEachMode(_ reply: String, _ mode: RepeatMode) {
        let value = ScriptValue.list([
            .string("playing"), .int(40), .bool(true), .string(reply),
            .string("ABC"), .string("Song"), .string("Band"), .string("Record"),
            .double(245), .double(3), .bool(false),
        ])
        let snapshot = MusicApp.parseState(value, at: clock.now)
        #expect(snapshot?.repeatMode == mode)
        #expect(snapshot?.shuffle == true)
    }

    // MARK: The repeat button

    @Test func theRepeatButtonGoesOffAllOneAndMusicHearsEachMode() async throws {
        let music = makeMusic()
        let store = makeStore(music)
        #expect(!store.capabilities.contains(.repeatOneByRestart))
        #expect(store.capabilities.repeatCycle == [.off, .all, .one])
        var shown: [RepeatMode?] = []
        for _ in 0..<3 {
            let next = try #require(store.capabilities.nextRepeatMode(after: store.snapshot.repeatMode ?? .off))
            await store.perform(.setRepeat(next))
            shown.append(store.snapshot.repeatMode)
        }
        #expect(shown == [.all, .one, .off])
        #expect(music.performed == [.setRepeat(.all), .setRepeat(.one), .setRepeat(.off)])
        #expect(store.lastError == nil)
    }

    /// Music repeats the song itself: near the end Hum plans nothing, and the
    /// song giving way to another sends nothing back.
    @Test func withOneOnHumLeavesTheEndToMusic() async {
        let music = makeMusic()
        let store = makeStore(music)
        await store.perform(.setRepeat(.one))
        await drainMainActor()
        #expect(sleeper.waiting.isEmpty)

        clock.advance(189)
        music.push(report(music) { $0.position = 199 })
        await drainMainActor()
        clock.advance(1)
        music.push(report(music) {
            $0.track = Fixtures.track("t2")
            $0.position = 0
        })
        await drainMainActor()
        #expect(music.performed == [.setRepeat(.one)])
        #expect(store.track?.id == TrackID("t2"))
        #expect(store.snapshot.repeatMode == .one)
        #expect(sleeper.waiting.isEmpty)
    }

    @Test func shuffleTurnsTheOtherWay() async {
        let music = makeMusic(shuffle: false)
        let store = makeStore(music)
        await store.perform(.setShuffle(true))
        #expect(store.snapshot.shuffle == true)
        await store.perform(.setShuffle(false))
        #expect(store.snapshot.shuffle == false)
        #expect(music.performed == [.setShuffle(true), .setShuffle(false)])
    }

    // MARK: Changes made in Music

    @Test func aChangeMadeInMusicShows() async {
        let music = makeMusic()
        let store = makeStore(music)
        for mode: RepeatMode in [.one, .all, .off] {
            clock.advance(1)
            music.push(report(music) {
                $0.repeatMode = mode
                $0.shuffle = mode != .off
            })
            #expect(store.snapshot.repeatMode == mode)
            #expect(store.snapshot.shuffle == (mode != .off))
        }
        #expect(music.performed.isEmpty)
    }

    // MARK: A late reply

    /// A reply already on its way when Hum set One still says All; the player
    /// keeps One until Music agrees.
    @Test func aLateReplyDoesNotFlickBack() async {
        let music = makeMusic(repeatMode: .all, takesSettersLate: true)
        let store = makeStore(music)
        await store.perform(.setRepeat(.one))
        #expect(store.snapshot.repeatMode == .one)

        clock.advance(0.5)
        music.push(report(music) { $0.repeatMode = .all })
        #expect(store.snapshot.repeatMode == .one)

        clock.advance(0.3)
        music.push(report(music) { $0.repeatMode = .one })
        #expect(store.snapshot.repeatMode == .one)
        #expect(store.warning == nil)
    }

    /// Music never took it: once the hold runs out, its word is final.
    @Test func aModeMusicNeverTookRevertsOnTime() async {
        let music = makeMusic(repeatMode: .off, takesSettersLate: true)
        let store = makeStore(music)
        await store.perform(.setRepeat(.all))
        #expect(store.snapshot.repeatMode == .all)

        clock.advance(PendingIntents.lifetime + 0.1)
        music.push(report(music) { $0.repeatMode = .off })
        #expect(store.snapshot.repeatMode == .off)
    }

    /// The source's own hold, as `ScriptedAppSource` runs it for Music:
    /// Music's three modes hold like Spotify's two.
    @Test func theSourcesHoldKeepsMusicsOne() {
        let start = clock.now
        func reply(at offset: TimeInterval, shuffle: Bool, repeatMode: RepeatMode) -> PlaybackSnapshot {
            PlaybackSnapshot(
                track: Fixtures.track("a"), status: .playing, position: 150,
                timestamp: start.addingTimeInterval(offset), volume: 0.4,
                shuffle: shuffle, repeatMode: repeatMode
            )
        }
        var hold = SetterHold()
        hold.record(.setRepeat(.one), track: TrackID("a"), at: start)
        hold.record(.setShuffle(false), track: TrackID("a"), at: start)
        let stale = hold.apply(to: reply(at: 0.3, shuffle: true, repeatMode: .all))
        #expect(stale.repeatMode == .one)
        #expect(stale.shuffle == false)
        _ = hold.apply(to: reply(at: 0.6, shuffle: false, repeatMode: .one))
        #expect(hold.isEmpty)
        // A change made in Music straight after shows at once.
        let changed = hold.apply(to: reply(at: 0.9, shuffle: true, repeatMode: .off))
        #expect(changed.repeatMode == .off)
        #expect(changed.shuffle == true)
    }
}
