/// What an accent is drawn against, which decides which way its lightness moves.
public enum AccentBackdrop: Equatable, Sendable {
    /// Over artwork (always behind the dark scrim) or on dark material. The accent
    /// is measured against black and made lighter if it needs to be.
    case dark
    /// On light material. The accent is measured against that background and made
    /// darker if it needs to be.
    case light(background: PaletteColor)
}

/// Turns the user's accent mode into a color that is legible where it's drawn.
public enum AccentResolver {
    /// Glyphs, focus indicators, and large text.
    public static let glyphContrast = 3.0
    /// Body text in the accent color.
    public static let textContrast = 4.5
    /// Content on an accent fill is white below this OKLCH lightness, black above.
    public static let onAccentLightness = 0.70

    /// The accent for `mode`, adjusted for `backdrop`.
    ///
    /// Album mode without a palette accent (grayscale art), or any color that can't
    /// reach the contrast bar, falls back to the system accent. Returns `nil` only
    /// when even that can't, and callers then use the label color.
    public static func accent(
        mode: AccentSource,
        palette: ArtworkPalette?,
        custom: PaletteColor?,
        system: PaletteColor,
        on backdrop: AccentBackdrop,
        ratio: Double = glyphContrast
    ) -> PaletteColor? {
        let preferred: PaletteColor? = switch mode {
        case .system: system
        case .album: palette?.accent
        case .custom: custom
        }
        if let preferred, let adjusted = adjust(preferred, on: backdrop, ratio: ratio) {
            return adjusted
        }
        return adjust(system, on: backdrop, ratio: ratio)
    }

    /// `color` with its OKLCH lightness moved until it reaches `ratio` against
    /// the backdrop, or `nil` if it can't.
    public static func adjust(_ color: PaletteColor, on backdrop: AccentBackdrop, ratio: Double) -> PaletteColor? {
        switch backdrop {
        case .dark:
            color.adjusted(toContrast: ratio, against: .black)
        case .light(let background):
            color.adjusted(toContrast: ratio, against: background)
        }
    }

    /// White or black, for a glyph or text drawn on an accent fill.
    public static func content(on accent: PaletteColor) -> PaletteColor {
        accent.oklch.lightness < onAccentLightness ? .white : .black
    }
}
