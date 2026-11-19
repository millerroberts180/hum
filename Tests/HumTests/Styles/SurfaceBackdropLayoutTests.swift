import CoreGraphics
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// History and Status sit on the backdrop in the card's own shape: Big Art
/// keeps its portrait (DESIGN.md §7.2). The backdrop's cover is filled past
/// a portrait card, to a square as tall as it, and once laid the page out as
/// wide as that, clipped on both sides.
@MainActor
@Suite("Backdrop layout")
struct SurfaceBackdropLayoutTests {
    typealias Pixels = MissingArtworkTests.Pixels

    /// A square cover of one color.
    static func artwork() throws -> ArtworkImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try #require(context.makeImage())
        let color = PaletteColor(red: 0.3, green: 0.5, blue: 0.7)
        let palette = ArtworkPalette(
            background: color, primary: color, secondary: color, tertiary: color,
            accent: nil, isDark: false, average: color
        )
        return ArtworkImage(key: "backdrop-layout", cgImage: image, palette: palette)
    }

    /// A page with a red mark at its leading edge and a green one at its
    /// trailing edge, on the backdrop in `size`.
    func render(_ size: CGSize) throws -> Pixels {
        let artwork = try Self.artwork()
        let view = SurfaceBackdrop(artwork: artwork) {
            HStack(spacing: 0) {
                Color(red: 1, green: 0, blue: 0).frame(width: 8)
                Spacer(minLength: 0)
                Color(red: 0, green: 1, blue: 0).frame(width: 8)
            }
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try Pixels(try #require(renderer.cgImage))
    }

    /// Big Art's narrowest and default cards, and the square the others
    /// grow to.
    @Test(arguments: [CGSize(width: 220, height: 381), CGSize(width: 280, height: 441), CGSize(width: 300, height: 300)])
    func thePageTakesTheCardsWidth(size: CGSize) throws {
        let pixels = try render(size)
        try #require(pixels.width == Int(size.width) && pixels.height == Int(size.height))
        let y = Int(size.height / 2)
        let leading = pixels.pixel(x: 2, y: y)
        let trailing = pixels.pixel(x: Int(size.width) - 3, y: y)
        #expect(leading[0] > 200 && leading[1] < 60 && leading[2] < 60, "leading edge: \(leading)")
        #expect(trailing[1] > 200 && trailing[0] < 60 && trailing[2] < 60, "trailing edge: \(trailing)")
        // The backdrop fills the card behind the page.
        let middle = pixels.pixel(x: Int(size.width / 2), y: y)
        #expect(middle[3] == 255)
        #expect(middle[0] < middle[2], "the cover's blue under the wash: \(middle)")
    }
}
