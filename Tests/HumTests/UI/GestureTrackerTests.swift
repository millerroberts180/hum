import AppKit
import HumCore
@testable import HumUI
import Testing

private func swipe(
    _ phase: ScrollSample.Phase,
    x: Double = 0,
    y: Double = 0,
    momentum: Bool = false,
    precise: Bool = true
) -> ScrollSample {
    ScrollSample(
        phase: phase,
        isMomentum: momentum,
        fingerDeltaX: x,
        deltaY: -y,
        fingerDeltaY: y,
        isPrecise: precise,
        timestamp: 0
    )
}

@Suite("Swipe volume")
struct SwipeVolumeTrackerTests {
    @Test func fingersMovingUpOverTheCoverRaiseTheVolumeOneToOne() {
        var tracker = SwipeVolumeTracker()
        #expect(tracker.handle(swipe(.began), isOverArtwork: true, volume: 0.5) == .init(consumed: false, level: nil))
        // Short of the axis lock, nothing happens yet.
        #expect(tracker.handle(swipe(.changed, y: 6), isOverArtwork: true, volume: 0.5) == .init(consumed: false, level: nil))
        let locked = tracker.handle(swipe(.changed, y: 6), isOverArtwork: true, volume: 0.5)
        #expect(locked.consumed)
        #expect(abs((locked.level ?? 0) - (0.5 + 12 / SwipeVolumeTracker.span)) < 1e-9)
        let lower = tracker.handle(swipe(.changed, y: -42), isOverArtwork: true, volume: 0.9)
        // Measured from where the swipe started, not from the latest volume.
        #expect(abs((lower.level ?? 0) - (0.5 - 30 / SwipeVolumeTracker.span)) < 1e-9)
        #expect(tracker.handle(swipe(.ended), isOverArtwork: true, volume: 0.4) == .init(consumed: true, level: nil))
    }

    @Test func theLevelStaysBetweenSilentAndFull() {
        var tracker = SwipeVolumeTracker()
        _ = tracker.handle(swipe(.began), isOverArtwork: true, volume: 0.9)
        #expect(tracker.handle(swipe(.changed, y: 400), isOverArtwork: true, volume: 0.9).level == 1)
        _ = tracker.handle(swipe(.ended), isOverArtwork: true, volume: 1)
        _ = tracker.handle(swipe(.began), isOverArtwork: true, volume: 0.1)
        #expect(tracker.handle(swipe(.changed, y: -400), isOverArtwork: true, volume: 0.1).level == 0)
    }

    @Test func aSwipeThatStartsOffTheCoverIsLeftAlone() {
        var tracker = SwipeVolumeTracker()
        _ = tracker.handle(swipe(.began), isOverArtwork: false, volume: 0.5)
        // Moving onto the cover mid-swipe doesn't take it over.
        #expect(tracker.handle(swipe(.changed, y: 40), isOverArtwork: true, volume: 0.5) == .init(consumed: false, level: nil))
        #expect(tracker.handle(swipe(.ended), isOverArtwork: true, volume: 0.5) == .init(consumed: false, level: nil))
    }

    @Test func aMostlySidewaysSwipeIsForPagingOrSkipping() {
        var tracker = SwipeVolumeTracker()
        _ = tracker.handle(swipe(.began), isOverArtwork: true, volume: 0.5)
        #expect(!tracker.handle(swipe(.changed, x: 14, y: 10), isOverArtwork: true, volume: 0.5).consumed)
        #expect(!tracker.handle(swipe(.changed, y: 60), isOverArtwork: true, volume: 0.5).consumed)
    }

    @Test func momentumAfterAVolumeSwipeIsSwallowed() {
        var tracker = SwipeVolumeTracker()
        _ = tracker.handle(swipe(.began), isOverArtwork: true, volume: 0.5)
        _ = tracker.handle(swipe(.changed, y: 20), isOverArtwork: true, volume: 0.5)
        _ = tracker.handle(swipe(.ended), isOverArtwork: true, volume: 0.5)
        #expect(tracker.handle(swipe(.changed, y: 8, momentum: true), isOverArtwork: true, volume: 0.5) == .init(consumed: true, level: nil))

        _ = tracker.handle(swipe(.began), isOverArtwork: false, volume: 0.5)
        _ = tracker.handle(swipe(.ended), isOverArtwork: false, volume: 0.5)
        #expect(!tracker.handle(swipe(.changed, y: 8, momentum: true), isOverArtwork: true, volume: 0.5).consumed)
    }

    @Test func aClickyMouseWheelNeverSetsTheVolume() {
        var tracker = SwipeVolumeTracker()
        #expect(!tracker.handle(swipe(.none, y: 40, precise: false), isOverArtwork: true, volume: 0.5).consumed)
    }
}

