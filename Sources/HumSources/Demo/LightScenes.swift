import CoreGraphics
import Foundation

/// A night street photographed far out of focus: lamps, windows, and tail lights
/// melted into discs of light, on pushed film with its halation and grain.
struct CityBokeh {
    var night: [(ArtColor, Double)]
    /// The lights, with how often each appears.
    var lights: [(ArtColor, Double)]
    var count = 90
    /// Where the lights gather, as a fraction of the height.
    var band: ClosedRange<Double> = 0.25...0.72
    /// The color film adds around bright lights.
    var halation = ArtColor(0xFF5A2A)
    var seed: UInt64

    func paint(_ canvas: ArtCanvas) {
        var random = ArtRandom(seed: seed)
        let noise = ValueNoise(seed: seed)
        canvas.linearGradient(night, from: (0.5, 0), to: (0.5, 1))

        // Shapes of buildings and street, too blurred to make out.
        for _ in 0..<7 {
            let x = random.range(-0.1...0.9)
            let width = random.range(0.1...0.35)
            let height = random.range(0.25...0.75)
            canvas.context.setFillColor(ArtColor.ramp(night, 0.5).scaled(random.range(0.6...1.5)).cgColor(0.5))
            canvas.solid { $0.fill(canvas.rect(x, 0, width, height)) }
        }
        canvas.blur(0.04)
        // A faint glow from the street below.
        canvas.layer(.screen) {
            canvas.glow(lights[0].0, at: (0.5, 0.35), radius: 0.7, alpha: 0.22)
        }

        let total = lights.reduce(0) { $0 + $1.1 }
        // Most lights gather in a band at street level; a row of lamps runs
        // gently away through it, shrinking with distance.
        let row = (start: random.range(0.05...0.25), rise: random.range(-0.12...0.12))
        for index in 0..<count {
            var x: Double
            var y: Double
            var radius: Double
            if index % 4 == 0 {
                let t = random.unit()
                x = row.start + t * 0.9
                y = (band.lowerBound + band.upperBound) / 2 + row.rise * (t - 0.5) + random.normal() * 0.02
                radius = 0.016 + (1 - t) * random.range(0.01...0.05)
            } else {
                // Many small distant lights, a few large near ones.
                let far = Double(index) / Double(count)
                radius = 0.018 + pow(random.unit(), 3) * 0.1 * (1.2 - far * 0.6)
                x = random.range(-0.05...1.05)
                y = random.chance(0.8)
                    ? band.lowerBound + (band.upperBound - band.lowerBound) * (random.unit() + random.unit()) / 2
                    : random.range(0...1)
            }
            var pick = random.unit() * total
            var color = lights[0].0
            for light in lights {
                pick -= light.1
                if pick <= 0 {
                    color = light.0
                    break
                }
            }
            let brightness = random.range(0.2...0.7) * (radius > 0.06 ? 0.55 : 1)
            canvas.bokeh(at: (x, y), radius: radius, color: color.scaled(random.range(0.85...1.1)), alpha: brightness, noise: noise)
        }

        // Film: bright lights spread a warm halo into the emulsion.
        canvas.bloom(threshold: 0.45, radius: 0.025, strength: 0.55)
        if let halo = canvas.copy() {
            halo.tone(ToneCurve(lift: 0.55))
            halo.blur(0.012)
            halo.layer(.multiply) { halo.fill(halation) }
            canvas.draw(halo.makeImage(), blend: .screen, alpha: 0.9)
        }
    }
}

