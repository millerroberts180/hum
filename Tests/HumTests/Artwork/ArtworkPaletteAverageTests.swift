import HumCore
import Testing

@Suite("Artwork palette average")
struct ArtworkPaletteAverageTests {
    static let red = PaletteColor(red: 0.9, green: 0.1, blue: 0.1)
    static let blue = PaletteColor(red: 0.1, green: 0.1, blue: 0.9)

    @Test func aSolidCoverAveragesToItsOwnColor() {
        let palette = ArtworkPalette.measure(grid: Array(repeating: Self.red, count: 100), side: 10)
        #expect(palette.average.distanceSquared(to: Self.red) < 0.0001)
    }

    /// A blue frame around a red middle: the border color is blue, but the
    /// average sits between the two, weighted by area.
    @Test func theAverageCountsTheWholeCoverNotJustTheBorder() {
        let side = 10
        let grid: [PaletteColor?] = (0..<side * side).map { index in
            let x = index % side, y = index / side
            return (2..<8).contains(x) && (2..<8).contains(y) ? Self.red : Self.blue
        }
        let palette = ArtworkPalette.measure(grid: grid, side: side)
        #expect(palette.background.blue > palette.background.red)
        #expect(palette.average.distanceSquared(to: palette.background) > 0.01)
        #expect(palette.average.red > 0.3)
        #expect(palette.average.blue > 0.3)
    }

    @Test func transparentPixelsDontCount() {
        let side = 10
        let grid: [PaletteColor?] = (0..<side * side).map { $0 % 2 == 0 ? Self.red : nil }
        let palette = ArtworkPalette.measure(grid: grid, side: side)
        #expect(palette.average.distanceSquared(to: Self.red) < 0.0001)
    }

    @Test func aPaletteWithoutAnAverageUsesItsBackground() {
        let palette = ArtworkPalette(
            background: Self.blue, primary: .white, secondary: .white, tertiary: .white, accent: nil, isDark: true
        )
        #expect(palette.average == Self.blue)
    }
}
