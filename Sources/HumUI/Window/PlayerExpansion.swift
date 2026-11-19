import CoreGraphics
import Foundation
import HumCore

/// The player grown to a square for a while, and how to put it back.
///
/// Title, Text, Strip and Wide are too short for History and Status, so showing either
/// grows the window to the `StyleGeometry.surfaceSide` square, and going back
/// to Now returns it to its shape (DESIGN.md §7.2). The session also ends when
/// the player hides. A pinned player holds its pinned point both ways; an
/// unpinned one holds the corner it grew from.
nonisolated struct PlayerExpansion: Equatable, Sendable {
    /// The size to come back to.
    var restoreSize: CGSize
    /// The part of an unpinned window held still while it grew (unit
    /// coordinates, y up), so it shrinks back into the same place.
    var anchor: CGPoint

    static let expandedSize = CGSize(width: StyleGeometry.surfaceSide, height: StyleGeometry.surfaceSide)

    /// The size to come back to for a window at `frame`, or on its way to
    /// `heading`. Grown again while it still shrinks back from the last
    /// expansion, the player returns to the size from before that one, not to
    /// wherever the shrink was caught.
    static func restoreSize(frame: CGRect, heading: CGRect?) -> CGSize {
        heading?.size ?? frame.size
    }

    /// Whether the session carries on now that `surface` is showing.
    func holds(on surface: Surface) -> Bool {
        surface != .now
    }

    /// Whether showing `surface` in `style` grows the player.
    static func isNeeded(for surface: Surface, style: PlayerStyleID) -> Bool {
        StyleGeometry.needsExpansion(for: surface, style: style)
    }

    /// The grown frame, from `frame` on a display whose usable area is `visible`.
    func expandedFrame(from frame: CGRect, pin: PinPosition?, in visible: CGRect) -> CGRect {
        resized(frame, to: Self.expandedSize, pin: pin, in: visible)
    }

    /// The frame to return to from wherever the grown window is now. If it was
    /// moved while grown, it comes back where it was moved to.
    func restoredFrame(from frame: CGRect, pin: PinPosition?, in visible: CGRect) -> CGRect {
        resized(frame, to: restoreSize, pin: pin, in: visible)
    }

    private func resized(_ frame: CGRect, to size: CGSize, pin: PinPosition?, in visible: CGRect) -> CGRect {
        if let pin {
            return PlacementResolver.frame(for: pin, size: size, in: visible)
        }
        return PlacementResolver.frame(resizing: frame, to: size, anchor: anchor, in: visible)
    }
}

/// Turns a two-finger horizontal swipe on the Now artwork into one skip, when
/// "Swipe to skip" is on (DESIGN.md §4.2).
///
/// The axis locks after 12 pt of travel. A horizontal swipe then belongs to the
/// tracker, which swallows the rest of the gesture and its momentum. Nothing
/// skips mid-drag: on release, the swipe skips once if it would come to rest
/// `commitDistance` or more from where it started, projected from the
/// fingers' velocity as a page is (`PagingPhysics`). A flick goes the way it's
/// moving, so a flick back toward the start never skips, however far the drag
/// went. Fingers moving left bring the next track in from the trailing edge;
/// moving right goes back. A vertical swipe is left alone.
nonisolated struct SwipeSkipTracker: Equatable, Sendable {
    enum Skip: Equatable, Sendable {
        case next
        case previous
    }

    struct Outcome: Equatable, Sendable {
        /// Nothing else should see the event.
        var consumed: Bool
        var skip: Skip?
        /// The tracker just took the gesture, so whatever was following it
        /// (the pager) should let it go.
        var claimed: Bool
    }

    static let axisLock = 12.0
    static let commitDistance = 48.0

    private enum Axis: Equatable, Sendable {
        case undecided, horizontal, vertical
    }

    /// The horizontal travel so far at a moment, for the release velocity.
    private struct Travel: Equatable, Sendable {
        var time: TimeInterval
        var x: Double
    }

    private var axis: Axis = .undecided
    private var travelX = 0.0
    private var travelY = 0.0
    private var history: [Travel] = []
    private var swallowsMomentum = false

    mutating func handle(_ sample: ScrollSample) -> Outcome {
        let pass = Outcome(consumed: false, skip: nil, claimed: false)
        if sample.isMomentum {
            return Outcome(consumed: swallowsMomentum, skip: nil, claimed: false)
        }
        guard sample.isPrecise else { return pass }
        switch sample.phase {
        case .none, .mayBegin:
            return pass
        case .began:
            self = SwipeSkipTracker()
            return track(sample)
        case .changed:
            return track(sample)
        case .ended, .cancelled:
            let wasHorizontal = axis == .horizontal
            var skip: Skip?
            if wasHorizontal, sample.phase == .ended {
                travelX += sample.fingerDeltaX
                let velocity = PagingPhysics.releaseVelocity(history.map { ($0.time, $0.x) }, at: sample.timestamp)
                skip = Self.skip(travel: travelX, velocity: velocity)
            }
            swallowsMomentum = wasHorizontal
            axis = .undecided
            travelX = 0
            travelY = 0
            history.removeAll()
            return Outcome(consumed: wasHorizontal, skip: skip, claimed: false)
        }
    }

    /// The skip for a swipe released after `travel` points, moving at
    /// `velocity` points per second; positive is rightward.
    static func skip(travel: Double, velocity: Double) -> Skip? {
        if abs(velocity) >= PagingPhysics.flickSpeed, (velocity < 0) != (travel < 0) { return nil }
        let projected = travel + PagingPhysics.projectedDistance(velocity: velocity)
        guard abs(projected) >= commitDistance else { return nil }
        return projected < 0 ? .next : .previous
    }

    private mutating func track(_ sample: ScrollSample) -> Outcome {
        travelX += sample.fingerDeltaX
        travelY += sample.deltaY
        history.append(Travel(time: sample.timestamp, x: travelX))
        history.removeAll { sample.timestamp - $0.time > PagingPhysics.velocityWindow * 2 }
        var claimed = false
        if axis == .undecided, max(abs(travelX), abs(travelY)) >= Self.axisLock {
            axis = abs(travelX) > abs(travelY) ? .horizontal : .vertical
            claimed = axis == .horizontal
        }
        guard axis == .horizontal else {
            return Outcome(consumed: false, skip: nil, claimed: false)
        }
        return Outcome(consumed: true, skip: nil, claimed: claimed)
    }
}

extension PlayerSize {
    init(_ size: CGSize) {
        self.init(width: Double(size.width), height: Double(size.height))
    }
}

extension CGSize {
    init(_ size: PlayerSize) {
        self.init(width: CGFloat(size.width), height: CGFloat(size.height))
    }
}
