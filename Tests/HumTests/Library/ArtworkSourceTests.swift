import CoreGraphics
import Foundation
import HumCore
@testable import HumSources
@testable import HumUI
import Testing

/// Each song's art says where it came from, so Echo and the History window
/// fetch it from its own source (DESIGN.md §3.6.1), even in a list that mixes
/// sources.
@MainActor
@Suite("Artwork knows its source")
struct ArtworkSourceTests {
    @Test func nowsSongTakesTheSourcePlayingIt() {
        let track = Track(id: TrackID("spotify:track:t1"), title: "Song", artist: "Artist", album: "Album",
                          artworkURL: URL(string: "https://i.scdn.co/image/ab67"))
        #expect(LibraryTrack(track, source: .spotifyApp).artwork?.source == .spotifyApp)
        #expect(LibraryTrack(track).artwork?.source == nil)
    }

    /// Art cached before Hum recorded the source still loads.
    @Test func artCachedWithoutASourceStillDecodes() throws {
        let json = Data(#"{"key":"music:track-art:1"}"#.utf8)
        let artwork = try JSONDecoder().decode(LibraryArtwork.self, from: json)
        #expect(artwork.key == "music:track-art:1")
        #expect(artwork.source == nil)
        let again = try JSONDecoder().decode(LibraryArtwork.self, from: JSONEncoder().encode(LibraryArtwork(key: "a", source: .musicApp)))
        #expect(again.source == .musicApp)
    }

    // MARK: Resolution

    @Test func artThatDoesntSayTakesTheLibrarysSource() {
        let (store, _) = Self.store(following: .spotifyApp)
        #expect(store.sourceID == .spotifyApp)
        #expect(store.artworkSource(for: LibraryArtwork(key: "old")) == .spotifyApp)
        #expect(store.artworkSource(for: nil) == .spotifyApp)
        #expect(store.artworkSource(for: LibraryArtwork(key: "m", source: .musicApp)) == .musicApp)
    }

    static func store(following id: SourceID) -> (LibraryStore, NowPlayingStore) {
        let source = FakeSource(id: id, state: Fixtures.state(status: .paused, at: Date(timeIntervalSince1970: 0)))
        let nowPlaying = NowPlayingStore(sources: [source], preferredSourceID: id)
        let store = LibraryStore(nowPlaying: nowPlaying, providers: [SourcedLibrary(id)], sleep: { _ in })
        return (store, nowPlaying)
    }
}

/// Echo's and Status's text is measured against the cover's regions, whichever
/// app the cover came from (§3.6.1).
@Suite("Backdrop under any cover")
struct CoverBackdropContrastTests {
    @Test func everyCoverIsMeasuredByItsRegions() throws {
        let average = PaletteColor(red: 0.2, green: 0.4, blue: 0.6)
        let white = PaletteColor(red: 1, green: 1, blue: 1)
        let palette = ArtworkPalette(
            background: white, primary: white, secondary: white, tertiary: white,
            accent: nil, isDark: false, average: average
        )
        let image = try Self.halves()
        let artwork = ArtworkImage(key: "https://i.scdn.co/image/ab67", cgImage: image, palette: palette)
        let regions = BackdropContrast.regions(of: artwork)
        #expect(regions.count == 9)
        #expect(regions == BackdropContrast.regions(of: image))
        #expect(regions != [average])
    }

    /// Left half black, right half white.
    static func halves() throws -> CGImage {
        let side = 24
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side / 2, height: side))
        return try #require(context.makeImage())
    }
}

/// A library that serves one source and nothing else.
@MainActor
final class SourcedLibrary: LibraryProvider {
    let sourceID: SourceID
    let displayName = "Library"
    var onChange: (@MainActor () -> Void)?
    let capabilities: SourceCapabilities = []
    let unavailable: LibraryUnavailable? = nil

    init(_ sourceID: SourceID) {
        self.sourceID = sourceID
    }
}
