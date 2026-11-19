import Foundation

/// A vertical two-finger swipe over Now's cover setting the volume (DESIGN.md
/// §4.2). The level follows the fingers 1:1 from where it was when the swipe
/// started: up is louder, and `span` points cover the whole range. A swipe that
/// starts anywhere else, or locks horizontally, is left alone.
nonisolated struct SwipeVolumeTracker: Equatable, Sendable {
    struct Outcome: Equatable, Sendable {
        /// Nothing else should see the event.
        var consumed: Bool
        /// The volume to set, when the swipe moved it.
        var level: Double?
    }

    static let axisLock = SwipeSkipTracker.axisLock
    /// Points of finger travel from silent to full.
    static let span = 300.0

    private enum Axis: Equatable, Sendable {
        case undecided, vertical, other
    }

    /// Nil between gestures.
    private var axis: Axis?
    private var travelX = 0.0
    private var travelY = 0.0
    private var startLevel = 0.0
    private var swallowsMomentum = false

    /// `isOverArtwork` and `volume` are read only as a swipe starts.
    mutating func handle(_ sample: ScrollSample, isOverArtwork: Bool, volume: Double) -> Outcome {
        let pass = Outcome(consumed: false, level: nil)
        if sample.isMomentum {
            return Outcome(consumed: swallowsMomentum, level: nil)
        }
        guard sample.isPrecise else { return pass }
        switch sample.phase {
        case .none, .mayBegin:
            return pass
        case .began:
            begin(isOverArtwork: isOverArtwork, volume: volume)
            return track(sample)
        case .changed:
            if axis == nil { begin(isOverArtwork: isOverArtwork, volume: volume) }
            return track(sample)
        case .ended, .cancelled:
            let wasVertical = axis == .vertical
            swallowsMomentum = wasVertical
            axis = nil
            return Outcome(consumed: wasVertical, level: nil)
        }
    }

    private mutating func begin(isOverArtwork: Bool, volume: Double) {
        axis = isOverArtwork ? .undecided : .other
        travelX = 0
        travelY = 0
        startLevel = min(1, max(0, volume))
        swallowsMomentum = false
    }

    private mutating func track(_ sample: ScrollSample) -> Outcome {
        guard axis != .other else { return Outcome(consumed: false, level: nil) }
        travelX += sample.fingerDeltaX
        travelY += sample.fingerDeltaY
        if axis == .undecided, max(abs(travelX), abs(travelY)) >= Self.axisLock {
            axis = abs(travelY) > abs(travelX) ? .vertical : .other
        }
        guard axis == .vertical else { return Outcome(consumed: false, level: nil) }
        return Outcome(consumed: true, level: min(1, max(0, startLevel + travelY / Self.span)))
    }
}
