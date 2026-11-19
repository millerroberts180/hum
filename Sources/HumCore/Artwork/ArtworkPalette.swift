import CoreGraphics
import Foundation

/// Colors derived from a cover: one background color and text colors guaranteed
/// to be legible on it, plus an optional accent. Computed once, off the main
/// actor, and cached with the artwork.
public struct ArtworkPalette: Hashable, Codable, Sendable {
    /// The dominant color of the cover's outer border.
    public var background: PaletteColor
    /// The most common distinct color, adjusted to read on `background`.
    public var primary: PaletteColor
    /// The next distinct color, adjusted the same way.
    public var secondary: PaletteColor
    /// `primary` at 60% over `background`.
    public var tertiary: PaletteColor
    /// The most saturated color with real coverage, or `nil` for covers without
    /// one (grayscale art), in which case Album accent falls back to System.
    public var accent: PaletteColor?
    /// Whether `background` is dark, so tinted contexts use light text.
    public var isDark: Bool
    /// The mean of every opaque pixel, in OKLab: the backdrop behind Spotify
    /// art, which may not be blurred (DESIGN §3.6.1).
    public var average: PaletteColor

    /// - Parameter average: The whole cover's mean color; `nil` uses
    ///   `background`.
    public init(
        background: PaletteColor,
        primary: PaletteColor,
        secondary: PaletteColor,
        tertiary: PaletteColor,
        accent: PaletteColor?,
        isDark: Bool,
        average: PaletteColor? = nil
    ) {
        self.background = background
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.accent = accent
        self.isDark = isDark
        self.average = average ?? background
    }

    public static let neutral = ArtworkPalette(
        background: PaletteColor(red: 0.16, green: 0.16, blue: 0.17),
        primary: .white,
        secondary: PaletteColor(red: 0.75, green: 0.75, blue: 0.76),
        tertiary: PaletteColor(red: 0.66, green: 0.66, blue: 0.67),
        accent: nil,
        isDark: true
    )

    // MARK: Rules

    /// Side of the thumbnail the palette is measured from.
    public static let sampleSide = 40
    /// The share of each side that counts as the border.
    public static let borderFraction = 0.15
    /// Number of color clusters.
    public static let clusterCount = 6
    /// Text colors must reach this contrast against `background`.
    public static let textContrast = 4.5
    /// An accent must cover at least this share of the cover...
    public static let accentCoverage = 0.05
    /// ...and be at least this colorful.
    public static let accentMinimumChroma = 0.08
    /// `background` darker than this OKLCH lightness counts as dark.
    public static let darkLightness = 0.6
    /// Squared OKLab distance below which two colors count as the same.
    static let distinctDistanceSquared = 0.08 * 0.08
    /// Fallback text when no cover color can reach the contrast bar.
    static let fallbackTextOpacity = 0.85

    // MARK: Measuring

    /// Measure `image`: one 40×40 redraw, then clustering over its pixels.
    public static func measure(_ image: CGImage) -> ArtworkPalette {
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .neutral }

        var grid: [PaletteColor?] = []
        grid.reserveCapacity(side * side)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else {
                grid.append(nil)
                continue
            }
            grid.append(PaletteColor(
                red: Double(pixels[index]) / 255 / alpha,
                green: Double(pixels[index + 1]) / 255 / alpha,
                blue: Double(pixels[index + 2]) / 255 / alpha
            ))
        }
        return measure(grid: grid, side: side)
    }

    /// Measure a square grid of samples in row order; `nil` marks a transparent
    /// pixel. Split out so tests can pass exact colors.
    public static func measure(grid: [PaletteColor?], side: Int) -> ArtworkPalette {
        precondition(grid.count == side * side, "The grid must be side × side.")
        let border = max(1, Int((Double(side) * borderFraction).rounded()))
        var samples: [Sample] = []
        samples.reserveCapacity(grid.count)
        for (index, color) in grid.enumerated() {
            guard let color else { continue }
            let x = index % side
            let y = index / side
            let isBorder = x < border || y < border || x >= side - border || y >= side - border
            let lab = color.oklab
            samples.append(Sample(l: lab.l, a: lab.a, b: lab.b, isBorder: isBorder))
        }
        guard !samples.isEmpty else { return .neutral }

        let clusters = KMeans.cluster(samples, k: clusterCount)
        let borderSamples = samples.filter(\.isBorder)
        let backgroundCluster = clusters.max { $0.borderCount < $1.borderCount }!
        // The mean of the border pixels in the winning cluster, so a cluster that
        // also spans the middle of the cover doesn't pull the border color inward.
        let background = backgroundCluster.borderCount > 0 && !borderSamples.isEmpty
            ? backgroundCluster.borderMean
            : backgroundCluster.center
        let isDark = background.oklch.lightness < darkLightness

        let byPopulation = clusters
            .filter { $0.count > 0 }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.order < $1.order }
        let candidates = byPopulation
            .map(\.center)
            .filter { $0.distanceSquared(to: background) >= distinctDistanceSquared }

        let fallback = fallbackText(on: background)
        var primary = fallback
        var primaryIndex: Int?
        for (index, candidate) in candidates.enumerated() {
            if let adjusted = candidate.adjusted(toContrast: textContrast, against: background) {
                primary = adjusted
                primaryIndex = index
                break
            }
        }

        var secondary: PaletteColor?
        if let primaryIndex {
            let original = candidates[primaryIndex]
            for candidate in candidates[(primaryIndex + 1)...]
            where candidate.distanceSquared(to: original) >= distinctDistanceSquared {
                if let adjusted = candidate.adjusted(toContrast: textContrast, against: background) {
                    secondary = adjusted
                    break
                }
            }
        }
        let resolvedSecondary = secondary
            ?? background.mixed(with: primary, amount: 0.8).adjusted(toContrast: textContrast, against: background)
            ?? primary

        let minimumCount = Double(samples.count) * accentCoverage
        let accent = clusters
            .filter { Double($0.count) >= minimumCount && $0.center.oklch.chroma >= accentMinimumChroma }
            .max { lhs, rhs in
                let a = lhs.center.oklch.chroma
                let b = rhs.center.oklch.chroma
                return a != b ? a < b : lhs.order > rhs.order
            }?
            .center

        let count = Double(samples.count)
        let sum = samples.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.l, $0.1 + $1.a, $0.2 + $1.b) }
        let average = PaletteColor(oklabL: sum.0 / count, a: sum.1 / count, b: sum.2 / count)

        return ArtworkPalette(
            background: background,
            primary: primary,
            secondary: resolvedSecondary,
            tertiary: background.mixed(with: primary, amount: 0.6),
            accent: accent,
            isDark: isDark,
            average: average
        )
    }

    /// White or black at 85% over `background`, whichever reads better.
    static func fallbackText(on background: PaletteColor) -> PaletteColor {
        let white = background.mixed(with: .white, amount: fallbackTextOpacity)
        let black = background.mixed(with: .black, amount: fallbackTextOpacity)
        return white.contrast(with: background) >= black.contrast(with: background) ? white : black
    }
}

