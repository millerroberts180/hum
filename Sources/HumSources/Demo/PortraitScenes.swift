import CoreGraphics
import Foundation

/// An artist photographed against a backdrop, as a press photo would be: a
/// dark figure with light catching the hair and shoulders, the face always in
/// shadow. The figure sits in the middle so a round crop keeps it.
struct StudioPortrait {
    enum Light: CaseIterable {
        /// A lamp behind the sitter, haloing the head.
        case backlit
        /// A stage spot overhead, cutting through haze.
        case spot
        /// Daylight from a window to one side.
        case window
    }

    var backdrop: ArtColor
    /// The color of the light itself.
    var lamp: ArtColor
    var light: Light
    var figure: ArtFigure
    var seed: UInt64

    func paint(_ canvas: ArtCanvas) {
        switch light {
        case .backlit: paintBacklit(canvas)
        case .spot: paintSpot(canvas)
        case .window: paintWindow(canvas)
        }
    }

    private func paintBacklit(_ canvas: ArtCanvas) {
        // A seamless paper backdrop, falling off toward the floor.
        canvas.linearGradient([(backdrop.scaled(0.45), 0), (backdrop, 0.6), (backdrop.scaled(0.8), 1)], from: (0.5, 0), to: (0.5, 1))
        canvas.layer(.screen) {
            canvas.glow(lamp, at: (figure.x, figure.y + figure.head * 0.4), radius: 0.55, alpha: 0.85)
            canvas.glow(lamp.mixed(with: .white, 0.5), at: (figure.x, figure.y + figure.head * 0.6), radius: 0.2, alpha: 0.6)
        }
        mottle(canvas, alpha: 0.12)
        canvas.silhouette(
            figure,
            color: backdrop.scaled(0.16),
            rim: [(lamp.scaled(0.4), 0), (lamp.mixed(with: .white, 0.4), 0.9)],
            light: (0, 0.007),
            focus: 0.006
        )
    }

    private func paintSpot(_ canvas: ArtCanvas) {
        canvas.fill(backdrop.scaled(0.12))
        // The beam: a cone of light coming down through stage haze.
        guard let beam = ArtCanvas(side: canvas.side) else { return }
        beam.fill(.black)
        beam.context.setFillColor(ArtColor.white.cgColor())
        let cone = CGMutablePath()
        cone.move(to: beam.point(figure.x - 0.08, 1.05))
        cone.addLine(to: beam.point(figure.x + 0.08, 1.05))
        cone.addLine(to: beam.point(figure.x + 0.42, -0.05))
        cone.addLine(to: beam.point(figure.x - 0.42, -0.05))
        cone.closeSubpath()
        beam.context.addPath(cone)
        beam.solid { $0.fillPath() }
        beam.blur(0.05)
        let noise = ValueNoise(seed: seed)
        let haze = ArtField.gray(width: 96, height: 96) { u, v in
            0.35 + noise.fractal(u * 3 + 5, v * 2.4, octaves: 4) * 0.65 * (0.4 + v * 0.6)
        }
        canvas.context.saveGState()
        if let mask = beam.maskImage() { canvas.context.clip(to: canvas.bounds, mask: mask) }
        canvas.fill(lamp, through: haze, blend: .screen, alpha: 0.55)
        canvas.context.restoreGState()
        canvas.glow(lamp.mixed(with: .white, 0.3), at: (figure.x, 1.02), radius: 0.22, alpha: 0.7)
        // A little light bouncing off the floor behind.
        canvas.glow(backdrop, at: (figure.x, 0), radius: 0.6, alpha: 0.35)
        canvas.silhouette(
            figure,
            color: backdrop.scaled(0.1),
            rim: [(lamp.scaled(0.3), 0), (lamp.mixed(with: .white, 0.5), 1)],
            light: (0.001, 0.008),
            focus: 0.005
        )
    }

    private func paintWindow(_ canvas: ArtCanvas) {
        let fromLeft = figure.turn < 0
        let bright: (Double, Double) = fromLeft ? (0, 0.6) : (1, 0.6)
        let dim: (Double, Double) = fromLeft ? (1, 0.4) : (0, 0.4)
        // A plain wall, lit across from the window.
        canvas.linearGradient([(backdrop.mixed(with: lamp, 0.35), 0), (backdrop, 0.45), (backdrop.scaled(0.45), 1)], from: bright, to: dim)
        canvas.layer(.screen) {
            canvas.glow(lamp, at: (bright.0, 0.7), radius: 0.7, alpha: 0.5)
        }
        // The shadow of the window bars on the wall.
        canvas.layer(.multiply, alpha: 0.35) {
            canvas.context.setFillColor(backdrop.scaled(0.4).cgColor())
            let x = fromLeft ? 0.62 : 0.3
            canvas.solid { context in
                context.fill(canvas.rect(x, 0, 0.035, 1))
                context.fill(canvas.rect(fromLeft ? x : x - 0.3, 0.66, 0.34, 0.03))
            }
        }
        canvas.blur(0.012)
        mottle(canvas, alpha: 0.1)
        let lean = fromLeft ? -0.008 : 0.008
        canvas.silhouette(
            figure,
            color: backdrop.scaled(0.22),
            rim: [(lamp.scaled(0.55), 0), (lamp.mixed(with: .white, 0.35), 1)],
            light: (lean, 0.003),
            focus: 0.005
        )
    }

    private func mottle(_ canvas: ArtCanvas, alpha: Double) {
        let noise = ValueNoise(seed: seed ^ 0x6D6F)
        let field = ArtField.gray(width: 48, height: 48) { u, v in
            noise.fractal(u * 2.5, v * 2.5, octaves: 4)
        }
        canvas.draw(field, blend: .softLight, alpha: alpha * 3)
    }
}
