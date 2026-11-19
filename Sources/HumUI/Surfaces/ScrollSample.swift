import AppKit

/// The parts of a scroll-wheel event that paging cares about.
///
/// A plain value so the pager can be driven by tests without synthesizing `NSEvent`s.
nonisolated struct ScrollSample: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// A legacy wheel event without gesture phases (a clicky mouse wheel).
        case none
        /// Fingers touched the trackpad but haven't moved yet.
        case mayBegin
        case began
        case changed
        case ended
        case cancelled
    }

    var phase: Phase
    /// Inertial scrolling after the fingers lifted.
    var isMomentum: Bool
    /// Horizontal finger movement in points; positive is rightward, whatever the
    /// user's scroll-direction setting. Pages follow the fingers.
    var fingerDeltaX: Double
    var deltaY: Double
    /// Vertical finger movement in points; positive is upward, whatever the
    /// user's scroll-direction setting.
    var fingerDeltaY: Double = 0
    /// Trackpad or other high-resolution device.
    var isPrecise: Bool
    /// Seconds, on the system uptime clock.
    var timestamp: TimeInterval
}

extension ScrollSample {
    init(_ event: NSEvent) {
        let momentum = event.momentumPhase
        let isMomentum = !momentum.isEmpty
        let eventPhase = isMomentum ? momentum : event.phase
        let phase: Phase = if eventPhase.contains(.mayBegin) {
            .mayBegin
        } else if eventPhase.contains(.began) {
            .began
        } else if eventPhase.contains(.changed) || eventPhase.contains(.stationary) {
            .changed
        } else if eventPhase.contains(.ended) {
            .ended
        } else if eventPhase.contains(.cancelled) {
            .cancelled
        } else {
            .none
        }
        self.init(
            phase: phase,
            isMomentum: isMomentum,
            scrollingDeltaX: Double(event.scrollingDeltaX),
            scrollingDeltaY: Double(event.scrollingDeltaY),
            isDirectionInverted: event.isDirectionInvertedFromDevice,
            isPrecise: event.hasPreciseScrollingDeltas,
            timestamp: event.timestamp
        )
    }

    /// A sample from the deltas a scroll event reports, which move the content,
    /// and whether the user's setting inverted them from the device.
    init(
        phase: Phase,
        isMomentum: Bool,
        scrollingDeltaX: Double,
        scrollingDeltaY: Double,
        isDirectionInverted: Bool,
        isPrecise: Bool,
        timestamp: TimeInterval
    ) {
        // With "natural" scrolling, deltas already follow the fingers; otherwise
        // they point the other way.
        self.init(
            phase: phase,
            isMomentum: isMomentum,
            fingerDeltaX: isDirectionInverted ? scrollingDeltaX : -scrollingDeltaX,
            deltaY: scrollingDeltaY,
            fingerDeltaY: isDirectionInverted ? -scrollingDeltaY : scrollingDeltaY,
            isPrecise: isPrecise,
            timestamp: timestamp
        )
    }
}
