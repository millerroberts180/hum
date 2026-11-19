import HumCore
import SwiftUI
import WidgetKit

// The few design tokens the widgets use, restated from DESIGN.md §3. HumUI's
// token enums are internal to the app, and the extension links only HumCore, so
// the values are repeated here with the section they come from.

/// DESIGN.md §3.1: the 4-pt spacing scale.
enum WidgetSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
}

/// DESIGN.md §3.2: continuous corners.
enum WidgetRadius {
    /// Artwork 41–120 pt, and the covers inside widgets, which sit in the
    /// widget's own rounded frame.
    static let artMedium: CGFloat = 6
}

/// DESIGN.md §3.3 and §7.3: the song's title, a step larger than the artist
/// line, as on the player (§13.20).
enum WidgetType {
    /// `trackTitle`: its M size in small and medium widgets, its L size in
    /// large ones, Text's included.
    static func trackTitle(_ family: WidgetFamily) -> Font.TextStyle {
        family == .systemLarge || family == .systemExtraLarge ? .title2 : .title3
    }
}

/// DESIGN.md §3.8: transport glyph sizes and hit targets by size class. Small
/// widgets have no buttons; medium widgets use M, large widgets L.
struct TransportMetrics {
    var play: CGFloat
    var skip: CGFloat
    var tertiary: CGFloat
    var playHit: CGFloat
    var skipHit: CGFloat
    var tertiaryHit: CGFloat

    static let medium = TransportMetrics(play: 22, skip: 16, tertiary: 13, playHit: 44, skipHit: 36, tertiaryHit: 32)
    static let large = TransportMetrics(play: 28, skip: 20, tertiary: 15, playHit: 56, skipHit: 44, tertiaryHit: 36)

    static func forFamily(_ family: WidgetFamily) -> TransportMetrics {
        family == .systemLarge || family == .systemExtraLarge ? .large : .medium
    }
}

/// DESIGN.md §3.5.2: the neutral roles over artwork (always a dark context).
enum OnArt {
    static let label = Color.white
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.5)
}

/// DESIGN.md §5.2: Apple's white scrubber. Over artwork or its scrim, or
/// material in dark appearance, a white fill; on light material, `label`. The
/// track is the system bar's own: only `ProgressView` runs on its own in a
/// widget.
struct SeekColors {
    var fill: Color

    static let overArt = SeekColors(fill: .white)
    static let onLightMaterial = SeekColors(fill: .primary)

    static func forScheme(_ scheme: ColorScheme) -> SeekColors {
        scheme == .dark ? .overArt : .onLightMaterial
    }
}

extension View {
    /// DESIGN.md §3.6: the soft legibility shadow under glyphs over artwork
    /// (`HumShadow.glyphOnArt`: y 0.5, blur 3, black 30%).
    func glyphOnArtShadow() -> some View {
        shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
    }
}

extension Color {
    init(_ color: PaletteColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}
