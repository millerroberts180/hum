import Accelerate
import CoreGraphics
import Foundation
import Synchronization

/// An sRGB color for painting covers, components 0...1.
struct ArtColor: Sendable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    static let black = ArtColor(0x000000)
    static let white = ArtColor(0xFFFFFF)

    func cgColor(_ alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: ArtCanvas.space, components: [red, green, blue, alpha].map { CGFloat($0) })
            ?? CGColor(gray: 0, alpha: alpha)
    }

    func mixed(with other: ArtColor, _ amount: Double) -> ArtColor {
        ArtColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    /// Brighter above 1, darker below.
    func scaled(_ factor: Double) -> ArtColor {
        ArtColor(red: red * factor, green: green * factor, blue: blue * factor)
    }

    static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }

    /// The color at `t` along `stops` (location 0...1, ascending).
    static func ramp(_ stops: [(ArtColor, Double)], _ t: Double) -> ArtColor {
        guard let first = stops.first, let last = stops.last else { return .black }
        if t <= first.1 { return first.0 }
        for (lower, upper) in zip(stops, stops.dropFirst()) where t <= upper.1 {
            let span = max(0.000_1, upper.1 - lower.1)
            return lower.0.mixed(with: upper.0, (t - lower.1) / span)
        }
        return last.0
    }
}

/// Smooth 0 → 1 between `edge0` and `edge1`.
func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}

/// An opaque square sRGB bitmap that cover scenes paint into: Core Graphics for
/// shapes, gradients, and type, and vImage for blur, glow, and tone curves.
///
/// Positions and lengths are fractions of the side, with the origin at the
/// bottom left as in Core Graphics.
final class ArtCanvas {
    static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    let side: Int
    let context: CGContext
    private var scratch: UnsafeMutableRawPointer?

    init?(side: Int) {
        guard side > 0, let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: Self.space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setShouldSmoothFonts(false)
        self.side = side
        self.context = context
    }

    deinit {
        scratch?.deallocate()
    }

