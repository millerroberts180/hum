import SwiftUI

/// Art Only's hover controls with Liquid Glass (`HumMaterial.controlsPlatter`,
/// DESIGN.md §3.6): clear glass in a rounded rectangle concentric with the
/// window, over a dimming layer of the same shape, as Apple asks for clear
/// glass over media. The caller insets it `Spacing.s` from the window's sides
/// and bottom and makes it as tall as the controls plus `Spacing.m`.
///
/// Without Liquid Glass the controls sit on the `Scrim` instead
/// (`usesPlatter`), and under Reduce Transparency the scrim's solid band.
struct ControlsPlatter: View {
    /// The window's corner radius, which the platter is concentric with.
    var windowRadius: CGFloat

    /// The black under the glass, so white glyphs read over any cover.
    nonisolated static let dimming = 0.35
    /// The platter's inset from the window's sides and bottom.
    nonisolated static let inset = Spacing.s
    /// The room above and below the controls inside the platter, together.
    nonisolated static let verticalRoom = Spacing.m

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius(windowRadius: windowRadius), style: .continuous)
        shape
            .fill(.black.opacity(Self.dimming))
            .overlay { Color.clear.humMaterial(.controlsPlatter, in: shape) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Concentric with the window: its radius less the inset, never below the
    /// small artwork corner.
    nonisolated static func cornerRadius(windowRadius: CGFloat) -> CGFloat {
        max(Radius.artSmall, windowRadius - inset)
    }

    /// Whether the controls sit in the platter: Liquid Glass is on and
    /// transparency isn't reduced.
    static func usesPlatter(liquidGlass: Bool, reduceTransparency: Bool) -> Bool {
        liquidGlass && !reduceTransparency
    }
}

private nonisolated struct InControlsPlatterKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The content sits in the `ControlsPlatter`, whose dimming already carries
    /// the glyphs: they take no legibility shadow (DESIGN.md §3.6).
    nonisolated var isInControlsPlatter: Bool {
        get { self[InControlsPlatterKey.self] }
        set { self[InControlsPlatterKey.self] = newValue }
    }
}
