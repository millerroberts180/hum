import Foundation

/// A color in sRGB, components 0...1. Plain data so it can live in HumCore, cross
/// actors, and be persisted next to cached artwork.
public struct PaletteColor: Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    public static let black = PaletteColor(red: 0, green: 0, blue: 0)
    public static let white = PaletteColor(red: 1, green: 1, blue: 1)
    public static let neutral = PaletteColor(red: 0.5, green: 0.5, blue: 0.52)

    /// WCAG relative luminance, 0...1.
    public var luminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio against another color, 1...21.
    public func contrast(with other: PaletteColor) -> Double {
        let a = luminance + 0.05
        let b = other.luminance + 0.05
        return max(a, b) / min(a, b)
    }

    // MARK: HSL

    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        guard delta > 0.0001 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maxValue {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, min(1, saturation), lightness)
    }

    public init(hue: Double, saturation: Double, lightness: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - chroma / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<1: (r, g, b) = (chroma, x, 0)
        case ..<2: (r, g, b) = (x, chroma, 0)
        case ..<3: (r, g, b) = (0, chroma, x)
        case ..<4: (r, g, b) = (0, x, chroma)
        case ..<5: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m)
    }

    /// The same hue with lightness clamped into `range`, for keeping an album color
    /// legible on a light or dark surface.
    public func clampingLightness(to range: ClosedRange<Double>) -> PaletteColor {
        let (h, s, l) = hsl
        let clamped = min(range.upperBound, max(range.lowerBound, l))
        guard abs(clamped - l) > 0.001 else { return self }
        return PaletteColor(hue: h, saturation: s, lightness: clamped)
    }

    public func mixed(with other: PaletteColor, amount: Double) -> PaletteColor {
        let t = Self.clamp(amount)
        return PaletteColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