extension ArtCanvas {
    /// One out-of-focus light: an even disc with a brighter rim, squeezed into a
    /// cat's eye toward the corners as a real lens does.
    func bokeh(at center: (Double, Double), radius: Double, color: ArtColor, alpha: Double, noise: ValueNoise) {
        let c = point(center.0, center.1)
        let r = radius * size
        let dx = center.0 - 0.5
        let dy = center.1 - 0.5
        let offCenter = (dx * dx + dy * dy).squareRoot()
        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        context.clip()
        if offCenter > 0.15 {
            // The lens barrel cuts the far side of the disc.
            let shift = (offCenter - 0.15) * 2.2 * r / offCenter
            let cut = CGPoint(x: c.x - CGFloat(dx) * shift, y: c.y - CGFloat(dy) * shift)
            context.addEllipse(in: CGRect(x: cut.x - r * 1.05, y: cut.y - r * 1.05, width: r * 2.1, height: r * 2.1))
            context.clip()
        }
        let colors = [
            color.cgColor(alpha * 0.78), color.cgColor(alpha * 0.82),
            color.mixed(with: .white, 0.2).cgColor(alpha), color.cgColor(alpha * 0.3),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: ArtCanvas.space, colors: colors, locations: [0, 0.78, 0.93, 1]) {
            context.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        }
        // Faint rings and specks inside, from dust and the lens's own surfaces.
        let speck = noise.value(center.0 * 40, center.1 * 40)
        if speck > 0.5 {
            context.setStrokeColor(color.cgColor(alpha * 0.12))
            context.setLineWidth(max(1, r * 0.06))
            solid { $0.strokeEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.55, width: r * 1.1, height: r * 1.1)) }
        }
        context.restoreGState()
    }
}

/// A person in silhouette, head and shoulders, seen from behind or with the
/// face turned into shadow: a shape and a pose, never a likeness.
struct ArtFigure {
    enum Hair: CaseIterable {
        case cropped, long, curls, bun
    }

    /// The middle of the head.
    var x: Double
    var y: Double
    /// Half the width of the head.
    var head: Double
    /// Half the width across the shoulders.
    var shoulders: Double
    var hair: Hair
    /// Leans the head, in radians; positive tips it to the left.
    var tilt = 0.0
    /// Turns the body, -1...1; positive turns the face toward the right.
    var turn = 0.0
    var seed: UInt64

    /// A white silhouette on black, softened by `focus` (a blur deviation).
    /// With `cutout`, a copy nudged by that much is taken away again, leaving
    /// only the edges on the opposite side.
    func mask(side: Int, focus: Double = 0, cutout: (Double, Double)? = nil) -> ArtCanvas? {
        guard let canvas = ArtCanvas(side: side) else { return nil }
        canvas.fill(.black)
        canvas.context.setFillColor(ArtColor.white.cgColor())
        let parts = parts(canvas)
        for part in parts {
            canvas.context.addPath(part)
            canvas.solid { $0.fillPath() }
        }
        if let cutout {
            canvas.context.translateBy(x: cutout.0 * canvas.size, y: cutout.1 * canvas.size)
            canvas.context.setFillColor(ArtColor.black.cgColor())
            for part in parts {
                canvas.context.addPath(part)
                canvas.solid { $0.fillPath() }
            }
            canvas.context.translateBy(x: -cutout.0 * canvas.size, y: -cutout.1 * canvas.size)
        }
        if focus > 0 { canvas.blur(focus) }
        return canvas
    }