@Suite("Pinch to resize")
struct PinchResizeTrackerTests {
    @Test func spreadingTheFingersGrowsOneStepPerThreshold() {
        var tracker = PinchResizeTracker()
        #expect(tracker.handle(.began, magnification: 0) == nil)
        #expect(tracker.handle(.changed, magnification: 0.1) == nil)
        #expect(tracker.handle(.changed, magnification: 0.1) == .grow)
        // The next step needs a full threshold of its own.
        #expect(tracker.handle(.changed, magnification: 0.1) == nil)
        #expect(tracker.handle(.changed, magnification: 0.1) == .grow)
        #expect(tracker.handle(.ended, magnification: 0) == nil)
    }

    @Test func pinchingInShrinks() {
        var tracker = PinchResizeTracker()
        _ = tracker.handle(.began, magnification: 0)
        #expect(tracker.handle(.changed, magnification: -0.2) == .shrink)
    }

    @Test func eachPinchStartsFromZero() {
        var tracker = PinchResizeTracker()
        _ = tracker.handle(.began, magnification: 0)
        _ = tracker.handle(.changed, magnification: 0.1)
        _ = tracker.handle(.ended, magnification: 0)
        _ = tracker.handle(.began, magnification: 0)
        #expect(tracker.handle(.changed, magnification: 0.1) == nil)
    }

    @Test func eventPhasesMapOntoThePinch() {
        #expect(PinchResizeTracker.Phase(.began) == .began)
        #expect(PinchResizeTracker.Phase(.changed) == .changed)
        #expect(PinchResizeTracker.Phase(.ended) == .ended)
        #expect(PinchResizeTracker.Phase(.cancelled) == .ended)
        #expect(PinchResizeTracker.Phase(.mayBegin) == nil)
        #expect(PinchResizeTracker.Phase([]) == nil)
    }

    @Test func stepsStopAtTheSmallestAndLargestSizes() {
        #expect(PlayerSizePreset.small.stepped(.grow) == .medium)
        #expect(PlayerSizePreset.medium.stepped(.grow) == .large)
        #expect(PlayerSizePreset.large.stepped(.grow) == nil)
        #expect(PlayerSizePreset.large.stepped(.shrink) == .medium)
        #expect(PlayerSizePreset.small.stepped(.shrink) == nil)
    }
}

/// Fingers moving on the trackpad as AppKit reports them: the scrolling deltas
/// move the content (positive is right and down), and the content follows the
/// fingers only with natural scrolling, which the event marks as inverted from
/// the device.
private func fingers(
    _ phase: ScrollSample.Phase,
    right: Double = 0,
    up: Double = 0,
    natural: Bool,
    at time: TimeInterval = 0
) -> ScrollSample {
    let content = natural ? 1.0 : -1.0
    return ScrollSample(
        phase: phase,
        isMomentum: false,
        scrollingDeltaX: content * right,
        scrollingDeltaY: -content * up,
        isDirectionInverted: natural,
        isPrecise: true,
        timestamp: time
    )
}

/// The same movement of the fingers does the same thing whichever way the
/// user's scroll-direction setting points.
@Suite("Scroll direction")
@MainActor
struct ScrollSampleDirectionTests {
    @Test(arguments: [true, false])
    func swipingUpOverTheCoverIsLouder(natural: Bool) {
        var tracker = SwipeVolumeTracker()
        _ = tracker.handle(fingers(.began, natural: natural), isOverArtwork: true, volume: 0.5)
        let outcome = tracker.handle(fingers(.changed, up: 30, natural: natural), isOverArtwork: true, volume: 0.5)
        #expect(outcome.consumed)
        #expect((outcome.level ?? 0) > 0.5)
    }

    @Test(arguments: [true, false])
    func swipingDownOverTheCoverIsQuieter(natural: Bool) {
        var tracker = SwipeVolumeTracker()
        _ = tracker.handle(fingers(.began, natural: natural), isOverArtwork: true, volume: 0.5)
        let outcome = tracker.handle(fingers(.changed, up: -30, natural: natural), isOverArtwork: true, volume: 0.5)
        #expect((outcome.level ?? 1) < 0.5)
    }

    /// Pages follow the fingers: pushing them left brings in the next surface.
    @Test(arguments: [true, false])
    func swipingLeftTurnsToTheNextSurface(natural: Bool) {
        let pager = SurfacePager(surface: .now)
        pager.pageWidth = 200
        _ = pager.handle(fingers(.began, natural: natural))
        for step in 1...3 {
            _ = pager.handle(fingers(.changed, right: -15, natural: natural, at: Double(step) * 0.01))
        }
        _ = pager.handle(fingers(.ended, natural: natural, at: 0.035))
        #expect(pager.current == .echo)
    }

    @Test(arguments: [true, false])
    func swipingRightAtTheFirstSurfaceGoesNowhere(natural: Bool) {
        let pager = SurfacePager(surface: .now)
        pager.pageWidth = 200
        _ = pager.handle(fingers(.began, natural: natural))
        for step in 1...3 {
            _ = pager.handle(fingers(.changed, right: 15, natural: natural, at: Double(step) * 0.01))
        }
        _ = pager.handle(fingers(.ended, natural: natural, at: 0.035))
        #expect(pager.current == .now)
    }
}
