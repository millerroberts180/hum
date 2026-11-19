import HumCore
@testable import HumUI
import Testing

@Suite("Accent colors")
struct AccentColorsTests {
    static let red = PaletteColor(red: 0.9, green: 0.2, blue: 0.2)
    static let blue = PaletteColor(red: 0.2, green: 0.4, blue: 0.95)

    @Test func bothBackdropsReachTheContrastBar() throws {
        let colors = AccentColors(base: Self.blue, system: Self.red, lightBackground: .white)
        let onDark = try #require(colors.onDark)
        let onLight = try #require(colors.onLight)
        #expect(onDark.contrast(with: .black) >= AccentResolver.glyphContrast)
        #expect(onLight.contrast(with: .white) >= AccentResolver.glyphContrast)
    }

    @Test func interpolationStartsAndEndsOnTheEndpoints() throws {
        let from = AccentColors(onDark: Self.red, onLight: Self.red)
        let to = AccentColors(onDark: Self.blue, onLight: Self.blue)
        let start = try #require(from.interpolated(to: to, fraction: 0).onDark)
        let end = try #require(from.interpolated(to: to, fraction: 1).onDark)
        #expect(start.distanceSquared(to: Self.red) < 1e-6)
        #expect(end.distanceSquared(to: Self.blue) < 1e-6)
        let middle = try #require(from.interpolated(to: to, fraction: 0.5).onLight)
        #expect(middle.distanceSquared(to: Self.red) > 1e-3)
        #expect(middle.distanceSquared(to: Self.blue) > 1e-3)
    }

    @Test func aMissingColorSwitchesHalfway() {
        let from = AccentColors(onDark: nil, onLight: Self.red)
        let to = AccentColors(onDark: Self.blue, onLight: Self.blue)
        #expect(from.interpolated(to: to, fraction: 0.3).onDark == nil)
        #expect(from.interpolated(to: to, fraction: 0.7).onDark == Self.blue)
    }
}