    private func parts(_ canvas: ArtCanvas) -> [CGPath] {
        let noise = ValueNoise(seed: seed)
        var random = ArtRandom(seed: seed)
        let h = head
        let ry = head * 1.22
        func p(_ px: Double, _ py: Double) -> CGPoint { canvas.point(px, py) }

        // The neck sits under the back of the skull and shifts toward the face
        // when the body turns; the nearer shoulder looks broader.
        let neckX = x + turn * h * 0.18
        let neckHalf = h * 0.6
        let neckTop = y - ry * 0.7
        let neckBase = y - ry * 1.2
        // Seen in profile, the face shows its outline and the shoulders
        // foreshorten.
        let profile = smoothstep(0.55, 0.95, abs(turn))
        let left = shoulders * (1 + turn * 0.22) * (1 - profile * 0.22)
        let right = shoulders * (1 - turn * 0.22) * (1 - profile * 0.22)
        // The far shoulder sits a little higher as the body turns away.
        let leftTop = neckBase - h * (random.range(0.55...0.75) + turn * 0.12)
        let rightTop = neckBase - h * (random.range(0.55...0.75) - turn * 0.12)

        let body = CGMutablePath()
        body.move(to: p(neckX - left * 0.95, -0.05))
        // Up the arm to the widest point of the shoulder, over its round top...
        body.addCurve(to: p(neckX - left * 1.03, leftTop - h * 0.9), control1: p(neckX - left * 0.96, leftTop - h * 2.6), control2: p(neckX - left * 1.03, leftTop - h * 1.7))
        body.addCurve(to: p(neckX - left * 0.8, leftTop + h * 0.04), control1: p(neckX - left * 1.03, leftTop - h * 0.35), control2: p(neckX - left * 0.95, leftTop + h * 0.02))
        // ...then along the long slope of the trapezius into the neck.
        body.addCurve(to: p(neckX - neckHalf, neckBase + h * 0.05), control1: p(neckX - left * 0.6, leftTop + h * 0.1), control2: p(neckX - neckHalf - h * 0.45, neckBase - h * 0.08))
        body.addCurve(to: p(neckX - neckHalf * 0.92, neckTop), control1: p(neckX - neckHalf * 0.86, neckBase + h * 0.25), control2: p(neckX - neckHalf * 0.88, neckTop - h * 0.15))
        body.addLine(to: p(neckX + neckHalf * 0.92, neckTop))
        body.addCurve(to: p(neckX + neckHalf, neckBase + h * 0.05), control1: p(neckX + neckHalf * 0.88, neckTop - h * 0.15), control2: p(neckX + neckHalf * 0.86, neckBase + h * 0.25))
        body.addCurve(to: p(neckX + right * 0.8, rightTop + h * 0.04), control1: p(neckX + neckHalf + h * 0.45, neckBase - h * 0.08), control2: p(neckX + right * 0.6, rightTop + h * 0.1))
        body.addCurve(to: p(neckX + right * 1.03, rightTop - h * 0.9), control1: p(neckX + right * 0.95, rightTop + h * 0.02), control2: p(neckX + right * 1.03, rightTop - h * 0.35))
        body.addCurve(to: p(neckX + right * 0.95, -0.05), control1: p(neckX + right * 1.03, rightTop - h * 1.7), control2: p(neckX + right * 0.96, rightTop - h * 2.6))
        body.closeSubpath()

        // The head, with the hair's outline: a little ragged, never a clean oval.
        let roughness: Double
        let volume: Double
        switch hair {
        case .cropped: (roughness, volume) = (0.03, 1.04)
        case .long: (roughness, volume) = (0.035, 1.07)
        case .curls: (roughness, volume) = (0.1, 1.3)
        case .bun: (roughness, volume) = (0.02, 1.03)
        }
        let headPath = CGMutablePath()
        let steps = 120
        for step in 0...steps {
            let angle = (-0.5 + 2 * Double(step) / Double(steps)) * .pi
            let around = noise.fractal(cos(angle) * 3 + 10, sin(angle) * 3, octaves: 4) - 0.5
            let up = smoothstep(-0.3, 0.4, sin(angle))
            // The angle measured from the direction the face looks.
            let facing = turn > 0 ? angle : .pi - angle
            let face = profile * exp(-pow(remainder(facing, 2 * .pi), 2) / 0.35)
            var r = 1 + (volume - 1) * up * (1 - face) + around * roughness * (0.3 + up) * (1 - face)
            if profile > 0 {
                let a = remainder(facing, 2 * .pi)
                func bump(_ at: Double, _ height: Double, _ width: Double) -> Double {
                    height * exp(-pow(a - at, 2) / width)
                }
                // Brow, nose, the dip under it, lips, and chin; and the back
                // of the skull, fuller seen from the side.
                r += profile * (bump(0.34, 0.05, 0.012) + bump(0.04, 0.2, 0.006) - bump(-0.1, 0.03, 0.003)
                    + bump(-0.24, 0.06, 0.004) + bump(-0.5, 0.1, 0.012) + bump(.pi * 0.85, 0.08, 0.2))
            }
            // Curls break the outline into small tufts.
            if hair == .curls {
                r += (noise.fractal(cos(angle) * 9 + 40, sin(angle) * 9, octaves: 2) - 0.5) * 0.16 * up
            }
            // Ears, when the hair is short enough to show them.
            if hair == .cropped {
                r += 0.07 * exp(-pow(angle - 0.0, 2) / 0.02) + 0.07 * exp(-pow(angle - .pi, 2) / 0.02)
            }
            // The jaw shows on the side the face is turned to.
            let jaw = turn > 0 ? -0.3 * Double.pi : 1.3 * Double.pi
            r += abs(turn) * 0.12 * exp(-pow(angle - jaw, 2) / 0.05)
            // Narrower toward the chin.
            let lower = 1 - smoothstep(-1, -0.2, sin(angle))
            let px = cos(angle) * h * r * (1 - lower * 0.22)
            let py = sin(angle) * ry * r
            // Lean the head about the neck.
            let lx = px * cos(tilt) - (py + ry) * sin(tilt)
            let ly = px * sin(tilt) + (py + ry) * cos(tilt) - ry
            let point = p(x + lx, y + ly)
            if step == 0 { headPath.move(to: point) } else { headPath.addLine(to: point) }
        }
        headPath.closeSubpath()
        var paths: [CGPath] = [body, headPath]

        switch hair {
        case .long:
            // The hair hangs from the head, so it leans with it, and falls
            // behind the shoulder the face is turned from.
            func q(_ dx: Double, _ dy: Double) -> CGPoint {
                let lx = dx * cos(tilt) - (dy + ry) * sin(tilt)
                let ly = dx * sin(tilt) + (dy + ry) * cos(tilt) - ry
                return p(x + lx, y + ly)
            }
            let back = -turn * h * 0.35
            let drop = neckBase - y
            let fall = CGMutablePath()
            fall.move(to: q(-h * 1.0, ry * 0.1))
            fall.addCurve(to: q(back - h * 1.3, drop - h * 1.1), control1: q(-h * 1.12, -ry * 0.8), control2: q(back - h * 1.38, drop - h * 0.2))
            fall.addQuadCurve(to: q(back + h * 1.3, drop - h * 1.1), control: q(back, drop - h * 1.5))
            fall.addCurve(to: q(h * 1.0, ry * 0.1), control1: q(back + h * 1.38, drop - h * 0.2), control2: q(h * 1.12, -ry * 0.8))
            fall.closeSubpath()
            paths.append(fall)
        case .bun:
            let lean = -sin(tilt) * ry * 2
            paths.append(CGPath(ellipseIn: CGRect(origin: p(x + lean - h * 0.4, y + ry * 0.8), size: CGSize(width: h * 0.8 * canvas.size, height: h * 0.7 * canvas.size)), transform: nil))
        case .cropped, .curls:
            break
        }
        return paths
    }
}

