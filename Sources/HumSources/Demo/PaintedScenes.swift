import CoreGraphics
import Foundation

/// Soft color melting into color, as through fogged glass or a lens smeared
/// with light: a handful of colors blended along warped, organic seams.
struct SoftMesh {
    var points: [(color: ArtColor, x: Double, y: Double, reach: Double)]
    /// How far the seams wander, as a fraction of the side.
    var warp = 0.16
    /// Out-of-focus leaves in front, 0 for none.
    var leaves = 0.0
    var leafColor = ArtColor(0x1F3A2C)
    var seed: UInt64

    func paint(_ canvas: ArtCanvas) {
        let noise = ValueNoise(seed: seed)
        // Blend in linear light so the colors between two points stay clean.
        let linear = points.map { point in
            (pow(point.color.red, 2.2), pow(point.color.green, 2.2), pow(point.color.blue, 2.2), point.x, point.y, point.reach)
        }
        let mesh = ArtField.color(width: 120, height: 120) { u, v in
            let wu = u + (noise.fractal(u * 2.1, v * 2.1, octaves: 3) - 0.5) * warp * 2
            let wv = v + (noise.fractal(u * 2.1 + 9, v * 2.1 + 4, octaves: 3) - 0.5) * warp * 2
            var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
            for point in linear {
                let dx = wu - point.3
                let dy = wv - point.4
                let weight = exp(-(dx * dx + dy * dy) / (point.5 * point.5)) + 0.0001
                red += point.0 * weight
                green += point.1 * weight
                blue += point.2 * weight
                total += weight
            }
            return ArtColor(red: pow(red / total, 1 / 2.2), green: pow(green / total, 1 / 2.2), blue: pow(blue / total, 1 / 2.2))
        }
        canvas.draw(mesh)

        // Fronds reaching in from the edges, close to the lens and far out of
        // focus: a curved stem with leaves along it.
        if leaves > 0 {
            var random = ArtRandom(seed: seed ^ 0x1EAF)
            let context = canvas.context
            for frond in 0..<3 {
                let fromLeft = frond != 1
                let base = CGPoint(x: fromLeft ? -0.04 : 1.04, y: random.range(frond == 0 ? 0.55...0.95 : 0.05...0.5))
                let heading = (fromLeft ? 0 : Double.pi) + random.range(-0.5...0.5)
                let length = random.range(0.3...0.5)
                let bend = random.range(-0.9...0.9)
                let shade = leafColor.mixed(with: ArtColor(0x6F9A6A), random.range(0...0.35))
                context.setFillColor(shade.cgColor(random.range(0.6...0.85) * leaves))
                context.setStrokeColor(shade.cgColor(0.7 * leaves))
                context.setLineWidth(canvas.size * 0.008)
                let steps = 5
                var point = base
                var angle = heading
                let stem = CGMutablePath()
                stem.move(to: canvas.point(point.x, point.y))
                for step in 0..<steps {
                    let t = Double(step + 1) / Double(steps)
                    angle += bend / Double(steps)
                    point = CGPoint(x: point.x + cos(angle) * length / Double(steps), y: point.y + sin(angle) * length / Double(steps))
                    stem.addLine(to: canvas.point(point.x, point.y))
                    // A pair of leaves at each node, smaller toward the tip.
                    for sideSign in [-1.0, 1.0] {
                        let leafLength = canvas.size * (0.22 - 0.1 * t) * random.range(0.8...1.15)
                        let leafAngle = angle + sideSign * random.range(0.45...0.75)
                        context.saveGState()
                        context.translateBy(x: canvas.point(point.x, point.y).x, y: canvas.point(point.x, point.y).y)
                        context.rotate(by: leafAngle)
                        let leaf = CGMutablePath()
                        leaf.move(to: .zero)
                        leaf.addCurve(to: CGPoint(x: leafLength, y: 0), control1: CGPoint(x: leafLength * 0.3, y: leafLength * 0.2), control2: CGPoint(x: leafLength * 0.75, y: leafLength * 0.1))
                        leaf.addCurve(to: .zero, control1: CGPoint(x: leafLength * 0.7, y: -leafLength * 0.06), control2: CGPoint(x: leafLength * 0.3, y: -leafLength * 0.12))
                        context.addPath(leaf)
                        canvas.solid { $0.fillPath() }
                        context.restoreGState()
                    }
                }
                context.addPath(stem)
                canvas.solid { $0.strokePath() }
            }
            canvas.blur(0.03)
        } else {
            canvas.blur(0.006)
        }

        // Breath on the glass: a faint uneven bloom of light.
        let fog = ArtField.gray(width: 64, height: 64) { u, v in
            noise.fractal(u * 4 + 30, v * 4, octaves: 4)
        }
        canvas.draw(fog, blend: .softLight, alpha: 0.5)
    }
}

