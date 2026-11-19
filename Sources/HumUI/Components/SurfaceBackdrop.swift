import AppKit
import HumCore
import SwiftUI

/// What Echo and Status sit on: the blurred cover under a wash of the window
/// background (`BackdropContrast.wash`), so text reads on any cover and the
/// surface keeps its tint.
///
/// Content over it is its own accent context (DESIGN.md §3.5.3): the accent is
/// adjusted against the hardest part of the backdrop, so the playing row's
/// title keeps 4.5:1. When no lightness reaches that, accent roles fall back to
/// the label color. Accent fills, such as a card's play button, keep the
/// context's own accent (`backdropAccentFill()`).
struct SurfaceBackdrop<Content: View>: View {
    var artwork: ArtworkImage?
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.humAccent) private var accent
    @State private var regions: [PaletteColor] = []

    var body: some View {
        ZStack {
            ArtBackdrop(artwork: artwork)
            Color(nsColor: .windowBackgroundColor)
                .opacity(BackdropContrast.wash)
                .accessibilityHidden(true)
            content
                .environment(\.humAccent, listAccent)
                .environment(\.backdropFillAccent, accent)
        }
        .onChange(of: artwork?.key, initial: true) {
            regions = artwork.map { BackdropContrast.regions(of: $0) } ?? []
        }
    }

    private var listAccent: AccentColors {
        let isDark = colorScheme == .dark
        let window = PaletteColor(.windowBackgroundColor, appearance: NSAppearance(named: isDark ? .darkAqua : .aqua))
        // Reduce Transparency draws a near-flat tint, so the window is the measure.
        let covered = reduceTransparency ? [] : regions
        return accent.backdropText(regions: covered, isDark: isDark, window: window)
    }
}

extension AccentColors {
    /// The accent for text over the backdrop: this appearance's variant with
    /// its lightness moved until it reads at 4.5:1 on every region.
    nonisolated func backdropText(regions: [PaletteColor], isDark: Bool, window: PaletteColor) -> AccentColors {
        func adjusted(_ color: PaletteColor?) -> PaletteColor? {
            color.flatMap { BackdropContrast.textAccent($0, regions: regions, isDark: isDark, window: window) }
        }
        var colors = self
        if isDark {
            colors.onDark = adjusted(onDark)
        } else {
            colors.onLight = adjusted(onLight)
        }
        return colors
    }
}

extension View {
    /// Draws an accent fill over the backdrop, such as a card's play button, in
    /// the context's own accent rather than the lists' text accent. A fill
    /// needs 3:1 where text needs 4.5:1 (DESIGN.md §3.5.3), and the text
    /// variant would pale the circle and turn its glyph black in dark
    /// appearance. Outside a backdrop it changes nothing.
    func backdropAccentFill() -> some View {
        modifier(BackdropAccentFill())
    }
}

private struct BackdropAccentFill: ViewModifier {
    @Environment(\.backdropFillAccent) private var fill
    @Environment(\.humAccent) private var accent

    func body(content: Content) -> some View {
        content.environment(\.humAccent, fill ?? accent)
    }
}

private nonisolated struct BackdropFillAccentKey: EnvironmentKey {
    static let defaultValue: AccentColors? = nil
}

extension EnvironmentValues {
    /// The accent the backdrop was given, before it was raised for text.
    fileprivate nonisolated var backdropFillAccent: AccentColors? {
        get { self[BackdropFillAccentKey.self] }
        set { self[BackdropFillAccentKey.self] = newValue }
    }
}