extension ArtCanvas {
    /// A grayscale copy, for clipping: white paints, black masks.
    func maskImage() -> CGImage? {
        guard let image = makeImage(), let gray = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        gray.draw(image, in: bounds)
        return gray.makeImage()
    }

    /// Paints `figure` in `color` with light catching the edges that face `light`
    /// (a direction, in fractions of the side).
    func silhouette(_ figure: ArtFigure, color: ArtColor, rim: [(ArtColor, Double)], light: (Double, Double), focus: Double) {
        guard let body = figure.mask(side: side, focus: focus)?.maskImage() else { return }
        fill(color, through: body)
        // A little of the light reaches the near side of the figure too.
        if let wash = ArtCanvas(side: side) {
            wash.linearGradient(rim, from: (0.5, 0), to: (0.5, 1))
            context.saveGState()
            context.clip(to: bounds, mask: body)
            draw(wash.makeImage(), blend: .screen, alpha: 0.06)
            // Fill light falling off across the figure from the lit side, and
            // the folds of clothing catching a little of it.
            glow(rim.last?.0 ?? .white, at: (figure.x + light.0 * 30, figure.y + light.1 * 30), radius: figure.shoulders * 1.4, alpha: 0.05)
            let noise = ValueNoise(seed: figure.seed ^ 0xF01D)
            let folds = ArtField.gray(width: 64, height: 64) { u, v in
                noise.fractal(u * 4 + v * 1.5, v * 2.5, octaves: 3)
            }
            draw(folds, blend: .softLight, alpha: 0.28)
            context.restoreGState()
        }
        // The rim: the figure minus a copy nudged away from the light.
        guard let edge = figure.mask(side: side, focus: focus * 0.5 + 0.001, cutout: (-light.0, -light.1)) else { return }
        guard let rimMask = edge.maskImage(), let lit = ArtCanvas(side: side) else { return }
        lit.linearGradient(rim, from: (0.5, 0), to: (0.5, 1))
        context.saveGState()
        context.clip(to: bounds, mask: rimMask)
        draw(lit.makeImage(), blend: .screen)
        context.restoreGState()
    }
}

