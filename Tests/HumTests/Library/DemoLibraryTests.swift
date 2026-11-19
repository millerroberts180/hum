import Foundation
@testable import HumCore
import HumSources
import Testing

/// The demo's library: Play Now on Echo's and the History window's songs,
/// starting them in Evening Mix, and Favorite on any song (DESIGN.md §1.3).
@MainActor
@Suite("Demo library")
struct DemoLibraryTests {
    let clock = TestClock()

    func make() -> (DemoLibrary, DemoSource) {
        let clock = clock
        let source = DemoSource(startsPlaying: false, startPosition: 0, latency: .zero, now: { clock.now })
        return (DemoLibrary(source: source, listLatency: .zero, transferLatency: .zero), source)
    }

    @Test func playsASongInTheDemosPlaylist() async throws {
        let (library, source) = make()
        let song = try #require(source.playOrder.dropFirst(2).first?.track)
        try await library.play(.track(LibraryTrack(song, source: .demo), in: nil))
        #expect(source.state.snapshot.track?.id == song.id)
        #expect(source.currentIndex == 2)
        #expect(source.context?.name == "Evening Mix")
    }

    @Test func aSongThatIsntInTheDemoLeavesThePlayerAlone() async {
        let (library, source) = make()
        let before = source.state.snapshot.track?.id
        let elsewhere = LibraryTrack(id: TrackID("spotify:track:4uLU6hMCjMI75M1A2tKUQC"), title: "Undertow", artist: "Low Tide")
        await #expect(throws: LibraryError.failed("That song isn’t in the demo.")) {
            try await library.play(.track(elsewhere, in: nil))
        }
        #expect(source.state.snapshot.track?.id == before)
    }

    @Test func favoritesAnySong() async throws {
        let (library, source) = make()
        let song = LibraryTrack(try #require(source.playOrder.last?.track), source: .demo)
        #expect(await library.isSaved(song) == false)
        try await library.setSaved(true, track: song)
        #expect(source.favoriteIDs.contains(song.id))
        #expect(await library.isSaved(song) == true)
        try await library.setSaved(false, track: song)
        #expect(await library.isSaved(song) == false)
    }

    @Test func offersPlayNowFavoriteAndDevices() {
        let (library, _) = make()
        #expect(library.capabilities == [.playItems, .devices, .deviceSwitching, .saveItems])
        #expect(!library.requiresAppAccess)
    }
}

@MainActor
@Suite("Library store")
struct LibraryStoreTests {
    let clock = TestClock()

    func make() -> (LibraryStore, DemoLibrary, DemoSource) {
        let clock = clock
        let source = DemoSource(startsPlaying: false, startPosition: 0, latency: .zero, now: { clock.now })
        let library = DemoLibrary(source: source, listLatency: .zero, transferLatency: .zero)
        let nowPlaying = NowPlayingStore(sources: [source], preferredSourceID: .demo, now: { clock.now })
        let store = LibraryStore(nowPlaying: nowPlaying, providers: [library], now: { clock.now }, sleep: { _ in })
        return (store, library, source)
    }

    @Test func followsTheSourceAndWhatItCanDo() {
        let (store, library, _) = make()
        #expect(store.sourceID == .demo)
        #expect(store.capabilities == library.capabilities)
        #expect(store.unavailable == nil)
        #expect(store.provider === library)
    }

    @Test func playNowStartsTheSong() async throws {
        let (store, _, source) = make()
        let song = LibraryTrack(try #require(source.playOrder.dropFirst(3).first?.track), source: .demo)
        #expect(store.canPlay(.track(song, in: nil)))
        store.play(.track(song, in: nil))
        await waitUntil { source.state.snapshot.track?.id == song.id }
        #expect(source.state.snapshot.track?.id == song.id)
        #expect(store.failure == nil)
    }

    /// Favorite on a song in a list shows at once and is kept once the source
    /// agrees.
    @Test func favoriteShowsAtOnce() async throws {
        let (store, _, source) = make()
        let song = LibraryTrack(try #require(source.playOrder.last?.track), source: .demo)
        store.setSaved(true, track: song, announce: false)
        #expect(store.isSaved(song))
        await waitUntil { source.favoriteIDs.contains(song.id) }
        #expect(source.favoriteIDs.contains(song.id))
        #expect(store.isSaved(song))
    }
}
