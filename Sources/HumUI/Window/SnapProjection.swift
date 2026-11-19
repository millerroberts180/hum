import CoreGraphics
import HumCore

/// Where a thrown window lands: the release velocity projects a resting point,
/// and the snap target nearest that point wins.
nonisolated enum SnapProjection {
    /// The same deceleration as scrolling, so a throw travels as far as a flick.
    static let decelerationRate = 0.998

    /// How far something moving at `velocity` (points per second) travels before
    /// friction stops it.
    static func distance(velocity: Double, decelerationRate: Double = decelerationRate) -> Double {
        PagingPhysics.projectedDistance(velocity: velocity, decelerationRate: decelerationRate)
    }

    static func project(_ point: CGPoint, velocity: CGVector) -> CGPoint {
        CGPoint(
            x: point.x + distance(velocity: velocity.dx),
            y: point.y + distance(velocity: velocity.dy)
        )
    }

    /// Where a throw comes to rest: the pin and the window's origin there.
    struct Snap: Equatable {
        var pin: PinPosition
        var origin: CGPoint
        /// The usable area of the display it lands on.
        var visibleFrame: CGRect
    }

    /// The window origins it can snap to on one display: the nine pin
    /// positions, in `PinPosition` order (DESIGN.md §4.5). `among` limits
    /// them, as Under Menu Bar does to the top row.
    static func targets(
        size: CGSize,
        visibleFrame visible: CGRect,
        among pins: [PinPosition] = PinPosition.allCases
    ) -> [(pin: PinPosition, origin: CGPoint)] {
        pins.map { pin in
            (pin, PlacementResolver.frame(for: pin, size: size, in: visible).origin)
        }
    }

    /// Where a window released at `origin`, moving at `velocity`, settles. The
    /// display is the one containing the projected center, or the nearest one
    /// when it lands off every display; the pin is the one nearest the
    /// projected point there.
    static func target(
        origin: CGPoint,
        size: CGSize,
        velocity: CGVector,
        visibleFrames: [CGRect],
        among pins: [PinPosition] = PinPosition.allCases
    ) -> Snap? {
        guard !visibleFrames.isEmpty, !pins.isEmpty else { return nil }
        let projected = project(origin, velocity: velocity)
        let center = CGPoint(x: projected.x + size.width / 2, y: projected.y + size.height / 2)
        let display = visibleFrames.first { $0.contains(center) }
            ?? visibleFrames.min { distanceSquared(center, to: $0) < distanceSquared(center, to: $1) }!
        let candidates = targets(size: size, visibleFrame: display, among: pins)
        guard let nearest = candidates.min(by: { distanceSquared($0.origin, projected) < distanceSquared($1.origin, projected) }) else {
            return nil
        }
        return Snap(pin: nearest.pin, origin: nearest.origin, visibleFrame: display)
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    private static func distanceSquared(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        return distanceSquared(point, CGPoint(x: x, y: y))
    }

    /// A window origin pulled back toward `bounds` with rubber-band resistance
    /// wherever it pokes outside.
    static func rubberBanded(origin: CGPoint, size: CGSize, bounds: CGRect, constant: Double = 0.55) -> CGPoint {
        func band(_ value: CGFloat, lower: CGFloat, upper: CGFloat, dimension: CGFloat) -> CGFloat {
            guard upper >= lower else { return value }
            if value < lower {
                return lower - CGFloat(PagingPhysics.rubberBand(Double(lower - value), dimension: Double(dimension), constant: constant))
            }
            if value > upper {
                return upper + CGFloat(PagingPhysics.rubberBand(Double(value - upper), dimension: Double(dimension), constant: constant))
            }
            return value
        }
        return CGPoint(
            x: band(origin.x, lower: bounds.minX, upper: bounds.maxX - size.width, dimension: size.width),
            y: band(origin.y, lower: bounds.minY, upper: bounds.maxY - size.height, dimension: size.height)
        )
    }
}
