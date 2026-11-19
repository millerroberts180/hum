import CoreGraphics
import Foundation
import HumCore
@testable import HumSources
import ImageIO
import Testing

@Suite("Demo art")
struct DemoArtTests {
    @Test(arguments: DemoCover.allCases)
    func coversAreDeterministic(_ cover: DemoCover) throws {
        let first = try #require(DemoArtwork.render(cover, side: 160).flatMap(ArtStore.encode))
        let second = try #require(DemoArtwork.render(cover, side: 160).flatMap(ArtStore.encode))
        #expect(first == second)
    }

    /// The app paints many covers at once; each must come out the same as
    /// when painted alone.
    @Test func artIsTheSameWhenPaintedSideBySide() async throws {
        for cover in DemoCover.allCases {
            let alone = try #require(DemoArtwork.render(cover, side: 128).flatMap(ArtStore.encode))
            let together = await withTaskGroup(of: Data?.self) { group in
                for _ in 0..<8 {
                    group.addTask { DemoArtwork.render(cover, side: 128).flatMap(ArtStore.encode) }
                }
                return await group.reduce(into: [Data?]()) { $0.append($1) }
            }
            #expect(together.allSatisfy { $0 == alone }, "\(cover)")
        }
    }

    @Test(arguments: [600, 400, 128])
    func coversArePNGsOfTheRequestedSize(_ side: Int) async throws {
        for cover in DemoCover.allCases {
            let data = try #require(await DemoArtwork.pngData(for: cover, side: side))
            #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
            let image = try #require(Self.decode(data))
            #expect(image.width == side && image.height == side)
            // Opaque, as a photograph is.
            #expect(image.alphaInfo == .none || image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst)
        }
    }

    /// Only the demo's own covers are drawn; anything else has no art.
    @Test func onlyDemoCoversAreDrawn() {
        #expect(DemoLibrary.cover(forKey: "demo-cover:" + DemoCover.allCases[0].rawValue) == DemoCover.allCases[0])
        #expect(DemoLibrary.cover(forKey: "spotify:album:1") == nil)
        #expect(DemoLibrary.cover(forKey: "demo-elsewhere:1") == nil)
    }

    @Test func everyCoverLooksDifferent() throws {
        let images = try DemoCover.allCases.map { try #require(DemoArtwork.render($0, side: 48).flatMap(ArtStore.encode)) }
        #expect(Set(images).count == images.count)
    }

    /// The palette every cover yields is usable (§3.5.4): a real background,
    /// text that reads at 4.5:1 on it (§3.5.9), a secondary color distinct from
    /// the primary, and an accent on every cover that has color.
    @Test(arguments: DemoCover.allCases)
    func coversYieldLegiblePalettes(_ cover: DemoCover) throws {
        let image = try #require(DemoArtwork.render(cover, side: 200))
        let palette = ArtworkPalette.measure(image)
        Self.expectLegible(palette, "\(cover)")
        if cover == .rings {
            // Black type on cream: the accent may be absent, and the
            // background is light.
            #expect(!palette.isDark)
        } else {
            #expect(palette.accent != nil, "\(cover) has no accent")
        }
    }

    /// Generous, so a debug build on a busy machine passes; a release build
    /// paints a 600-pixel cover in tens of milliseconds.
    @Test func coversPaintWithinBudget() throws {
        let clock = ContinuousClock()
        for cover in DemoCover.allCases {
            let elapsed = clock.measure { _ = DemoArtwork.render(cover, side: 600) }
            #expect(elapsed < .seconds(2), "\(cover) took \(elapsed)")
        }
    }

    @Test func storeKeepsWhatItPaintedAndEvictsTheOldest() throws {
        let store = ArtStore(budget: 3000)
        var paints = 0
        func image() -> CGImage? {
            paints += 1
            return DemoArtwork.render(.rings, side: 16)
        }
        let first = try #require(store.png("a", side: 16, render: image))
        let again = try #require(store.png("a", side: 16, render: image))
        #expect(first == again)
        #expect(paints == 1)
        // A different size is a different picture.
        _ = store.png("a", side: 17) { DemoArtwork.render(.rings, side: 17) }
        #expect(store.count == 2)
        // Filling past the budget lets the least recently used go.
        for index in 0..<20 {
            _ = store.png("fill-\(index)", side: 16, render: image)
        }
        #expect(store.count < 22)
        _ = store.png("a", side: 16, render: image)
        #expect(paints > 1)
    }

    @Test func titlesChooseFittingStyles() {
        #expect(CoverArt.style(forTitle: "Golden Rivers", seed: 1) == .sea)
        #expect(CoverArt.style(forTitle: "Late Stations", seed: 1) == .bokeh)
        #expect(CoverArt.style(forTitle: "Paper Letters", seed: 1) == .type)
        #expect(CoverArt.style(forTitle: "Northern Weather", seed: 1) == .dusk)
        #expect(CoverArt.style(forTitle: "Summer Gardens", seed: 1) == .mesh)
    }

    @Test func typeBreaksTitlesIntoDisplayLines() {
        #expect(TypeCover.lines("Ash & Paper") == ["Ash", "& Paper"])
        #expect(TypeCover.lines("Long Drive Home") == ["Long", "Drive", "Home"])
        #expect(TypeCover.lines("Under the Overpass") == ["Under", "the Overpass"])
        #expect(TypeCover.lines("Echoes") == ["Echoes"])
        #expect(TypeCover.lines("The") == ["The"])
    }

    // MARK: Helpers

    static func expectLegible(_ palette: ArtworkPalette, _ name: String) {
        #expect(palette != .neutral, "\(name) fell back to the neutral palette")
        let bar = ArtworkPalette.textContrast - 0.05
        #expect(palette.primary.contrast(with: palette.background) >= bar, "\(name) primary")
        #expect(palette.secondary.contrast(with: palette.background) >= bar, "\(name) secondary")
        #expect(palette.primary != palette.secondary, "\(name) secondary isn't distinct")
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
