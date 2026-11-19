import SwiftUI

/// Elevation and legibility shadows (DESIGN.md §3.6). The player window uses the
/// system window shadow and cards use none; these are for artwork, glyphs over
/// standard artwork, and the floating card play button.
nonisolated struct HumShadow: Equatable, Sendable {
    var opacity: Double
    /// SwiftUI's shadow radius, which is half the design's blur.
    var radius: CGFloat
    var y: CGFloat

    /// List artwork: y 1, blur 2, black 15%.
    static let listArt = HumShadow(opacity: 0.15, radius: 1, y: 1)
    /// Glyphs over artwork (transport, toggles, the resting indicator), for
    /// legibility as in Apple's MiniPlayer: y 0.5, blur 3, black 30%.
    static let glyphOnArt = HumShadow(opacity: 0.3, radius: 1.5, y: 0.5)
    /// The floating card play button: y 2, blur 6, black 25%.
    static let cardPlay = HumShadow(opacity: 0.25, radius: 3, y: 2)
    /// No shadow, for a view that takes one only in some contexts.
    static let none = HumShadow(opacity: 0, radius: 0, y: 0)
}

extension View {
    func humShadow(_ shadow: HumShadow) -> some View {
        self.shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}
