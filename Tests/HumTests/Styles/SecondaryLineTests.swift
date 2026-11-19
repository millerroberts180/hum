import CoreGraphics
@testable import HumUI
import SwiftUI
import Testing

/// The "Artist — Album" line (DESIGN.md §3.3, §5.3). The album truncates
/// first, but never to a sliver too narrow for its ellipsis, which the demo's
/// long artist did on Big Art; then the artist truncates.
@MainActor
@Suite("Secondary line")
struct SecondaryLineTests {
    typealias Pixels = MissingArtworkTests.Pixels

    @Test func everythingFitsAtItsOwnWidth() {
        let widths = SecondaryLineLayout.widths(artist: 90, dash: 14, album: 60, available: 196)
        #expect(widths.artist == 90)
        #expect(widths.album == 60)
    }

    @Test func theAlbumTruncatesFirst() {
        let widths = SecondaryLineLayout.widths(artist: 100, dash: 14, album: 120, available: 196)
        #expect(widths.artist == 100)
        #expect(widths.album == 82)
    }

    /// The demo's long artist in Big Art's narrowest column.
    @Test func theAlbumStopsAtItsFloorAndThenTheArtistTruncates() {
        let widths = SecondaryLineLayout.widths(artist: 290, dash: 14, album: 120, available: 196)
        #expect(widths.album == SecondaryLineLayout.albumFloor)
        #expect(widths.artist == 196 - 14 - SecondaryLineLayout.albumFloor)
    }

    @Test func anAlbumShorterThanTheFloorKeepsItsWidth() {
        let widths = SecondaryLineLayout.widths(artist: 290, dash: 14, album: 20, available: 196)
        #expect(widths.album == 20)
        #expect(widths.artist == 162)
    }

    @Test func nothingGoesPastTheRoom() {
        let widths = SecondaryLineLayout.widths(artist: 290, dash: 14, album: 120, available: 30)
        #expect(widths.artist == 0)
        #expect(widths.album == 16)
    }

    /// Blocks stand in for the artist, the dash and the album: drawn in 196,
    /// each starts where the last ends, at the widths above.
    @Test func theLayoutPlacesTheWidths() throws {
        let view = SecondaryLineLayout {
            Color(red: 1, green: 0, blue: 0).frame(idealWidth: 290, idealHeight: 10)
            Color(red: 0, green: 1, blue: 0).frame(idealWidth: 14, idealHeight: 10)
            Color(red: 0, green: 0, blue: 1).frame(idealWidth: 120, idealHeight: 10)
        }
        .frame(width: 196, height: 10, alignment: .leading)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let pixels = try Pixels(try #require(renderer.cgImage))
        try #require(pixels.width == 196)

        func channel(atX x: Int) -> Int? {
            let pixel = pixels.pixel(x: x, y: 5)
            return (0..<3).first { pixel[$0] > 200 && pixel[3] > 200 }
        }
        let artistEnd = Int(196 - 14 - SecondaryLineLayout.albumFloor)
        #expect(channel(atX: 0) == 0)
        #expect(channel(atX: artistEnd - 1) == 0)
        #expect(channel(atX: artistEnd) == 1)
        #expect(channel(atX: artistEnd + 13) == 1)
        #expect(channel(atX: artistEnd + 14) == 2)
        #expect(channel(atX: 195) == 2)
    }
}
