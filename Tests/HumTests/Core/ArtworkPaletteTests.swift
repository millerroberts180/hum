import HumCore
import Testing

@Suite("Artwork palette")
struct ArtworkPaletteTests {
    static let navy = PaletteColor(red: 0.08, green: 0.1, blue: 0.3)
    static let orange = PaletteColor(red: 0.95, green: 0.5, blue: 0.1)

    /// A navy cover with an orange square in the middle covering about a fifth of it.
    static func navyWithOrange(side: Int = 20) -> [PaletteColor?] {
        let patch = (side / 2 - 4)..<(side / 2 + 5)
        return (0..<side * side).map { index in
            patch.contains(index % side) && patch.contains(index / side) ? orange : navy
        }
    }

    @Test func theBorderSetsTheBackgroundAndTheColorfulPatchTheAccent() throws {
        let palette = ArtworkPalette.measure(grid: Self.navyWithOrange(), side: 20)
        #expect(palette.background.blue > palette.background.red)
        #expect(palette.isDark)
        let accent = try #require(palette.accent)
        #expect(accent.red > accent.blue)
    }

    @Test func textColorsAreLegibleOnTheBackground() {
        let palette = ArtworkPalette.measure(grid: Self.navyWithOrange(), side: 20)
        #expect(palette.primary.contrast(with: palette.background) >= ArtworkPalette.textContrast)
        #expect(palette.secondary.contrast(with: palette.background) >= ArtworkPalette.textContrast)
    }

    @Test func theSameCoverAlwaysGivesTheSamePalette() {
        // A noisy cover, so clustering has real choices to make.
        var state: UInt64 = 42
        let grid: [PaletteColor?] = (0..<40 * 40).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let bits = state >> 33
            return PaletteColor(
                red: Double(bits & 0xFF) / 255,
                green: Double((bits >> 8) & 0xFF) / 255,
                blue: Double((bits >> 16) & 0xFF) / 255
            )
        }
        let first = ArtworkPalette.measure(grid: grid, side: 40)
        let second = ArtworkPalette.measure(grid: grid, side: 40)
        #expect(first == second)
    }

    @Test func aGrayCoverHasNoAccent() {
        let gray = PaletteColor(red: 0.5, green: 0.5, blue: 0.5)
        let palette = ArtworkPalette.measure(grid: Array(repeating: gray, count: 100), side: 10)
        #expect(palette.accent == nil)
    }

    @Test func aTransparentCoverIsNeutral() {
        let palette = ArtworkPalette.measure(grid: Array(repeating: nil, count: 16), side: 4)
        #expect(palette == .neutral)
    }

    @Test func lightnessClampingKeepsHue() {
        let color = PaletteColor(hue: 0.6, saturation: 0.7, lightness: 0.1)
        let clamped = color.clampingLightness(to: 0.6...0.8)
        #expect(abs(clamped.hsl.lightness - 0.6) < 0.01)
        #expect(abs(clamped.hsl.hue - 0.6) < 0.01)
        #expect(PaletteColor.white.contrast(with: .black) > 20)
    }
}
