import CoreGraphics
import Foundation

/// SplitMix64: a small deterministic generator, so every cover paints the same
/// pixels on every run.
struct ArtRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// A seed from text, so a title or key always picks the same cover.
    static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func range(_ bounds: ClosedRange<Double>) -> Double {
        bounds.lowerBound + unit() * (bounds.upperBound - bounds.lowerBound)
    }

    mutating func below(_ bound: Int) -> Int {
        Int(next() % UInt64(max(1, bound)))
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    /// Roughly normal, mean 0 and deviation 1 (the sum of four uniforms).
    mutating func normal() -> Double {
        (unit() + unit() + unit() + unit() - 2) * 1.732
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[below(items.count)]
    }
}

/// Seeded value noise: smooth random values on a lattice, layered into fractal
/// noise for clouds, waves, mist, paint, and paper.
struct ValueNoise: Sendable {
    private let seed: UInt32

    init(seed: UInt64) {
        self.seed = UInt32(truncatingIfNeeded: seed ^ (seed >> 32))
    }

    /// 0...1 at (`x`, `y`), one lattice cell per unit.
    func value(_ x: Double, _ y: Double) -> Double {
        let fx = x.rounded(.down)
        let fy = y.rounded(.down)
        let ix = Int32(truncatingIfNeeded: Int(fx))
        let iy = Int32(truncatingIfNeeded: Int(fy))
        let tx = Self.fade(x - fx)
        let ty = Self.fade(y - fy)
        let a = lattice(ix, iy)
        let b = lattice(ix &+ 1, iy)
        let c = lattice(ix, iy &+ 1)
        let d = lattice(ix &+ 1, iy &+ 1)
        let bottom = a + (b - a) * tx
        let top = c + (d - c) * tx
        return bottom + (top - bottom) * ty
    }

    /// Fractal noise, roughly 0...1: `octaves` layers, each at twice the
    /// frequency and `gain` times the amplitude of the one before.
    func fractal(_ x: Double, _ y: Double, octaves: Int, gain: Double = 0.5) -> Double {
        var sum = 0.0
        var amplitude = 1.0
        var total = 0.0
        var frequency = 1.0
        for octave in 0..<octaves {
            // Each layer is shifted so the lattices don't line up.
            let shift = Double(octave) * 17.31
            sum += value(x * frequency + shift, y * frequency - shift) * amplitude
            total += amplitude
            amplitude *= gain
            frequency *= 2.03
        }
        return sum / total
    }

    /// Quintic smoothstep, so the lattice never shows as creases.
    private static func fade(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    private func lattice(_ x: Int32, _ y: Int32) -> Double {
        var h = UInt32(bitPattern: x) &* 0x8DA6_B343
        h ^= UInt32(bitPattern: y) &* 0xD816_3841
        h ^= seed &* 0xCB1A_B31F
        h ^= h >> 13
        h &*= 0x5BD1_E995
        h ^= h >> 15
        return Double(h & 0xFF_FFFF) / Double(0xFF_FFFF)
    }
}

/// A small image computed point by point, which Core Graphics smooths as it
/// scales it up to cover size. `u` runs left to right and `v` bottom to top,
/// both 0...1.
enum ArtField {
    /// A grayscale image, for masks and textures; values are clamped to 0...1.
    static func gray(width: Int, height: Int, _ value: (_ u: Double, _ v: Double) -> Double) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let v = 1 - (Double(row) + 0.5) / Double(height)
            for column in 0..<width {
                let u = (Double(column) + 0.5) / Double(width)
                bytes[row * width + column] = ArtColor.byte(value(u, v))
            }
        }
        return image(bytes, width: width, height: height, components: 1)
    }

    /// A color image, for skies, water, and paint.
    static func color(width: Int, height: Int, _ value: (_ u: Double, _ v: Double) -> ArtColor) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            let v = 1 - (Double(row) + 0.5) / Double(height)
            for column in 0..<width {
                let u = (Double(column) + 0.5) / Double(width)
                let color = value(u, v)
                let index = (row * width + column) * 4
                bytes[index] = ArtColor.byte(color.red)
                bytes[index + 1] = ArtColor.byte(color.green)
                bytes[index + 2] = ArtColor.byte(color.blue)
            }
        }
        return image(bytes, width: width, height: height, components: 4)
    }

    /// An image from raw bytes, row 0 at the top: one gray byte per pixel, or
    /// four (red, green, blue, unused).
    static func image(_ bytes: [UInt8], width: Int, height: Int, components: Int) -> CGImage? {
        let gray = components == 1
        // Masks must be device gray; Core Graphics reads their samples as coverage.
        let space = gray ? CGColorSpaceCreateDeviceGray() : ArtCanvas.space
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * components,
            bytesPerRow: width * components,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
