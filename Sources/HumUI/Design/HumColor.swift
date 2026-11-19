import AppKit
import HumCore
import SwiftUI

/// Where a component is drawn, which decides how every `HumColor` role resolves.
nonisolated enum HumColorContext: Equatable, Sendable {
    /// System materials and window backgrounds: system dynamic colors that follow
    /// light and dark appearance.
    case material
    /// Over artwork with the controls scrim beneath. Always dark: the scrim
    /// guarantees a dark base, so dark text never sits on a cover.
    case artwork
    /// On a fill of the cover's own `background` (Text's album tint): every
    /// role is drawn in the palette's colors, glyphs included.
    case tinted(ArtworkPalette)
    /// On a backdrop whose color is known only as an estimate: white or black
    /// by the fill's luminance, each text role raised to its contrast bar
    /// (§3.5.9).
    case swatch(SwatchLabels)
}

/// Hum's color roles. Components ask for a role; the environment's color context,
/// appearance, contrast setting, and accent decide the actual color.
///
/// Chrome is neutral. Color enters only through the artwork, the accent (which
/// marks state and nothing else), and the two status colors.
nonisolated struct HumColor: ShapeStyle, Hashable {
    enum Role: Hashable, Sendable {
        case label, secondaryLabel, tertiaryLabel, quaternaryLabel
        case trackFill, fillQuaternary, fillTertiary
        case separator, glassStroke
        case accent, onAccent, onLabel
        case critical, warning
        case scrubberFill, scrubberTrack, scrubberTime
    }

    let role: Role

    /// Titles, primary glyphs, the filled play button.
    static let label = HumColor(role: .label)
    /// Artist, inactive glyphs, slider fills at rest.
    static let secondaryLabel = HumColor(role: .secondaryLabel)
    /// Times, album, captions.
    static let tertiaryLabel = HumColor(role: .tertiaryLabel)
    /// Placeholder glyphs, controls waiting on a source.
    static let quaternaryLabel = HumColor(role: .quaternaryLabel)
    /// The unfilled part of a slider.
    static let trackFill = HumColor(role: .trackFill)
    /// Hover backings, chips at rest, loading placeholders.
    static let fillQuaternary = HumColor(role: .fillQuaternary)
    /// Pressed backings.
    static let fillTertiary = HumColor(role: .fillTertiary)
    /// Hairlines in lists.
    static let separator = HumColor(role: .separator)
    /// The 1-pt inner edge of glass and cards.
    static let glassStroke = HumColor(role: .glassStroke)
    /// State only: an active toggle, the filled Save glyph, the card play button.
    static let accent = HumColor(role: .accent)
    /// A glyph or text drawn on an accent fill: white or black, whichever reads.
    static let onAccent = HumColor(role: .onAccent)
    /// Text on a `label` fill (the selected chip), inverted from `label`.
    static let onLabel = HumColor(role: .onLabel)
    /// Errors that block playback.
    static let critical = HumColor(role: .critical)
    /// Degraded but working, and missing Automation access.
    static let warning = HumColor(role: .warning)
    /// Apple's white scrubber (DESIGN.md §5.2): the elapsed fill of the seek
    /// and volume sliders. White over artwork, a backdrop or dark material;
    /// `label` on light material. Never the accent.
    static let scrubberFill = HumColor(role: .scrubberFill)
    /// The rest of the slider's track: the fill's color at 30%, or `label` at
    /// 20% on light material.
    static let scrubberTrack = HumColor(role: .scrubberTrack)
    /// The seek bar's times: the fill's color at 60%.
    static let scrubberTime = HumColor(role: .scrubberTime)

    func resolve(in environment: EnvironmentValues) -> Color {
        Self.color(
            role,
            context: environment.humColorContext,
            isDark: environment.colorScheme == .dark,
            increasedContrast: environment.colorSchemeContrast == .increased,
            accent: environment.humAccent
        )
    }

    static func color(
        _ role: Role,
        context: HumColorContext,
        isDark: Bool,
        increasedContrast: Bool,
        accent: AccentColors
    ) -> Color {
        // Increase Contrast takes every stroke to the system separator, over
        // artwork and palettes too (§3.6).
        if role == .glassStroke, increasedContrast {
            return Color(nsColor: .separatorColor)
        }
        if let scrubber = scrubberColor(role, context: context, isDark: isDark, increasedContrast: increasedContrast) {
            return scrubber
        }
        if case .tinted(let palette) = context, role != .critical, role != .warning {
            return tintedColor(role, palette: palette, increasedContrast: increasedContrast)
        }
        if case .swatch(let labels) = context, role != .critical, role != .warning {
            return swatchColor(role, labels: labels, increasedContrast: increasedContrast, accent: accent)
        }
        switch role {
        case .accent:
            let color = context == .artwork || isDark ? accent.onDark : accent.onLight
            return color.map(Color.init) ?? Color(nsColor: .labelColor)
        case .onAccent:
            let color = context == .artwork || isDark ? accent.onDark : accent.onLight
            return Color(color.map(AccentResolver.content(on:)) ?? .white)
        case .critical:
            return Color(nsColor: .systemRed)
        case .warning:
            return Color(nsColor: .systemOrange)
        case .onLabel where context == .artwork:
            return .black
        default:
            break
        }
        switch context {
        case .artwork:
            return .white.opacity(artworkOpacity(role, increasedContrast: increasedContrast))
        case .material, .tinted, .swatch:
            return materialColor(role, isDark: isDark, increasedContrast: increasedContrast)
        }
    }

    /// The scrubber roles, or nil for any other role. White (or the swatch's
    /// content, or the palette's primary) over anything dark; `label` on light
    /// material. Increase Contrast lifts the track and the times.
    static func scrubberColor(_ role: Role, context: HumColorContext, isDark: Bool, increasedContrast: Bool) -> Color? {
        let opacity: Double
        switch role {
        case .scrubberFill: opacity = 1
        case .scrubberTrack: opacity = increasedContrast ? 0.45 : (context == .material && !isDark ? 0.2 : 0.3)
        case .scrubberTime: opacity = increasedContrast ? 0.85 : 0.6
        default: return nil
        }
        // The fill is the plain color, so it matches `label` and white exactly.
        func at(_ color: Color, _ opacity: Double) -> Color {
            role == .scrubberFill ? color : color.opacity(opacity)
        }
        switch context {
        case .artwork:
            return at(.white, opacity)
        case .material:
            return at(isDark ? Color.white : Color(nsColor: .labelColor), opacity)
        case .tinted(let palette):
            return at(Color(palette.primary), opacity)
        case .swatch(let labels):
            let raised = role == .scrubberTime ? labels.opacity(nominal: opacity, ratio: SwatchLabels.textContrast) : opacity
            return at(Color(labels.content), raised)
        }
    }

    /// White or black on the average color, at the scrim's opacities where they
    /// already read and higher where they don't: text keeps 4.5:1 and the accent
    /// 3:1 against the fill itself.
    static func swatchColor(_ role: Role, labels: SwatchLabels, increasedContrast: Bool, accent: AccentColors) -> Color {
        switch role {
        case .accent, .onAccent:
            let base = labels.isDark ? accent.onDark : accent.onLight
            let adjusted = base.flatMap {
                AccentResolver.adjust($0, on: .light(background: labels.fill), ratio: AccentResolver.glyphContrast)
            }
            guard let adjusted else { return Color(role == .accent ? labels.content : labels.fill) }
            return Color(role == .accent ? adjusted : AccentResolver.content(on: adjusted))
        case .label, .secondaryLabel, .tertiaryLabel:
            let nominal = artworkOpacity(role, increasedContrast: increasedContrast)
            return Color(labels.content).opacity(labels.opacity(nominal: nominal, ratio: SwatchLabels.textContrast))
        case .onLabel:
            return Color(labels.fill)
        default:
            return Color(labels.content).opacity(artworkOpacity(role, increasedContrast: increasedContrast))
        }
    }

    /// The palette's text colors on its own background. They were chosen to read
    /// there, so the accent becomes the primary color too and the controls stay
    /// one color. Increase Contrast moves secondary text up to primary.
    static func tintedColor(_ role: Role, palette: ArtworkPalette, increasedContrast: Bool) -> Color {
        let primary = Color(palette.primary)
        switch role {
        case .label, .accent: return primary
        case .secondaryLabel: return Color(increasedContrast ? palette.primary : palette.secondary)
        case .tertiaryLabel: return Color(increasedContrast ? palette.secondary : palette.tertiary)
        case .quaternaryLabel: return primary.opacity(increasedContrast ? 0.5 : 0.3)
        case .trackFill: return primary.opacity(0.24)
        case .fillQuaternary: return primary.opacity(increasedContrast ? 0.24 : 0.12)
        case .fillTertiary: return primary.opacity(increasedContrast ? 0.4 : 0.2)
        case .separator: return primary.opacity(0.14)
        case .glassStroke: return primary.opacity(0.18)
        case .onAccent, .onLabel: return Color(palette.background)
        case .critical: return Color(nsColor: .systemRed)
        case .warning: return Color(nsColor: .systemOrange)
        case .scrubberFill, .scrubberTrack, .scrubberTime:
            return scrubberColor(role, context: .tinted(palette), isDark: true, increasedContrast: increasedContrast) ?? primary
        }
    }

    /// White over the scrim. Increase Contrast lifts the label whites to
    /// 100 / 90 / 72% and doubles the hover and pressed fills.
    static func artworkOpacity(_ role: Role, increasedContrast: Bool) -> Double {
        switch (role, increasedContrast) {
        case (.label, _): 1
        case (.secondaryLabel, false): 0.72
        case (.secondaryLabel, true): 0.9
        case (.tertiaryLabel, false): 0.5
        case (.tertiaryLabel, true): 0.72
        case (.quaternaryLabel, false): 0.3
        case (.quaternaryLabel, true): 0.5
        case (.trackFill, _): 0.24
        case (.fillQuaternary, false): 0.12
        case (.fillQuaternary, true): 0.24
        case (.fillTertiary, false): 0.2
        case (.fillTertiary, true): 0.4
        case (.separator, _): 0.14
        case (.glassStroke, _): 0.18
        default: 1
        }
    }

    private static func materialColor(_ role: Role, isDark: Bool, increasedContrast: Bool) -> Color {
        switch role {
        case .label: Color(nsColor: .labelColor)
        // Increase Contrast steps each text role up one (§3.5.9).
        case .secondaryLabel: Color(nsColor: increasedContrast ? .labelColor : .secondaryLabelColor)
        case .tertiaryLabel: Color(nsColor: increasedContrast ? .secondaryLabelColor : .tertiaryLabelColor)
        case .quaternaryLabel: Color(nsColor: .quaternaryLabelColor)
        case .trackFill, .fillTertiary: Color(nsColor: .tertiarySystemFill)
        case .fillQuaternary: Color(nsColor: .quaternarySystemFill)
        case .separator: Color(nsColor: .separatorColor)
        case .onLabel: Color(nsColor: .windowBackgroundColor)
        case .glassStroke: isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
        default: Color(nsColor: .labelColor)
        }
    }
}