    var size: CGFloat { CGFloat(side) }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * Double(side), y: y * Double(side))
    }

    func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
        CGRect(x: x * Double(side), y: y * Double(side), width: width * Double(side), height: height * Double(side))
    }

    var bounds: CGRect { CGRect(x: 0, y: 0, width: side, height: side) }

    func makeImage() -> CGImage? {
        context.makeImage()
    }

    /// A second canvas with the same pixels, for glows and layered effects.
    func copy() -> ArtCanvas? {
        guard let other = ArtCanvas(side: side), let from = context.data, let to = other.context.data else { return nil }
        to.copyMemory(from: from, byteCount: context.bytesPerRow * side)
        return other
    }

    // MARK: Painting

    func fill(_ color: ArtColor) {
        context.setFillColor(color.cgColor())
        solid { $0.fill(bounds) }
    }

    /// Core Graphics can mix up colors when several threads fill shapes in
    /// solid color at once wherever an edge, a mask, or a glyph only partly
    /// covers a pixel, so every solid fill, stroke, and line of text goes
    /// through one lock. Gradients, images, and the filters below are safe
    /// to run side by side.
    func solid(_ body: (CGContext) -> Void) {
        Self.solidLock.withLock { _ in body(context) }
    }

    private static let solidLock = Mutex(())

    /// Runs `body` with a blend mode and opacity, restoring both afterward.
    func layer(_ blend: CGBlendMode = .normal, alpha: Double = 1, _ body: () -> Void) {
        context.saveGState()
        context.setBlendMode(blend)
        context.setAlpha(alpha)
        body()
        context.restoreGState()
    }

    func linearGradient(
        _ stops: [(ArtColor, Double)],
        from start: (Double, Double),
        to end: (Double, Double),
        alpha: Double = 1
    ) {
        let colors = stops.map { $0.0.cgColor(alpha) } as CFArray
        let locations = stops.map { CGFloat($0.1) }
        guard let gradient = CGGradient(colorsSpace: Self.space, colors: colors, locations: locations) else { return }
        context.drawLinearGradient(
            gradient,
            start: point(start.0, start.1),
            end: point(end.0, end.1),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    /// A soft round light: `color` at `alpha` in the middle, fading to nothing at
    /// `radius` along a smooth falloff.
    func glow(_ color: ArtColor, at center: (Double, Double), radius: Double, alpha: Double, hardness: Double = 0) {
        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        for step in 0...8 {
            let t = Double(step) / 8
            let fade = 1 - smoothstep(hardness, 1, t)
            colors.append(color.cgColor(alpha * fade * fade))
            locations.append(CGFloat(t))
        }
        guard let gradient = CGGradient(colorsSpace: Self.space, colors: colors as CFArray, locations: locations) else { return }
        let c = point(center.0, center.1)
        context.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius * size, options: [])
    }

    /// Draws `image` across the canvas, or across `frame` in canvas fractions.
    func draw(_ image: CGImage?, in frame: CGRect? = nil, blend: CGBlendMode = .normal, alpha: Double = 1) {
        guard let image else { return }
        let target = frame.map { rect($0.minX, $0.minY, $0.width, $0.height) } ?? bounds
        layer(blend, alpha: alpha) {
            context.draw(image, in: target)
        }
    }

    /// Fills `color` wherever `mask` is light (a grayscale image stretched over
    /// the canvas, or over `frame`).
    func fill(_ color: ArtColor, through mask: CGImage?, in frame: CGRect? = nil, blend: CGBlendMode = .normal, alpha: Double = 1) {
        guard let mask else { return }
        let target = frame.map { rect($0.minX, $0.minY, $0.width, $0.height) } ?? bounds
        layer(blend, alpha: alpha) {
            context.clip(to: target, mask: mask)
            context.setFillColor(color.cgColor())
            solid { $0.fill(target) }
        }
    }

    // MARK: Filters

    /// A Gaussian-like blur (two tent passes) with a deviation of `radius`.
    func blur(_ radius: Double) {
        let kernel = Self.kernelWidth(deviation: radius * size)
        guard kernel > 1, var source = buffer, var temporary = scratchBuffer() else { return }
        let flags = vImage_Flags(kvImageEdgeExtend)
        vImageTentConvolve_ARGB8888(&source, &temporary, nil, 0, 0, kernel, kernel, nil, flags)
        vImageTentConvolve_ARGB8888(&temporary, &source, nil, 0, 0, kernel, kernel, nil, flags)
    }

    /// Applies a curve to each channel: lifted blacks, rolled-off highlights,
    /// and the color casts of film.
    func tone(red: ToneCurve, green: ToneCurve, blue: ToneCurve) {
        guard var pixels = buffer else { return }
        let r = red.table(), g = green.table(), b = blue.table()
        // vImage names the channels alpha, red, green, blue; this bitmap stores
        // red, green, blue, unused, so each table moves one place.
        _ = r.withUnsafeBufferPointer { rp in
            g.withUnsafeBufferPointer { gp in
                b.withUnsafeBufferPointer { bp in
                    vImageTableLookUp_ARGB8888(&pixels, &pixels, rp.baseAddress, gp.baseAddress, bp.baseAddress, nil, vImage_Flags(kvImageNoFlags))
                }
            }
        }
    }

    func tone(_ curve: ToneCurve) {
        tone(red: curve, green: curve, blue: curve)
    }

    /// Light bleeding past the bright parts, as through a real lens: everything
    /// above `threshold` (0...1) is blurred by `radius` and screened back on.
    func bloom(threshold: Double, radius: Double, strength: Double, tint: ArtColor = .white) {
        guard let glow = copy() else { return }
        glow.tone(ToneCurve(black: 0, white: 1, lift: threshold, contrast: 0))
        glow.blur(radius)
        if tint != .white {
            glow.layer(.multiply) { glow.fill(tint) }
        }
        draw(glow.makeImage(), blend: .screen, alpha: strength)
    }

    /// Darkens the corners, as a lens does.
    func vignette(_ strength: Double, reach: Double = 0.75, color: ArtColor = .black) {
        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        for step in 0...8 {
            let t = Double(step) / 8
            colors.append(color.cgColor(strength * smoothstep(0.35, 1, t)))
            locations.append(CGFloat(t))
        }
        guard let gradient = CGGradient(colorsSpace: Self.space, colors: colors as CFArray, locations: locations) else { return }
        let c = point(0.5, 0.5)
        context.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: reach * size * 1.414, options: .drawsAfterEndLocation)
    }

    /// Film grain: seeded noise laid over the image, strongest in the midtones.
    /// `clump` is the grain size in pixels.
    func grain(_ amount: Double, clump: Double = 1, seed: UInt64) {
        guard let tile = Self.grainTile(seed: seed) else { return }
        let tileSide = CGFloat(Self.grainSide) * CGFloat(clump)
        layer(.overlay, alpha: amount) {
            context.interpolationQuality = clump > 1.2 ? .medium : .none
            // Offset by the seed so neighboring covers don't share a pattern.
            let offset = CGFloat(seed % 97)
            context.translateBy(x: -offset, y: -offset)
            context.draw(tile, in: CGRect(x: 0, y: 0, width: tileSide, height: tileSide), byTiling: true)
        }
    }

    /// Adds `color` at `alpha` to the pixels under a small ellipse (`frame` in
    /// canvas fractions), as the plus-lighter blend would. It writes straight
    /// into the bitmap, which for thousands of sparks is far quicker than
    /// filling each one through `solid`.
    func addLight(_ color: ArtColor, ellipse frame: CGRect, alpha: Double) {
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self), alpha > 0 else { return }
        // Memory runs top to bottom; canvas y runs bottom to top.
        let rowBytes = context.bytesPerRow
        let scale = size
        let cx = frame.midX * scale, cy = frame.midY * scale
        let rx = max(frame.width * scale / 2, 0.01), ry = max(frame.height * scale / 2, 0.01)
        let minX = max(0, Int((cx - rx).rounded(.down))), maxX = min(side - 1, Int((cx + rx).rounded(.up)))
        let minY = max(0, Int((cy - ry).rounded(.down))), maxY = min(side - 1, Int((cy + ry).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }
        let light = [color.red, color.green, color.blue].map { $0 * alpha * 255 }
        func add(_ x: Int, _ y: Int, _ coverage: Double) {
            guard x >= 0, y >= 0, x < side, y < side, coverage > 0 else { return }
            let pixel = data + (side - 1 - y) * rowBytes + x * 4
            for channel in 0..<3 {
                pixel[channel] = UInt8(min(255, (Double(pixel[channel]) + light[channel] * coverage).rounded()))
            }
        }
        // A spark smaller than a pixel lights the pixels around its middle by
        // its area, shared out by how close it is to each.
        let area = Double.pi * rx * ry
        if area < 1.5 {
            let fx = cx - 0.5, fy = cy - 0.5
            let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
            let tx = fx - Double(x0), ty = fy - Double(y0)
            add(x0, y0, area * (1 - tx) * (1 - ty))
            add(x0 + 1, y0, area * tx * (1 - ty))
            add(x0, y0 + 1, area * (1 - tx) * ty)
            add(x0 + 1, y0 + 1, area * tx * ty)
            return
        }
        let samples = 4
        for y in minY...maxY {
            for x in minX...maxX {
                var covered = 0
                for sy in 0..<samples {
                    let dy = (Double(y) + (Double(sy) + 0.5) / Double(samples) - cy) / ry
                    for sx in 0..<samples {
                        let dx = (Double(x) + (Double(sx) + 0.5) / Double(samples) - cx) / rx
                        if dx * dx + dy * dy <= 1 { covered += 1 }
                    }
                }
                add(x, y, Double(covered) / Double(samples * samples))
            }
        }
    }

    // MARK: Buffers

    private var buffer: vImage_Buffer? {
        guard let data = context.data else { return nil }
        return vImage_Buffer(data: data, height: vImagePixelCount(side), width: vImagePixelCount(side), rowBytes: context.bytesPerRow)
    }

    private func scratchBuffer() -> vImage_Buffer? {
        let bytes = context.bytesPerRow * side
        if scratch == nil {
            scratch = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 64)
        }
        guard let scratch else { return nil }
        return vImage_Buffer(data: scratch, height: vImagePixelCount(side), width: vImagePixelCount(side), rowBytes: context.bytesPerRow)
    }

    /// The tent width whose double pass matches a Gaussian of `deviation` pixels.
    private static func kernelWidth(deviation: Double) -> UInt32 {
        let width = Int((deviation * 1.73).rounded())
        return UInt32(max(1, width | 1))
    }

    static let grainSide = 192

    /// Gray noise centered on middle gray, which overlay leaves unchanged.
    private static func grainTile(seed: UInt64) -> CGImage? {
        var random = ArtRandom(seed: seed ^ 0x6772_6169_6E)
        var bytes = [UInt8](repeating: 128, count: grainSide * grainSide)
        for index in bytes.indices {
            bytes[index] = ArtColor.byte(0.5 + random.normal() * 0.16)
        }
        return ArtField.image(bytes, width: grainSide, height: grainSide, components: 1)
    }
}

/// A per-channel tone curve, built into a 256-entry table.
struct ToneCurve: Sendable {
    /// Output for pure black, so shadows can sit above zero like printed film.
    var black: Double = 0
    /// Output for pure white.
    var white: Double = 1
    /// Input below this maps to `black`.
    var lift: Double = 0
    /// An S-curve, 0 for none.
    var contrast: Double = 0
    /// Brightens the midtones above 1, darkens them below.
    var gamma: Double = 1

    static let identity = ToneCurve()

    func table() -> [UInt8] {
        (0..<256).map { index in
            var x = Double(index) / 255
            x = max(0, (x - lift) / max(0.001, 1 - lift))
            x = pow(x, 1 / gamma)
            if contrast != 0 {
                let s = x * x * (3 - 2 * x)
                x += (s - x) * contrast
            }
            return ArtColor.byte(black + (white - black) * x)
        }
    }
}
