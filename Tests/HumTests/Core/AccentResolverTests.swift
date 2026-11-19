import HumCore
import Testing

@Suite("Accent resolver")
struct AccentResolverTests {
    static let system = PaletteColor(red: 0, green: 0.48, blue: 1)
    static let white = PaletteColor.white

    @Test func albumModeWithoutAnAccentFallsBackToSystem() throws {
        #expect(ArtworkPalette.neutral.accent == nil)
        // The system blue already reads at 3:1 on black and on white, so it comes
        // back as it is.
        let onDark = try #require(AccentResolver.accent(mode: .album, palette: .neutral, custom: nil, system: Self.system, on: .dark))
        #expect(onDark == PaletteColor(red: 0, green: 0.48, blue: 1))
        let onLight = try #require(AccentResolver.accent(
            mode: .album, palette: .neutral, custom: nil, system: Self.system, on: .light(background: Self.white)
        ))
        #expect(onLight == PaletteColor(red: 0, green: 0.48, blue: 1))
    }

    @Test func aDarkAccentOnDarkIsLightenedNotSwapped() throws {
        let navy = PaletteColor(red: 0.05, green: 0.05, blue: 0.25)
        let resolved = try #require(AccentResolver.accent(mode: .custom, palette: nil, custom: navy, system: Self.system, on: .dark))
        // Its own hue, lighter, rather than the system blue.
        #expect(resolved != PaletteColor(red: 0, green: 0.48, blue: 1))
        #expect(resolved.oklch.lightness > navy.oklch.lightness)
        #expect(abs(resolved.oklch.hue - navy.oklch.hue) < 0.1) // radians
    }

    @Test func accentsReachTheContrastBarOnBothBackdrops() throws {
        let navy = PaletteColor(red: 0.05, green: 0.05, blue: 0.25)
        let onDark = try #require(AccentResolver.adjust(navy, on: .dark, ratio: AccentResolver.glyphContrast))
        #expect(onDark.contrast(with: .black) >= AccentResolver.glyphContrast)

        let pale = PaletteColor(red: 1, green: 0.95, blue: 0.6)
        let onLight = try #require(AccentResolver.adjust(pale, on: .light(background: Self.white), ratio: AccentResolver.glyphContrast))
        #expect(onLight.contrast(with: Self.white) >= AccentResolver.glyphContrast)
    }

    @Test func customModeUsesTheCustomColor() throws {
        let green = PaletteColor(red: 0.1, green: 0.8, blue: 0.3)
        let resolved = try #require(AccentResolver.accent(mode: .custom, palette: nil, custom: green, system: Self.system, on: .dark))
        #expect(resolved.distanceSquared(to: green) < 0.01)
    }

    @Test func contentOnAnAccentIsWhiteOrBlack() {
        #expect(AccentResolver.content(on: PaletteColor(red: 0.1, green: 0.2, blue: 0.7)) == .white)
        #expect(AccentResolver.content(on: PaletteColor(red: 1, green: 0.9, blue: 0.3)) == .black)
    }
}
