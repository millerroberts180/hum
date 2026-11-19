import CoreGraphics
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// Lists over the backdrop raise the accent for text, but a fill such as a
/// card's play button keeps the context's own accent: a shape needs 3:1, text
/// 4.5:1 (DESIGN.md §3.5.3). Drawn with the text variant, the circle went pale
/// and its glyph black in dark appearance.
@MainActor
@Suite("Accent fills over the backdrop")
struct BackdropAccentTests {
    /// 3:1 against black, so a fair dark-appearance accent, but short of 4.5:1
    /// against the dark window, so text over the backdrop has to be raised.
    static let deepBlue = PaletteColor(red: 0.1, green: 0.3, blue: 0.9)
    static let accent = AccentColors(onDark: deepBlue, onLight: deepBlue)

    @Test func aFillKeepsTheAccentTheBackdropWasGiven() throws {
        let pixels = try MissingArtworkTests.Pixels(try Self.render(
            SurfaceBackdrop(artwork: nil) {
                HStack(spacing: 0) {
                    Rectangle().fill(HumColor.accent).frame(width: 20, height: 20)
                    Rectangle().fill(HumColor.accent).frame(width: 20, height: 20).backdropAccentFill()
                }
            }
        ))
        let text = Self.color(pixels.pixel(x: 10, y: 10))
        let fill = Self.color(pixels.pixel(x: 30, y: 10))
        #expect(fill.isClose(to: Self.deepBlue), "fill \(fill)")
        // The lists' own accent was raised; the fill wasn't.
        #expect(text.oklch.lightness > Self.deepBlue.oklch.lightness + 0.05, "text \(text)")
        #expect(AccentResolver.content(on: Self.deepBlue) == .white)
    }

    @Test func outsideABackdropItChangesNothing() throws {
        let pixels = try MissingArtworkTests.Pixels(try Self.render(
            Rectangle().fill(HumColor.accent).frame(width: 40, height: 20).backdropAccentFill()
        ))
        #expect(Self.color(pixels.pixel(x: 20, y: 10)).isClose(to: Self.deepBlue))
    }

    @Test func textOverTheBackdropStillReads() throws {
        let window = PaletteColor(red: 0.196, green: 0.196, blue: 0.196)
        let raised = try #require(Self.accent.backdropText(regions: [], isDark: true, window: window).onDark)
        #expect(Self.deepBlue.contrast(with: window) < AccentResolver.textContrast)
        #expect(raised.contrast(with: window) >= AccentResolver.textContrast)
        // Light appearance is left for its own measure.
        #expect(Self.accent.backdropText(regions: [], isDark: true, window: window).onLight == Self.deepBlue)
    }

    static func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(content: view
            .frame(width: 40, height: 20)
            .environment(\.colorScheme, .dark)
            .environment(\.humAccent, accent))
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    static func color(_ pixel: [UInt8]) -> PaletteColor {
        PaletteColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}

private extension PaletteColor {
    /// Within a step of 8-bit rounding and color matching.
    func isClose(to other: PaletteColor) -> Bool {
        abs(red - other.red) < 0.03 && abs(green - other.green) < 0.03 && abs(blue - other.blue) < 0.03
    }
}
