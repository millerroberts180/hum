import Foundation
import HumCore
import Testing

/// The cover on screen keeps the source it came from until the next cover
/// replaces it, not the source that just took over.
@MainActor
@Suite("Displayed artwork source")
struct DisplayedArtworkSourceTests {
    let clock = TestClock()

    func makeSources() -> (spotify: FakeSource, music: FakeSource) {
        let spotify = FakeSource(id: .spotifyApp, displayName: "Spotify", state: Fixtures.state(track: Fixtures.track("s1"), at: clock.now))
        spotify.artworkData = ThumbnailCacheTests.png(width: 8, height: 8)
        let music = FakeSource(id: .musicApp, displayName: "Music", state: Fixtures.state(track: Fixtures.track("m1"), at: clock.now))
        return (spotify, music)
    }

    func makeStore(_ sources: [FakeSource], preferred: SourceID) -> NowPlayingStore {
        let clock = clock
        let store = NowPlayingStore(sources: sources, preferredSourceID: preferred, now: { clock.now })
        store.start()
        return store
    }

    /// Lets the store's artwork load finish.
    func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func spotifysCoverKeepsItsSourceUntilMusicsArrives() async {
        let (spotify, music) = makeSources()
        let store = makeStore([spotify, music], preferred: .spotifyApp)
        await waitFor { store.artwork != nil }
        #expect(store.artworkSourceID == .spotifyApp)

        music.artworkData = ThumbnailCacheTests.png(width: 6, height: 6)
        store.preferredSourceID = .musicApp
        // Music is active, but its art hasn't loaded: Spotify's cover is still drawn.
        #expect(store.activeSourceID == .musicApp)
        #expect(store.artwork != nil)
        #expect(store.displayedArtworkSource == .spotifyApp)

        await waitFor { store.artworkSourceID == .musicApp }
        #expect(store.artwork?.pixelSize == CGSize(width: 6, height: 6))
        #expect(store.displayedArtworkSource == .musicApp)
    }

    @Test func withoutACoverTheActiveSourceDecides() async {
        let (spotify, music) = makeSources()
        spotify.artworkData = nil
        let store = makeStore([spotify, music], preferred: .musicApp)
        #expect(store.artwork == nil)
        #expect(store.displayedArtworkSource == .musicApp)

        store.preferredSourceID = .spotifyApp
        #expect(store.displayedArtworkSource == .spotifyApp)
    }

    @Test func aCoverThatFailsToLoadDoesNotKeepTheOldSource() async {
        let (spotify, music) = makeSources()
        let store = makeStore([spotify, music], preferred: .spotifyApp)
        await waitFor { store.artwork != nil }

        // Music has no art for its track, so the load ends with no cover.
        store.preferredSourceID = .musicApp
        await waitFor { store.artwork == nil }
        #expect(store.artworkSourceID == nil)
        #expect(store.displayedArtworkSource == .musicApp)
    }
}
