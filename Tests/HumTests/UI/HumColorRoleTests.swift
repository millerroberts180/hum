@testable import HumUI
import HumCore
import SwiftUI
import Testing

/// Increase Contrast's text roles (DESIGN.md §3.5.9).
@Suite("Color roles")
struct HumColorRoleTests {
    static func material(_ role: HumColor.Role, isDark: Bool = false, increasedContrast: Bool) -> Color {
        HumColor.color(role, context: .material, isDark: isDark, increasedContrast: increasedContrast, accent: .fallback)
    }

    @Test func increaseContrastStepsEachTextRoleUpOneOffArtwork() {
        #expect(Self.material(.secondaryLabel, increasedContrast: false) == Color(nsColor: .secondaryLabelColor))
        #expect(Self.material(.secondaryLabel, increasedContrast: true) == Color(nsColor: .labelColor))
        #expect(Self.material(.tertiaryLabel, increasedContrast: false) == Color(nsColor: .tertiaryLabelColor))
        #expect(Self.material(.tertiaryLabel, increasedContrast: true) == Color(nsColor: .secondaryLabelColor))
        #expect(Self.material(.tertiaryLabel, isDark: true, increasedContrast: true) == Color(nsColor: .secondaryLabelColor))
    }

    @Test func overArtworkTheWhitesRiseTo100And90And72() {
        #expect(HumColor.artworkOpacity(.label, increasedContrast: true) == 1)
        #expect(HumColor.artworkOpacity(.secondaryLabel, increasedContrast: true) == 0.9)
        #expect(HumColor.artworkOpacity(.tertiaryLabel, increasedContrast: true) == 0.72)
        #expect(HumColor.artworkOpacity(.tertiaryLabel, increasedContrast: false) == 0.5)
    }

    static func scrubber(_ role: HumColor.Role, _ context: HumColorContext, isDark: Bool = false, increasedContrast: Bool = false) -> Color {
        HumColor.color(role, context: context, isDark: isDark, increasedContrast: increasedContrast, accent: .fallback)
    }

    /// Apple's white scrubber (§5.2): white, white 30%, white 60% over art and
    /// dark material; `label` and `label` 20% on light material.
    @Test func theScrubberIsWhiteOverArtAndDarkMaterialAndLabelOnLight() {
        for (context, isDark) in [(HumColorContext.artwork, false), (.artwork, true), (.material, true)] {
            #expect(Self.scrubber(.scrubberFill, context, isDark: isDark) == .white)
            #expect(Self.scrubber(.scrubberTrack, context, isDark: isDark) == .white.opacity(0.3))
            #expect(Self.scrubber(.scrubberTime, context, isDark: isDark) == .white.opacity(0.6))
        }
        let label = Color(nsColor: .labelColor)
        #expect(Self.scrubber(.scrubberFill, .material) == label)
        #expect(Self.scrubber(.scrubberTrack, .material) == label.opacity(0.2))
        #expect(Self.scrubber(.scrubberTime, .material) == label.opacity(0.6))
    }

    @Test func theScrubberNeverTakesTheAccent() {
        let accent = Self.scrubber(.accent, .artwork)
        for context in [HumColorContext.artwork, .material] {
            #expect(Self.scrubber(.scrubberFill, context) != accent)
        }
    }

    @Test func increaseContrastLiftsTheScrubbersTrackAndTimes() {
        #expect(Self.scrubber(.scrubberTrack, .artwork, increasedContrast: true) == .white.opacity(0.45))
        #expect(Self.scrubber(.scrubberTime, .artwork, increasedContrast: true) == .white.opacity(0.85))
        #expect(Self.scrubber(.scrubberFill, .artwork, increasedContrast: true) == .white)
    }

    /// On a backdrop known only by its estimated color (Big Art), the times
    /// rise to 4.5:1 against it.
    @Test func onABackdropTheScrubberTimesKeepTheirContrast() {
        let gray = PaletteColor(red: 0.46, green: 0.46, blue: 0.46)
        let labels = SwatchLabels(fill: gray)
        let raised = labels.opacity(nominal: 0.6, ratio: SwatchLabels.textContrast)
        #expect(raised > 0.6)
        #expect(Self.scrubber(.scrubberTime, .swatch(labels)) == Color(labels.content).opacity(raised))
        #expect(Self.scrubber(.scrubberFill, .swatch(labels)) == Color(labels.content))
    }
}
