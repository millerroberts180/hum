import Foundation
@testable import HumCore
@testable import HumSources
@testable import HumUI
import Testing

/// `--demo-attribution Spotify` shows what a Spotify listener sees (DESIGN.md
/// §1.3), with no app to open; without it the demo is as it was.
@MainActor
@Suite("The demo as Spotify")
struct SpotifyDemoParityTests {
    let clock = TestClock()

    /// The demo as the app puts it together for `attribution`.
    func demo(attribution: String?) -> (NowPlayingStore, LibraryStore, DemoSource) {
        let clock = clock
        let source = DemoSource(followsSpotify: DemoAttribution.namesSpotify(attribution), latency: .zero, now: { clock.now })
        let provider = DemoLibrary(source: source, attribution: attribution, listLatency: .zero, transferLatency: .zero)
        let nowPlaying = NowPlayingStore(sources: [source], preferredSourceID: .demo, now: { clock.now })
        nowPlaying.start()
        let library = LibraryStore(nowPlaying: nowPlaying, providers: [provider], now: { clock.now }, sleep: { _ in })
        return (nowPlaying, library, source)
    }

    @Test func asSpotifyItPlaysAndCantSave() async {
        let (nowPlaying, library, source) = demo(attribution: "Spotify")
        await drainMainActor()
        #expect(!nowPlaying.capabilities.contains(.favorite))
        // Repeat one with Spotify, too (DESIGN.md §5.2). The demo's is its
        // own, so it needs none of Hum's restarting.
        #expect(nowPlaying.capabilities.repeatCycle == [.off, .all, .one])
        #expect(!nowPlaying.capabilities.contains(.repeatOneByRestart))
        #expect(nowPlaying.capabilities.isSuperset(of: [.playPause, .skipNext, .skipPrevious, .seek, .volume, .shuffle, .repeatAll]))
        #expect(nowPlaying.toggleSaveAndConfirm() == nil)
        await drainMainActor()
        #expect(library.notice == nil)
        withExtendedLifetime(source) {}
    }

    @Test func asSpotifyItNamesNothingASongPlaysFrom() async {
        let (nowPlaying, _, source) = demo(attribution: "Spotify")
        await drainMainActor()
        let playlist = PlaybackContext(kind: .playlist, name: "Evening Mix")
        await source.play(DemoPlaylist.tracks, startingAt: 1, context: playlist)
        source.setContext(PlaybackContext(kind: .album, name: "Altitude Notes"))
        await drainMainActor()
        #expect(source.context == nil)
        #expect(source.state.snapshot.context == nil)
        #expect(nowPlaying.snapshot.context == nil)

        // Without the flag, the demo says where it plays from.
        let (_, _, plain) = demo(attribution: nil)
        await plain.play(DemoPlaylist.tracks, startingAt: 1, context: playlist)
        #expect(plain.state.snapshot.context == playlist)
        #expect(plain.state.capabilities.repeatCycle == [.off, .all, .one])
    }

    /// Spotify's app plays one song and offers no devices or saving.
    @Test func asSpotifyTheLibraryOnlyPlays() async {
        let (_, library, _) = demo(attribution: "Spotify")
        await drainMainActor()
        #expect(library.capabilities == [.playItems])
        #expect(!library.capabilities.contains(.devices))
        #expect(!library.capabilities.contains(.saveItems))
        library.loadDevices()
        await drainMainActor()
        #expect(library.devices.value == nil)
        let isUnavailable = if case .unavailable = library.devices.phase { true } else { false }
        #expect(isUnavailable)
    }

    @Test func asSpotifyMenusArePlayNowOnly() async throws {
        let (nowPlaying, library, _) = demo(attribution: "Spotify")
        await drainMainActor()
        let song = try #require(DemoPlaylist.tracks.first.map { LibraryTrack($0.track, artwork: nil, source: .demo) })
        let menu = TrackMenu.song(song, library: library)
        #expect(menu.entries == [.action(.playNow)])
        // Now has nothing to offer: no Save, and the demo has no links.
        #expect(TrackMenu.current(nowPlaying) == nil)
    }

    @Test(arguments: ["spotify", "SPOTIFY", "Spotify"])
    func theAttributionIsReadAsSpotifyWhateverItsCase(attribution: String) {
        let (_, library, _) = demo(attribution: attribution)
        #expect(library.capabilities == [.playItems])
    }

    @Test(arguments: [nil, "Tidal"] as [String?])
    func otherwiseTheDemoIsUnchanged(attribution: String?) async {
        let (nowPlaying, library, _) = demo(attribution: attribution)
        await drainMainActor()
        #expect(nowPlaying.capabilities.contains(.favorite))
        #expect(nowPlaying.capabilities.contains(.repeatOne))
        #expect(library.capabilities == [.playItems, .devices, .deviceSwitching, .saveItems])
        #expect(DemoSource.capabilities.contains(.favorite))
        library.loadDevices()
        await waitUntil { library.devices.phase == .loaded }
        #expect(library.devices.phase == .loaded)
    }
}
