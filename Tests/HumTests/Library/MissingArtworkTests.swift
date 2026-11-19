import CoreGraphics
@testable import HumUI
import SwiftUI
import Testing

/// The placeholder as drawn (DESIGN.md §3.4): a tile that fills its side, with
/// the glyph centered on it at just over half the side.
@MainActor
@Suite("Missing artwork")
struct MissingArtworkTests {
    static let scale: CGFloat = 2

    @Test(arguments: [24.0, 44.0, 160.0])
    func theTileFillsItsSide(_ side: CGFloat) throws {
        let image = try Self.render(side)
        #expect(image.width == Int(side * Self.scale))
        #expect(image.height == Int(side * Self.scale))
        let pixels = try Pixels(image)
        // The corners are the tile's fill, not empty.
        #expect(pixels.alpha(x: 0, y: 0) > 0)
        #expect(pixels.alpha(x: image.width - 1, y: image.height - 1) > 0)
    }

    @Test(arguments: [24.0, 44.0, 160.0])
    func theGlyphIsCenteredAndJustOverHalfTheTile(_ side: CGFloat) throws {
        let pixels = try Pixels(try Self.render(side))
        let ink = try #require(pixels.inkBounds())
        let full = side * Self.scale
        // A note's ink is a little shorter than its point size, which is 0.55
        // of the side.
        #expect(ink.height > full * 0.4)
        #expect(ink.height < full * 0.6)
        #expect(abs(ink.midX - full / 2) < full * 0.1)
        #expect(abs(ink.midY - full / 2) < full * 0.1)
    }

    @Test func aLargerTileHasALargerGlyph() throws {
        let small = try #require(try Pixels(try Self.render(44)).inkBounds())
        let large = try #require(try Pixels(try Self.render(160)).inkBounds())
        // In proportion to the side, within antialiasing.
        #expect(abs(large.height / small.height - 160.0 / 44.0) < 0.3)
    }

    static func render(_ side: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: MissingArtwork(side: side).environment(\.colorScheme, .light))
        renderer.scale = scale
        return try #require(renderer.cgImage)
    }

    /// The image's RGBA bytes.
    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) throws {
            let width = image.width, height = image.height
            self.width = width
            self.height = height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            try #require(drawn)
            self.bytes = bytes
        }

        func pixel(x: Int, y: Int) -> [UInt8] {
            let start = (y * width + x) * 4
            return Array(bytes[start..<start + 4])
        }

        func alpha(x: Int, y: Int) -> UInt8 { pixel(x: x, y: y)[3] }

        /// The box around every pixel that differs from the tile's corner.
        func inkBounds() -> CGRect? {
            let tile = pixel(x: 0, y: 0)
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where zip(pixel(x: x, y: y), tile).contains(where: { abs(Int($0) - Int($1)) > 3 }) {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }
}