// MARK: - Clustering

extension ArtworkPalette {
    struct Sample {
        var l: Double
        var a: Double
        var b: Double
        var isBorder: Bool
    }

    struct Cluster {
        /// Position in the original clustering, for stable tie-breaking.
        var order: Int
        var center: PaletteColor
        var count: Int
        var borderCount: Int
        var borderMean: PaletteColor
    }

    /// k-means in OKLab with a fixed seed: the same cover always gives the same
    /// clusters.
    enum KMeans {
        static let seed: UInt64 = 0x6875_6D5F_7061_6C65
        static let maximumIterations = 16

        static func cluster(_ samples: [Sample], k: Int) -> [Cluster] {
            var generator = SplitMix64(seed: seed)
            var centers = initialCenters(samples, k: min(k, samples.count), generator: &generator)
            var assignment = [Int](repeating: 0, count: samples.count)

            for iteration in 0..<maximumIterations {
                var changed = iteration == 0
                for (index, sample) in samples.enumerated() {
                    let nearest = nearestCenter(to: sample, in: centers)
                    if nearest != assignment[index] {
                        assignment[index] = nearest
                        changed = true
                    }
                }
                guard changed else { break }
                var sums = [(Double, Double, Double, Int)](repeating: (0, 0, 0, 0), count: centers.count)
                for (index, sample) in samples.enumerated() {
                    let c = assignment[index]
                    sums[c] = (sums[c].0 + sample.l, sums[c].1 + sample.a, sums[c].2 + sample.b, sums[c].3 + 1)
                }
                for c in centers.indices where sums[c].3 > 0 {
                    let n = Double(sums[c].3)
                    centers[c] = (sums[c].0 / n, sums[c].1 / n, sums[c].2 / n)
                }
            }

            return centers.indices.map { c in
                var count = 0
                var borderCount = 0
                var borderSum = (0.0, 0.0, 0.0)
                for (index, sample) in samples.enumerated() where assignment[index] == c {
                    count += 1
                    if sample.isBorder {
                        borderCount += 1
                        borderSum = (borderSum.0 + sample.l, borderSum.1 + sample.a, borderSum.2 + sample.b)
                    }
                }
                let center = PaletteColor(oklabL: centers[c].0, a: centers[c].1, b: centers[c].2)
                let borderMean = borderCount > 0
                    ? PaletteColor(
                        oklabL: borderSum.0 / Double(borderCount),
                        a: borderSum.1 / Double(borderCount),
                        b: borderSum.2 / Double(borderCount)
                    )
                    : center
                return Cluster(order: c, center: center, count: count, borderCount: borderCount, borderMean: borderMean)
            }
        }

        /// k-means++ seeding: each new center is drawn with probability
        /// proportional to its squared distance from the nearest center so far.
        private static func initialCenters(
            _ samples: [Sample],
            k: Int,
            generator: inout SplitMix64
        ) -> [(Double, Double, Double)] {
            var centers: [(Double, Double, Double)] = []
            let first = samples[Int(generator.next() % UInt64(samples.count))]
            centers.append((first.l, first.a, first.b))
            var distances = samples.map { squaredDistance($0, centers[0]) }
            while centers.count < k {
                let total = distances.reduce(0, +)
                guard total > 0 else { break }
                var target = Double(generator.next() >> 11) / Double(1 << 53) * total
                var chosen = samples.count - 1
                for (index, distance) in distances.enumerated() {
                    target -= distance
                    if target <= 0 {
                        chosen = index
                        break
                    }
                }
                let sample = samples[chosen]
                let center = (sample.l, sample.a, sample.b)
                centers.append(center)
                for index in samples.indices {
                    distances[index] = min(distances[index], squaredDistance(samples[index], center))
                }
            }
            return centers
        }

        private static func nearestCenter(to sample: Sample, in centers: [(Double, Double, Double)]) -> Int {
            var best = 0
            var bestDistance = Double.infinity
            for (index, center) in centers.enumerated() {
                let distance = squaredDistance(sample, center)
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
            return best
        }

        private static func squaredDistance(_ sample: Sample, _ center: (Double, Double, Double)) -> Double {
            let dl = sample.l - center.0
            let da = sample.a - center.1
            let db = sample.b - center.2
            return dl * dl + da * da + db * db
        }
    }

    /// A small, fast, seedable generator, so clustering is repeatable.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
