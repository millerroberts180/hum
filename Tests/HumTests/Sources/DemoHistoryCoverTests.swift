import Foundation
import HumCore
@testable import HumSources
import Testing

/// Every song in the demo history has a cover, so History and Echo's Top lists
/// show no placeholders (DESIGN.md §3.6).
@Suite("Demo history covers")
struct DemoHistoryCoverTests {
    let catalog = DemoPlaylist.tracks.map(\.track)

    @Test(arguments: [DemoHistory.defaultSeed, 7, 42])
    func everyListenHasACover(_ seed: UInt64) {
        let listens = DemoHistory.generate(catalog: catalog, endingAt: HistoryFixtures.now, calendar: HistoryFixtures.calendar, seed: seed)
        #expect(!listens.isEmpty)
        let missing = Set(listens.filter { DemoPlaylist.cover(for: $0.trackID, album: $0.album) == nil }.map(\.title))
        #expect(missing.isEmpty, "No cover for \(missing.sorted())")
    }

    /// The singles aren't on any demo album, so each has a cover of its own,
    /// not one a starting song already shows.
    @Test func theSinglesHaveTheirOwnCovers() throws {
        let singles = DemoHistory.extraTracks(for: catalog).filter { track in
            !catalog.contains { $0.album == track.album }
        }
        #expect(singles.map(\.title).sorted() == ["Northbound", "Paper Boats"])
        let covers = try singles.map { try #require(DemoPlaylist.cover(for: $0.id, album: $0.album)) }
        #expect(Set(covers).count == singles.count)
        #expect(Set(covers).isDisjoint(with: DemoPlaylist.tracks.map(\.cover)))
    }

    @Test func aSongOnADemoAlbumKeepsTheAlbumsCover() {
        let song = Track(id: TrackID("demo:harbor-static"), title: "Harbor Static", artist: "Marlow Fields", album: "Coastline Hours")
        #expect(DemoPlaylist.cover(for: song.id, album: song.album) == .tide)
        #expect(DemoPlaylist.cover(for: TrackID("demo:elsewhere"), album: "Elsewhere") == nil)
    }
}