/// A dark room at night, a person at the window, and the neon of the street
/// outside spilling over their shoulders.
struct WindowLight {
    var room: ArtColor
    /// The colors outside, each with where it glows.
    var neon: [(color: ArtColor, x: Double, y: Double, radius: Double)]
    var outside: [(ArtColor, Double)]
    var window = CGRect(x: 0.34, y: 0.16, width: 0.74, height: 0.92)
    var figure: ArtFigure
    var seed: UInt64

    func paint(_ canvas: ArtCanvas) {
        var random = ArtRandom(seed: seed)
        let noise = ValueNoise(seed: seed)
        canvas.fill(room)
        let pane = canvas.rect(window.minX, window.minY, window.width, window.height)

        // Outside: the street's glow, far out of focus.
        canvas.context.saveGState()
        canvas.context.clip(to: pane)
        canvas.linearGradient(outside, from: (0.5, window.minY), to: (0.5, window.maxY))
        canvas.layer(.screen) {
            for light in neon {
                canvas.glow(light.color, at: (light.x, light.y), radius: light.radius, alpha: 0.75)
            }
        }
        for _ in 0..<26 {
            let light = random.pick(neon)
            canvas.bokeh(
                at: (random.range(window.minX...window.maxX), random.range(window.minY...window.maxY)),
                radius: random.range(0.01...0.04),
                color: light.color.mixed(with: .white, random.range(0...0.4)),
                alpha: random.range(0.15...0.5),
                noise: noise
            )
        }
        canvas.context.restoreGState()
        canvas.blur(0.012)

        // The window frame, nearer and sharper.
        let bar = 0.016
        canvas.context.setFillColor(room.cgColor())
        let columns = [window.minX + window.width * 0.5]
        let rows = [window.minY + window.height * 0.36, window.minY + window.height * 0.72]
        canvas.solid { context in
            for column in columns {
                context.fill(canvas.rect(column - bar / 2, window.minY, bar, window.height))
            }
            for row in rows {
                context.fill(canvas.rect(window.minX, row - bar / 2, window.width, bar))
            }
            context.fill(canvas.rect(window.minX - 0.04, window.minY - 0.05, window.width + 0.08, 0.05))
        }
        canvas.blur(0.003)

        // The glow spilling into the room.
        canvas.layer(.screen) {
            let first = neon[0]
            canvas.glow(first.color, at: (window.minX, window.midY), radius: 0.5, alpha: 0.18)
            canvas.glow(first.color.mixed(with: room, 0.5), at: (window.midX, window.minY), radius: 0.45, alpha: 0.2)
        }

        let rim = neon.sorted { $0.y < $1.y }.map { light in (light.color.mixed(with: .white, 0.15), light.y) }
        canvas.silhouette(figure, color: room.scaled(0.55), rim: rim, light: (0.007, 0.003), focus: 0.005)

        // Haze hanging in the light.
        let haze = ArtField.gray(width: 96, height: 96) { u, v in
            let n = noise.fractal(u * 3 + 5, v * 2.4, octaves: 4)
            return smoothstep(0.4, 0.8, n) * smoothstep(window.minX - 0.2, window.minX + 0.3, u)
        }
        canvas.fill(neon[0].color.mixed(with: .white, 0.3), through: haze, blend: .screen, alpha: 0.12)
    }
}
