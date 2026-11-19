import HumCore
import Testing

@Suite("Labels on the average color")
struct SwatchLabelsTests {
    static let fills: [PaletteColor] = [
        .black,
        .white,
        PaletteColor(red: 0.08, green: 0.1, blue: 0.3),   // navy
        PaletteColor(red: 0.95, green: 0.85, blue: 0.4),  // pale yellow
        PaletteColor(red: 0.46, green: 0.46, blue: 0.46), // mid gray, the hardest case
        PaletteColor(red: 0.9, green: 0.2, blue: 0.2),    // red
        PaletteColor(red: 0.1, green: 0.6, blue: 0.3),    // green
        PaletteColor(red: 0.3, green: 0.55, blue: 0.95),  // sky blue
    ]

    @Test func darkFillsGetWhiteAndLightFillsGetBlack() {
        #expect(SwatchLabels(fill: PaletteColor(red: 0.08, green: 0.1, blue: 0.3)).content == .white)
        #expect(SwatchLabels(fill: .black).isDark)
        #expect(SwatchLabels(fill: PaletteColor(red: 0.95, green: 0.85, blue: 0.4)).content == .black)
        #expect(!SwatchLabels(fill: .white).isDark)
    }

    @Test(arguments: fills)
    func everyTextRoleKeepsBodyTextContrast(fill: PaletteColor) {
        let labels = SwatchLabels(fill: fill)
        for nominal in [1.0, 0.72, 0.5] {
            let opacity = labels.opacity(nominal: nominal, ratio: SwatchLabels.textContrast)
            #expect(labels.color(opacity: opacity).contrast(with: fill) >= SwatchLabels.textContrast)
            #expect(opacity >= nominal)
        }
    }

    @Test func aRoleThatAlreadyReadsKeepsItsUsualOpacity() {
        let labels = SwatchLabels(fill: .black)
        #expect(labels.opacity(nominal: 0.72, ratio: SwatchLabels.textContrast) == 0.72)
        #expect(labels.opacity(nominal: 0.5, ratio: SwatchLabels.textContrast) == 0.5)
    }

    @Test func aMidToneFillRaisesSecondaryText() {
        let labels = SwatchLabels(fill: PaletteColor(red: 0.46, green: 0.46, blue: 0.46))
        #expect(labels.opacity(nominal: 0.5, ratio: SwatchLabels.textContrast) > 0.9)
    }
}
