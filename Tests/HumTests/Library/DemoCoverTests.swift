import Foundation
import HumCore
@testable import HumSources
import Testing

/// One song, one cover: Now shows the cover Echo shows (DESIGN.md §3.6).
@MainActor
@Suite("Demo songs keep their album's cover")
struct DemoCoverTests {
    let clock = TestClock()

    /// A song Echo plays shows its own cover on Now, not the one before it.
    @Test func aSongPlayedFromEchoKeepsItsCover() async throws {
        let clock = clock
        let source = DemoSource(startsPlaying: false, startPosition: 0, latency: .zero, now: { clock.now })
        let library = DemoLibrary(source: source, listLatency: .zero)
        let entry = try #require(source.playOrder.dropFirst(2).first)
        let song = LibraryTrack(
            entry.track,
            artwork: LibraryArtwork(key: "demo-cover:\(entry.cover.rawValue)", source: .demo),
            source: .demo
        )
        #expect(DemoLibrary.cover(of: song) == entry.cover)

        try await library.play(.track(song, in: nil))
        #expect(source.playOrder[source.currentIndex].track.id == song.id)
        let shown = await source.artwork(for: Track(id: song.id, title: song.title, artist: song.artist))
        #expect(shown == (await DemoArtwork.pngData(for: entry.cover)))
        // The cover the player started with would be a different one.
        let first = try #require(source.playOrder.first)
        try #require(first.cover != entry.cover)
        #expect(shown != (await DemoArtwork.pngData(for: first.cover)))
    }

    @Test func songsWithOtherArtHaveNoDrawnCover() {
        let song = LibraryTrack(id: TrackID("demo:x"), title: "X", artist: "Y", artwork: LibraryArtwork(key: "demo-art:3", source: .demo))
        #expect(DemoLibrary.cover(of: song) == nil)
        #expect(DemoLibrary.cover(of: LibraryTrack(id: TrackID("demo:y"), title: "X", artist: "Y")) == nil)
    }
}
