import CoreGraphics
import Foundation
import HumCore
import Testing

@Suite("Backdrop contrast")
struct BackdropContrastTests {
    /// The system window backgrounds, dark and light.
    static let darkWindow = PaletteColor(red: 0.196, green: 0.196, blue: 0.196)
    static let lightWindow = PaletteColor(red: 0.925, green: 0.925, blue: 0.925)
    static let systemBlue = PaletteColor(red: 0.04, green: 0.52, blue: 1)
    /// A warm cover that left blue titles unreadable before the wash.
    static let sunset = PaletteColor(red: 0.93, green: 0.48, blue: 0.36)

    static let covers: [PaletteColor] = [
        .white, .black, sunset,
        PaletteColor(red: 1, green: 0.85, blue: 0.1),
        PaletteColor(red: 0.1, green: 0.8, blue: 0.9),
        PaletteColor(red: 0.2, green: 0.1, blue: 0.5),
    ]

    /// Vertical stripes: white, red, black.
    static func stripes() throws -> CGImage {
        let side = 240
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let stripes: [[CGFloat]] = [[1, 1, 1, 1], [1, 0, 0, 1], [0, 0, 0, 1]]
        for (index, components) in stripes.enumerated() {
            context.setFillColor(try #require(CGColor(colorSpace: space, components: components)))
            context.fill(CGRect(x: index * 80, y: 0, width: 80, height: side))
        }
        return try #require(context.makeImage())
    }

    @Test func regionsAverageTheCoverInAGrid() throws {
        let regions = BackdropContrast.regions(of: try Self.stripes())
        #expect(regions.count == 9)
        for row in 0..<3 {
            let left = regions[row * 3], middle = regions[row * 3 + 1], right = regions[row * 3 + 2]
            #expect(left.luminance > 0.9)
            #expect(middle.red > 0.9 && middle.green < 0.15)
            #expect(right.luminance < 0.02)
        }
    }

    @Test func darkAppearanceMeasuresTheLightestPart() {
        let window = Self.darkWindow
        let hardest = BackdropContrast.hardest([.black, Self.sunset, .white], isDark: true, window: window)
        #expect(hardest == BackdropContrast.backdrop(over: .white, isDark: true, window: window))
        let light = BackdropContrast.hardest([.black, Self.sunset, .white], isDark: false, window: Self.lightWindow)
        #expect(light == BackdropContrast.backdrop(over: .black, isDark: false, window: Self.lightWindow))
        #expect(BackdropContrast.hardest([], isDark: true, window: window) == window)
    }

    @Test(arguments: [true, false])
    func labelsReadOnAnyCover(isDark: Bool) {
        let window = isDark ? Self.darkWindow : Self.lightWindow
        let ink: PaletteColor = isDark ? .white : .black
        for cover in Self.covers {
            let backdrop = BackdropContrast.backdrop(over: cover, isDark: isDark, window: window)
            // The label color is the ink at 85%.
            let label = ink.mixed(with: backdrop, amount: 0.15)
            #expect(label.contrast(with: backdrop) >= 4.5, "cover \(cover)")
        }
    }

    @Test(arguments: [true, false])
    func accentTextReadsEverywhereOnTheBackdrop(isDark: Bool) throws {
        let window = isDark ? Self.darkWindow : Self.lightWindow
        let accent = try #require(BackdropContrast.textAccent(Self.systemBlue, regions: Self.covers, isDark: isDark, window: window))
        for cover in Self.covers {
            let backdrop = BackdropContrast.backdrop(over: cover, isDark: isDark, window: window)
            #expect(accent.contrast(with: backdrop) >= AccentResolver.textContrast, "cover \(cover)")
        }
        // Lighter for dark appearance, darker for light, and still blue.
        let moved = accent.oklch.lightness - Self.systemBlue.oklch.lightness
        #expect(isDark ? moved > 0 : moved < 0)
        #expect(accent.blue > accent.red && accent.blue > accent.green)
    }

    @Test func aWarmCoverNeedsALighterBlue() throws {
        let window = Self.darkWindow
        let backdrop = BackdropContrast.backdrop(over: Self.sunset, isDark: true, window: window)
        #expect(Self.systemBlue.contrast(with: backdrop) < AccentResolver.textContrast)
        let adjusted = try #require(BackdropContrast.textAccent(Self.systemBlue, regions: [Self.sunset], isDark: true, window: window))
        #expect(adjusted.contrast(with: backdrop) >= AccentResolver.textContrast)
    }

    @Test func anAccentAlreadyLegibleIsKept() {
        let pale = PaletteColor(red: 0.6, green: 0.8, blue: 1)
        let kept = BackdropContrast.textAccent(pale, regions: [.black], isDark: true, window: Self.darkWindow)
        #expect(kept == pale)
    }
}