/// The accent, already adjusted for each place it can be drawn.
nonisolated struct AccentColors: Equatable, Sendable {
    /// Over artwork and on dark material: at least 3:1 against black.
    var onDark: PaletteColor?
    /// On light material: at least 3:1 against the window background.
    var onLight: PaletteColor?

    static let fallback = AccentColors(
        onDark: PaletteColor(red: 0.25, green: 0.56, blue: 1),
        onLight: PaletteColor(red: 0, green: 0.4, blue: 0.86)
    )

    /// Resolve `base` (already chosen by mode) for both backdrops.
    init(base: PaletteColor, system: PaletteColor, lightBackground: PaletteColor) {
        onDark = AccentResolver.adjust(base, on: .dark, ratio: AccentResolver.glyphContrast)
            ?? AccentResolver.adjust(system, on: .dark, ratio: AccentResolver.glyphContrast)
        let light = AccentBackdrop.light(background: lightBackground)
        onLight = AccentResolver.adjust(base, on: light, ratio: AccentResolver.glyphContrast)
            ?? AccentResolver.adjust(system, on: light, ratio: AccentResolver.glyphContrast)
    }

    init(onDark: PaletteColor?, onLight: PaletteColor?) {
        self.onDark = onDark
        self.onLight = onLight
    }

    /// Part of the way to `target`, through OKLCH so hues travel the short way
    /// round and don't muddy in the middle.
    func interpolated(to target: AccentColors, fraction: Double) -> AccentColors {
        func mix(_ from: PaletteColor?, _ to: PaletteColor?) -> PaletteColor? {
            guard let from, let to else { return fraction < 0.5 ? from : to }
            return from.interpolated(to: to, fraction: fraction)
        }
        return AccentColors(onDark: mix(onDark, target.onDark), onLight: mix(onLight, target.onLight))
    }
}

extension Color {
    nonisolated init(_ rgb: PaletteColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

extension PaletteColor {
    /// `color` in sRGB, resolved in `appearance` when it's a dynamic system color.
    nonisolated init(_ color: NSColor, appearance: NSAppearance? = nil) {
        var resolved = color.usingColorSpace(.sRGB)
        if let appearance {
            appearance.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB)
            }
        }
        self.init(
            red: Double(resolved?.redComponent ?? 0.5),
            green: Double(resolved?.greenComponent ?? 0.5),
            blue: Double(resolved?.blueComponent ?? 0.5)
        )
    }

    /// The user's macOS accent color.
    @MainActor static var systemAccent: PaletteColor { PaletteColor(.controlAccentColor) }

    /// The light window background accents are measured against on light material.
    @MainActor static var lightWindowBackground: PaletteColor {
        PaletteColor(.windowBackgroundColor, appearance: NSAppearance(named: .aqua))
    }
}
