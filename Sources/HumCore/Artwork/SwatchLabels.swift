/// Text and glyphs on a flat fill of a cover's average color, where Spotify's
/// art leaves room for the controls (DESIGN §3.6.1).
///
/// The fill's luminance picks white or black content, whichever contrasts more.
/// Each role then starts at its usual opacity and rises only as far as it must
/// to keep §3.5.9's minimums on that fill, so most covers look exactly like the
/// scrim's whites, and a mid-tone cover still reads.
public struct SwatchLabels: Hashable, Sendable {
    /// The flat color the labels sit on.
    public let fill: PaletteColor
    /// White on a dark fill, black on a light one.
    public let content: PaletteColor

    public init(fill: PaletteColor) {
        self.fill = fill
        content = PaletteColor.white.contrast(with: fill) >= PaletteColor.black.contrast(with: fill) ? .white : .black
    }

    /// Light content on a dark fill.
    public var isDark: Bool { content == .white }

    /// Body text: titles, artists, and times.
    public static let textContrast = 4.5
    /// Opacity steps when raising a role to its contrast bar.
    static let step = 0.02

    /// The opacity of `content` for a role drawn at `nominal`, raised until it
    /// reaches `ratio` on the fill or is fully opaque.
    public func opacity(nominal: Double, ratio: Double) -> Double {
        var opacity = min(1, max(0, nominal))
        while opacity < 1, color(opacity: opacity).contrast(with: fill) < ratio {
            opacity = min(1, opacity + Self.step)
        }
        return opacity
    }

    /// `content` at `opacity` over the fill, as it appears on screen.
    public func color(opacity: Double) -> PaletteColor {
        fill.mixed(with: content, amount: opacity)
    }
}
