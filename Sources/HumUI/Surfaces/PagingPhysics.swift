import Foundation

/// The pure math behind surface paging, kept apart from event handling so it can be
/// tested directly.
nonisolated enum PagingPhysics {
    /// How firmly the edges resist. Lower is stiffer.
    static let rubberBandConstant = 0.55
    /// Deceleration used to project where a flick would come to rest.
    static let decelerationRate = 0.998
    /// Points per second. A release at least this fast is a flick, and goes
    /// the way it's moving.
    static let flickSpeed = 100.0
    /// A release's velocity is measured over this much recent movement.
    static let velocityWindow: TimeInterval = 0.08

    /// The visible offset for a drag that has gone `overshoot` points past an edge.
    /// Resistance grows the further the drag goes, so the edge feels soft but final.
    static func rubberBand(_ overshoot: Double, dimension: Double, constant: Double = rubberBandConstant) -> Double {
        guard dimension > 0 else { return 0 }
        let magnitude = abs(overshoot)
        let banded = (magnitude * dimension * constant) / (dimension + constant * magnitude)
        return overshoot < 0 ? -banded : banded
    }

    /// The inverse of `rubberBand`: the drag that produces a visible offset. Used to
    /// pick up a page that's still sitting past the edge.
    static func unrubberBand(_ offset: Double, dimension: Double, constant: Double = rubberBandConstant) -> Double {
        guard dimension > 0, constant > 0 else { return 0 }
        let magnitude = min(abs(offset), dimension * 0.999)
        let raw = (magnitude * dimension) / (constant * (dimension - magnitude))
        return offset < 0 ? -raw : raw
    }

    /// How far a flick at `velocity` (points per second) would carry before stopping.
    static func projectedDistance(velocity: Double, decelerationRate: Double = decelerationRate) -> Double {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// Units per second over the samples within `velocityWindow` of the last
    /// one. If the fingers paused before lifting at `time`, there's no velocity
    /// left.
    static func releaseVelocity(_ history: [(time: TimeInterval, value: Double)], at time: TimeInterval) -> Double {
        guard let last = history.last, time - last.time < velocityWindow else { return 0 }
        let recent = history.filter { last.time - $0.time <= velocityWindow }
        guard let first = recent.first, last.time - first.time > 0.001 else { return 0 }
        return (last.value - first.value) / (last.time - first.time)
    }

    /// Apply edge resistance to a fractional page position.
    static func bandedPosition(_ raw: Double, pageCount: Int, pageWidth: Double) -> Double {
        let upper = Double(max(pageCount - 1, 0))
        if raw < 0 {
            return rubberBand(raw * pageWidth, dimension: pageWidth) / pageWidth
        } else if raw > upper {
            return upper + rubberBand((raw - upper) * pageWidth, dimension: pageWidth) / pageWidth
        }
        return raw
    }

    /// Undo `bandedPosition`.
    static func rawPosition(fromBanded banded: Double, pageCount: Int, pageWidth: Double) -> Double {
        let upper = Double(max(pageCount - 1, 0))
        if banded < 0 {
            return unrubberBand(banded * pageWidth, dimension: pageWidth) / pageWidth
        } else if banded > upper {
            return upper + unrubberBand((banded - upper) * pageWidth, dimension: pageWidth) / pageWidth
        }
        return banded
    }

    /// The page a released swipe should settle on (DESIGN.md §4.2).
    ///
    /// A flick goes to the next page the way it's moving, however far the drag
    /// went, so a short quick flick turns the page and a flick back returns
    /// even past halfway. A slower release projects a resting point and takes
    /// the page nearest it. A single swipe moves at most one page from where
    /// it started. `velocity` is in pages per second.
    static func targetPage(
        position: Double,
        velocity: Double,
        startPage: Int,
        pageCount: Int,
        pageWidth: Double
    ) -> Int {
        guard pageCount > 0, pageWidth > 0 else { return 0 }
        let target: Int
        if abs(velocity * pageWidth) >= flickSpeed {
            target = velocity > 0 ? Int(position.rounded(.down)) + 1 : Int(position.rounded(.up)) - 1
        } else {
            let projected = position + projectedDistance(velocity: velocity * pageWidth) / pageWidth
            target = Int(projected.rounded())
        }
        let lower = max(0, startPage - 1)
        let upper = min(pageCount - 1, startPage + 1)
        return min(upper, max(lower, target))
    }
}
