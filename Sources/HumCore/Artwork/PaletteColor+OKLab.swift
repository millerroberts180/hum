import Foundation

/// A color in OKLCH: perceptual lightness 0...1, chroma (0 for gray, about 0.37 at
/// most inside sRGB), and hue in radians.
///
/// Palette work happens here rather than in RGB or HSL because equal steps in
/// OKLCH lightness look like equal steps, and hue stays put while lightness moves.
public struct OKLCH: Hashable, Codable, Sendable {
    public var lightness: Double
    public var chroma: Double
    public var hue: Double

    public init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    /// The hue that is `target`'s hue but no more than half a turn from `hue`, so a
    /// straight interpolation between the two travels the shorter way around.
    public func hueNearest(to target: OKLCH) -> Double {
        var delta = (target.hue - hue).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return hue + delta
    }
}

extension PaletteColor {
    /// OKLab coordinates: lightness, then the green–red and blue–yellow axes.
    public var oklab: (l: Double, a: Double, b: Double) {
        Self.oklab(fromLinear: (Self.linear(red), Self.linear(green), Self.linear(blue)))
    }

    public var oklch: OKLCH {
        let (l, a, b) = oklab
        let chroma = (a * a + b * b).squareRoot()
        return OKLCH(lightness: l, chroma: chroma, hue: chroma < 1e-6 ? 0 : atan2(b, a))
    }

    /// The sRGB color for OKLab coordinates. Out-of-gamut results are clipped.
    public init(oklabL l: Double, a: Double, b: Double) {
        let (r, g, bl) = Self.linear(fromOKLab: (l, a, b))
        self.init(red: Self.gamma(r), green: Self.gamma(g), blue: Self.gamma(bl))
    }

    /// The sRGB color for `oklch`. When it falls outside sRGB, chroma is reduced
    /// (keeping lightness and hue) until it fits.
    public init(_ oklch: OKLCH) {
        let l = min(1, max(0, oklch.lightness))
        func components(_ chroma: Double) -> (Double, Double, Double) {
            Self.linear(fromOKLab: (l, chroma * cos(oklch.hue), chroma * sin(oklch.hue)))
        }
        func fits(_ rgb: (Double, Double, Double)) -> Bool {
            let range = -0.0001...1.0001
            return range.contains(rgb.0) && range.contains(rgb.1) && range.contains(rgb.2)
        }
        var chroma = max(0, oklch.chroma)
        var rgb = components(chroma)
        if !fits(rgb) {
            var low = 0.0
            var high = chroma
            for _ in 0..<20 {
                let mid = (low + high) / 2
                if fits(components(mid)) { low = mid } else { high = mid }
            }
            chroma = low
            rgb = components(chroma)
        }
        self.init(red: Self.gamma(rgb.0), green: Self.gamma(rgb.1), blue: Self.gamma(rgb.2))
    }

    /// Squared distance in OKLab, where about 0.01 (0.1 unsquared) is a clearly
    /// different color.
    public func distanceSquared(to other: PaletteColor) -> Double {
        let p = oklab
        let q = other.oklab
        return (p.l - q.l) * (p.l - q.l) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b)
    }

    /// The color part of the way to `target` in OKLCH, along the shorter hue arc.
    /// Gray endpoints borrow the other end's hue so a fade from gray doesn't swing
    /// through unrelated hues.
    public func interpolated(to target: PaletteColor, fraction: Double) -> PaletteColor {
        let t = min(1, max(0, fraction))
        var from = oklch
        var to = target.oklch
        if from.chroma < 0.002 { from.hue = to.hue }
        if to.chroma < 0.002 { to.hue = from.hue }
        let hue = from.hue + (from.hueNearest(to: to) - from.hue) * t
        return PaletteColor(OKLCH(
            lightness: from.lightness + (to.lightness - from.lightness) * t,
            chroma: from.chroma + (to.chroma - from.chroma) * t,
            hue: hue
        ))
    }

    /// The same hue and chroma at another OKLCH lightness.
    public func withLightness(_ lightness: Double) -> PaletteColor {
        var value = oklch
        value.lightness = lightness
        return PaletteColor(value)
    }

    /// Step OKLCH lightness away from `background`, 0.02 at a time, keeping hue
    /// and chroma, until the contrast ratio reaches `ratio`.
    ///
    /// - Returns: The first color that reaches the ratio (`self` if it already
    ///   does), or `nil` if none does before lightness runs out.
    public func adjusted(toContrast ratio: Double, against background: PaletteColor) -> PaletteColor? {
        if contrast(with: background) >= ratio { return self }
        let start = oklch
        let backgroundLightness = background.oklch.lightness
        // Move away from the background; from an equal start, go the way with room.
        let lighter = start.lightness == backgroundLightness
            ? backgroundLightness < 0.5
            : start.lightness > backgroundLightness
        let step = lighter ? Self.lightnessStep : -Self.lightnessStep
        var lightness = start.lightness
        while true {
            lightness += step
            guard (0...1).contains(lightness) else { return nil }
            let candidate = PaletteColor(OKLCH(lightness: lightness, chroma: start.chroma, hue: start.hue))
            if candidate.contrast(with: background) >= ratio { return candidate }
        }
    }

    /// One contrast-adjustment step in OKLCH lightness.
    public static let lightnessStep = 0.02

    // MARK: Conversions

    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func gamma(_ c: Double) -> Double {
        let value = min(1, max(0, c))
        return value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    static func oklab(fromLinear rgb: (Double, Double, Double)) -> (l: Double, a: Double, b: Double) {
        let (r, g, b) = rgb
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    static func linear(fromOKLab lab: (Double, Double, Double)) -> (Double, Double, Double) {
        let (lightness, a, b) = lab
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }
}