/// An abstract painting of soft-edged color fields: thin layers of paint
/// scrubbed over a colored ground, the edges feathered and uneven, the canvas
/// weave showing through.
struct ColorFieldPainting {
    var ground: ArtColor
    var fields: [(color: ArtColor, frame: CGRect)]
    /// How visible the brushwork is.
    var brush = 1.0
    var seed: UInt64

    func paint(_ canvas: ArtCanvas) {
        let noise = ValueNoise(seed: seed)
        var random = ArtRandom(seed: seed)
        canvas.fill(ground)
        // An uneven ground, darker where the paint pooled.
        let mottle = ArtField.gray(width: 64, height: 64) { u, v in
            noise.fractal(u * 3 + 50, v * 3, octaves: 5)
        }
        canvas.draw(mottle, blend: .overlay, alpha: 0.45)

        for (index, field) in fields.enumerated() {
            let frame = field.frame
            let offset = Double(index) * 13.7
            // Feathered, wandering edges: the distance to the rectangle, pushed
            // around by noise, softened through a smooth step.
            let mask = ArtField.gray(width: 160, height: 160) { u, v in
                let dx = max(frame.minX - u, u - frame.maxX)
                let dy = max(frame.minY - v, v - frame.maxY)
                let outside = (max(dx, 0) * max(dx, 0) + max(dy, 0) * max(dy, 0)).squareRoot()
                let distance = outside > 0 ? outside : max(dx, dy)
                let wander = (noise.fractal(u * 6 + offset, v * 6, octaves: 4) - 0.5) * 0.05
                let fray = (noise.fractal(u * 24 + offset, v * 9, octaves: 2) - 0.5) * 0.014
                return 1 - smoothstep(-0.03, 0.022, distance + wander + fray)
            }
            guard let mask else { continue }
            // Several thin glazes, each a little different, so the color has depth.
            for glaze in 0..<3 {
                let shade = field.color.scaled(random.range(0.92...1.06)).mixed(with: ground, glaze == 0 ? 0.2 : 0)
                canvas.fill(shade, through: mask, alpha: glaze == 0 ? 0.9 : 0.35)
            }
            // Brushwork inside the field: long scrubbed strokes that wander a
            // little and fade in and out, thick in places and dry in others.
            let strokes = ArtField.gray(width: 90, height: 240) { u, v in
                let drift = v + (noise.fractal(u * 1.6 + offset, v * 1.6, octaves: 2) - 0.5) * 0.06
                let stroke = noise.fractal(u * 2.4 + offset, drift * 38, octaves: 3)
                let load = noise.fractal(u * 3 + offset + 5, v * 3, octaves: 2)
                return 0.5 + (stroke - 0.5) * (0.4 + load * 1.2)
            }
            canvas.context.saveGState()
            canvas.context.clip(to: canvas.bounds, mask: mask)
            canvas.draw(strokes, blend: .overlay, alpha: 0.32 * brush)
            canvas.context.restoreGState()
        }

        // Strokes across the whole canvas at a slight angle, and the weave.
        let wash = ArtField.gray(width: 60, height: 200) { u, v in
            noise.fractal(u * 2 + 80, v * 30, octaves: 3)
        }
        canvas.context.saveGState()
        canvas.context.translateBy(x: canvas.size / 2, y: canvas.size / 2)
        canvas.context.rotate(by: random.range(-0.08...0.08))
        canvas.context.translateBy(x: -canvas.size * 0.6, y: -canvas.size * 0.6)
        canvas.draw(wash, in: CGRect(x: 0, y: 0, width: 1.2, height: 1.2), blend: .overlay, alpha: 0.18 * brush)
        canvas.context.restoreGState()
        canvas.blur(0.0012)
        canvas.weave(0.08)
    }
}

extension ArtCanvas {
    /// The fine crosshatch of linen canvas under paint.
    func weave(_ amount: Double) {
        let side = 6
        var bytes = [UInt8](repeating: 128, count: side * side)
        for row in 0..<side {
            for column in 0..<side {
                let warp = sin(Double(column) / Double(side) * 2 * .pi)
                let weft = sin(Double(row) / Double(side) * 2 * .pi)
                bytes[row * side + column] = ArtColor.byte(0.5 + (row % 3 == 0 ? warp : weft) * 0.25)
            }
        }
        guard let tile = ArtField.image(bytes, width: side, height: side, components: 1) else { return }
        layer(.overlay, alpha: amount) {
            context.interpolationQuality = .low
            let tileSide = CGFloat(side) * max(1, size / 400)
            context.draw(tile, in: CGRect(x: 0, y: 0, width: tileSide, height: tileSide), byTiling: true)
        }
    }
}
