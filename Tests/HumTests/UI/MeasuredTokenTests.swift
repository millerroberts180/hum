import AppKit
import SwiftUI
@testable import HumUI
import Testing

@Suite("Measured player tokens")
@MainActor
struct MeasuredTokenTests {
    /// The system window radius on macOS 15. On macOS 26 it grows with the
    /// player, so the smallest isn't a pill and the largest isn't a slab.
    @Test func thePanelRadiusIsTheSystemsOnMacOS15AndScalesWithinLimitsOnMacOS26() {
        if #available(macOS 26, *) {
            #expect(Radius.panel(side: 168) == 13)
            #expect(Radius.panel(side: 280) == 21)
            #expect(Radius.panel(side: 640) == 26)
            // Clamped at both ends, beyond the sizes the player allows.
            #expect(Radius.panel(side: 100) == 12)
            #expect(Radius.panel(side: 1000) == 26)
            let sides = stride(from: CGFloat(168), through: 640, by: 8).map(Radius.panel(side:))
            #expect(zip(sides, sides.dropFirst()).allSatisfy { $0 <= $1 })
        } else {
            for side: CGFloat in [168, 280, 640] {
                #expect(Radius.panel(side: side) == 10)
            }
        }
    }

    @Test func timeIsCalloutAtMAndLAndCaptionAtS() {
        #expect(HumType.time.style(for: .small) == .caption)
        #expect(HumType.time.style(for: .medium) == .callout)
        #expect(HumType.time.style(for: .large) == .callout)
        #expect(HumType.time.weight == .regular)
        // Over artwork, one step heavier.
        #expect(HumType.time.weight.heavier == .medium)
    }

    /// The song title stands a step above the artist line (§13.20): 15 pt at S
    /// and M, 17 at L; a bar's text-only title is 13.
    @Test func theTitleIsTitle3AtSAndMAndTitle2AtL() {
        #expect(HumType.trackTitle.style(for: .small) == .title3)
        #expect(HumType.trackTitle.style(for: .medium) == .title3)
        #expect(HumType.trackTitle.style(for: .large) == .title2)
        #expect(HumType.trackTitle.weight == .semibold)
        #expect(HumType.textTitle.style(for: .small) == .headline)
        #expect(HumType.textTitle.style(for: .large) == .headline)
        #expect(HumType.textTitle.weight == .semibold)
        // The artist line is where it was.
        #expect(HumType.trackArtist.style(for: .small) == .subheadline)
        #expect(HumType.trackArtist.style(for: .medium) == .body)
        #expect(HumType.trackArtist.weight == .regular)
    }

    @Test func thoseStylesAreFifteenSeventeenAndThirteenPoints() {
        #expect(NSFont.preferredFont(forTextStyle: .title3).pointSize == 15)
        #expect(NSFont.preferredFont(forTextStyle: .title2).pointSize == 17)
        #expect(NSFont.preferredFont(forTextStyle: .headline).pointSize == 13)
    }

    @Test func tracksAreFourPointsAtRestAndSevenWhenActive() {
        #expect(SliderMetrics.restThickness == 4)
        #expect(SliderMetrics.activeThickness == 7)
        #expect(SliderMetrics.hairline == 2)
    }

    @Test func theRimShowsInDarkAppearanceOnly() throws {
        let view = PlayerContentView(hostingView: NSView())
        view.appearance = NSAppearance(named: .darkAqua)
        view.viewDidChangeEffectiveAppearance()
        let layer = try #require(view.layer)
        #expect(layer.borderWidth > 0 && layer.borderWidth <= 1)
        let color = try #require(layer.borderColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
        #expect(abs(color.alphaComponent - 0.1) < 0.001)
        #expect(min(color.redComponent, color.greenComponent, color.blueComponent) > 0.99)

        view.appearance = NSAppearance(named: .aqua)
        view.viewDidChangeEffectiveAppearance()
        #expect(layer.borderWidth == 0)
    }

    @Test func permissionCopyNamesHum() {
        // An empty state's title is Title Case; the banner's is a sentence.
        #expect(PermissionGuide.neededTitle(app: "Music") == "Let Hum Control Music")
        #expect(PermissionGuide.neededMessage(app: "Music").hasPrefix("macOS will ask once. Hum reads"))
        #expect(PermissionGuide.deniedTitle(app: "Spotify") == "Hum Can’t Control Spotify")
        #expect(PermissionGuide.deniedBannerTitle(app: "Spotify") == "Hum can’t control Spotify")
        #expect(PermissionGuide.deniedMessage(app: "Spotify").contains("for Hum in System Settings"))
        // The player's own copy names Hum and never the app (§10).
        #expect(PermissionGuide.playerNeededTitle == "Let Hum Control Your Music App")
        #expect(PermissionGuide.playerDeniedTitle == "Hum Needs Your Permission")
        #expect(PermissionGuide.playerDeniedMessage.contains("System Settings › Privacy & Security › Automation"))
    }
}
