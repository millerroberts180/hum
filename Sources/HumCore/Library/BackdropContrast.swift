import CoreGraphics
import Foundation

/// Legibility over the blurred cover behind Play and Find.
///
/// The backdrop is the cover blurred and washed, so its color changes across the
/// surface. Text is measured against the part that is hardest to read on: the
/// lightest region in dark appearance, the darkest in light.
public enum BackdropContrast {
    /// How much of the window background covers the art behind lists. Enough
    /// that labels keep 4.5:1 on any cover, little enough that the cover still
    /// tints the surface.
    public static let wash = 0.65

    /// The cover averaged over a `grid` × `grid` layout, about the scale its
    /// 60-pt blur leaves at player sizes.
    public static func regions(of image: CGImage, grid: Int = 3) -> [PaletteColor] {
        let cell = 8
        let side = grid * cell
        guard grid > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: side * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return [] }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return [] }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let count = Double(cell * cell) * 255
        var regions: [PaletteColor] = []
        for row in 0..<grid {
            for column in 0..<grid {
                var red = 0.0, green = 0.0, blue = 0.0
                for y in row * cell..<(row + 1) * cell {
                    for x in column * cell..<(column + 1) * cell {
                        let index = (y * side + x) * 4
                        red += Double(pixels[index])
                        green += Double(pixels[index + 1])
                        blue += Double(pixels[index + 2])
                    }
                }
                regions.append(PaletteColor(red: red / count, green: green / count, blue: blue / count))
            }
        }
        return regions
    }

    /// What lies under a surface's content for `artwork`: the regions of its
    /// blurred cover.
    public static func regions(of artwork: ArtworkImage) -> [PaletteColor] {
        regions(of: artwork.cgImage)
    }

    /// The backdrop over one region of the cover, as it's drawn: the cover under
    /// 25% black (dark) or 35% white (light), then `wash` of the window
    /// background. The saturation boost is left out; it hardly moves luminance.
    public static func backdrop(over region: PaletteColor, isDark: Bool, window: PaletteColor) -> PaletteColor {
        let art = isDark ? region.mixed(with: .black, amount: 0.25) : region.mixed(with: .white, amount: 0.35)
        return art.mixed(with: window, amount: wash)
    }

    /// The part of the backdrop that text reads worst on. With no cover, the
    /// window background.
    public static func hardest(_ regions: [PaletteColor], isDark: Bool, window: PaletteColor) -> PaletteColor {
        let backdrops = regions.map { backdrop(over: $0, isDark: isDark, window: window) }
        let hardest = isDark
            ? backdrops.max { $0.luminance < $1.luminance }
            : backdrops.min { $0.luminance < $1.luminance }
        return hardest ?? window
    }

    /// `accent` with its lightness moved until text in it reaches 4.5:1 on every
    /// part of the backdrop, or `nil` when no lightness can. Callers then use the
    /// label color.
    public static func textAccent(
        _ accent: PaletteColor,
        regions: [PaletteColor],
        isDark: Bool,
        window: PaletteColor
    ) -> PaletteColor? {
        accent.adjusted(
            toContrast: AccentResolver.textContrast,
            against: hardest(regions, isDark: isDark, window: window)
        )
    }
}
