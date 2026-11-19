import CoreGraphics
import HumCore
@testable import HumUI
import Testing

@Suite("Echo and Status in the short styles")
struct PlayerExpansionTests {
    let visible = CGRect(x: 0, y: 0, width: 1500, height: 900)

    @Test func theBarsGrowForEchoAndStatusOnly() {
        for style in [PlayerStyleID.title, .text, .strip] {
            #expect(!PlayerExpansion.isNeeded(for: .now, style: style))
            #expect(PlayerExpansion.isNeeded(for: .echo, style: style))
            #expect(PlayerExpansion.isNeeded(for: .status, style: style))
        }
    }

    @Test func artOnlyAndBigArtNeverGrow() {
        for style in [PlayerStyleID.artOnly, .bigArt] {
            for surface in Surface.allCases {
                #expect(!PlayerExpansion.isNeeded(for: surface, style: style))
            }
        }
    }

    @Test func theyGrowToTheSurfaceSquare() {
        #expect(PlayerExpansion.expandedSize == CGSize(width: StyleGeometry.surfaceSide, height: StyleGeometry.surfaceSide))
        #expect(PlayerExpansion.expandedSize == CGSize(width: 300, height: 300))
    }

    @Test func theSessionEndsBackOnNow() {
        let session = expansion()
        #expect(session.holds(on: .echo))
        #expect(session.holds(on: .status))
        #expect(!session.holds(on: .now))
    }

    @Test func aPinnedBarHoldsItsPinnedCornerBothWays() {
        // Title, pinned Top Right: the top-right corner stays put.
        let frame = PlacementResolver.frame(for: .topRight, size: CGSize(width: 300, height: 72), in: visible)
        var session = expansion()
        session.restoreSize = frame.size
        let grown = session.expandedFrame(from: frame, pin: .topRight, in: visible)
        #expect(grown.size == PlayerExpansion.expandedSize)
        #expect(grown.maxX == frame.maxX)
        #expect(grown.maxY == frame.maxY)
        #expect(session.restoredFrame(from: grown, pin: .topRight, in: visible) == frame)
    }

    @Test func aBarPinnedAtTheBottomGrowsUpFromItsMiddle() {
        let frame = PlacementResolver.frame(for: .bottom, size: CGSize(width: 400, height: 48), in: visible)
        var session = expansion()
        session.restoreSize = frame.size
        let grown = session.expandedFrame(from: frame, pin: .bottom, in: visible)
        #expect(grown.midX == frame.midX)
        #expect(grown.minY == frame.minY)
        #expect(session.restoredFrame(from: grown, pin: .bottom, in: visible) == frame)
    }

    @Test func aCenteredBarGrowsAboutItsCenter() {
        let frame = PlacementResolver.frame(for: .center, size: CGSize(width: 240, height: 44), in: visible)
        var session = expansion()
        session.restoreSize = frame.size
        let grown = session.expandedFrame(from: frame, pin: .center, in: visible)
        #expect(grown.midX == frame.midX)
        #expect(grown.midY == frame.midY)
        #expect(session.restoredFrame(from: grown, pin: .center, in: visible) == frame)
    }

    @Test func anUnpinnedBarHoldsTheCornerItGrewFrom() {
        let frame = CGRect(x: 600, y: 836, width: 400, height: 48)
        var session = expansion()
        session.restoreSize = frame.size
        session.anchor = PlacementResolver.anchor(of: frame, in: visible)
        let grown = session.expandedFrame(from: frame, pin: nil, in: visible)
        #expect(grown == CGRect(x: 650, y: 584, width: 300, height: 300))
        #expect(visible.contains(grown))
        #expect(session.restoredFrame(from: grown, pin: nil, in: visible) == frame)
    }

    @Test func aGrownPlayerMovedElsewhereShrinksWhereItWasMoved() {
        var session = expansion()
        session.restoreSize = CGSize(width: 300, height: 72)
        session.anchor = CGPoint(x: 0, y: 0)
        let moved = CGRect(x: 100, y: 100, width: 300, height: 300)
        let restored = session.restoredFrame(from: moved, pin: nil, in: visible)
        #expect(restored.origin == moved.origin)
        #expect(restored.size == session.restoreSize)
    }

    @Test func aGrownPlayerThrownToAnotherPinShrinksAtThatPin() {
        var session = expansion()
        session.restoreSize = CGSize(width: 300, height: 72)
        let grown = PlacementResolver.frame(for: .bottomLeft, size: PlayerExpansion.expandedSize, in: visible)
        let restored = session.restoredFrame(from: grown, pin: .bottomLeft, in: visible)
        #expect(restored == PlacementResolver.frame(for: .bottomLeft, size: session.restoreSize, in: visible))
        #expect(restored.minX == grown.minX)
        #expect(restored.minY == grown.minY)
    }

    @Test func growingAgainMidShrinkReturnsToTheSizeBefore() {
        let shrinking = CGRect(x: 0, y: 0, width: 280, height: 160)
        let heading = CGRect(x: 0, y: 0, width: 300, height: 72)
        #expect(PlayerExpansion.restoreSize(frame: shrinking, heading: heading) == heading.size)
        #expect(PlayerExpansion.restoreSize(frame: heading, heading: nil) == heading.size)
    }

    private func expansion() -> PlayerExpansion {
        PlayerExpansion(restoreSize: CGSize(width: 300, height: 72), anchor: CGPoint(x: 1, y: 1))
    }
}

@Suite("Swipe to skip")
struct SwipeSkipTrackerTests {
    private func sample(
        _ phase: ScrollSample.Phase,
        x: Double = 0,
        y: Double = 0,
        at time: Double = 0,
        momentum: Bool = false
    ) -> ScrollSample {
        ScrollSample(phase: phase, isMomentum: momentum, fingerDeltaX: x, deltaY: y, isPrecise: true, timestamp: time)
    }

    /// Feeds `deltas`, one every `interval` seconds from `start`, and returns
    /// the skips that came back.
    private func drag(
        _ tracker: inout SwipeSkipTracker,
        _ deltas: [Double],
        every interval: Double,
        from start: Double
    ) -> [SwipeSkipTracker.Skip] {
        deltas.enumerated().compactMap { index, x in
            tracker.handle(sample(.changed, x: x, at: start + Double(index) * interval)).skip
        }
    }

    @Test func aLeftwardSwipeSkipsForwardOnceOnRelease() {
        var tracker = SwipeSkipTracker()
        #expect(tracker.handle(sample(.began, x: -6, at: 0)).consumed == false)
        let lock = tracker.handle(sample(.changed, x: -8, at: 0.01))
        #expect(lock.consumed)
        #expect(lock.claimed)
        #expect(lock.skip == nil)
        for step in 0..<10 {
            let outcome = tracker.handle(sample(.changed, x: -10, at: 0.02 + Double(step) * 0.01))
            #expect(!outcome.claimed)
            // Nothing skips while the fingers are down.
            #expect(outcome.skip == nil)
        }
        let release = tracker.handle(sample(.ended, at: 0.12))
        #expect(release.consumed)
        #expect(release.skip == .next)
        // The flick's momentum goes nowhere else, and skips nothing more.
        let momentum = tracker.handle(sample(.changed, x: -30, at: 0.13, momentum: true))
        #expect(momentum.consumed)
        #expect(momentum.skip == nil)
    }

    @Test func aRightwardSwipeGoesBack() {
        var tracker = SwipeSkipTracker()
        _ = tracker.handle(sample(.began, at: 0))
        #expect(drag(&tracker, Array(repeating: 12, count: 6), every: 0.01, from: 0.01).isEmpty)
        #expect(tracker.handle(sample(.ended, at: 0.07)).skip == .previous)
    }

    @Test func aShortQuickFlickSkips() {
        var tracker = SwipeSkipTracker()
        _ = tracker.handle(sample(.began, x: -4, at: 0))
        #expect(drag(&tracker, [-5, -5], every: 0.01, from: 0.01).isEmpty)
        // 14 pt of travel, well short of the commit distance, but quick.
        #expect(tracker.handle(sample(.ended, at: 0.025)).skip == .next)
    }

    @Test func aSlowShortDragDoesNotSkip() {
        var tracker = SwipeSkipTracker()
        _ = tracker.handle(sample(.began, at: 0))
        // 30 pt over a second.
        #expect(drag(&tracker, Array(repeating: -0.6, count: 50), every: 0.02, from: 0.02).isEmpty)
        let release = tracker.handle(sample(.ended, at: 1.0))
        #expect(release.consumed)
        #expect(release.skip == nil)
    }

    @Test func aDragPastTheCommitDistanceFlickedBackDoesNotSkip() {
        var tracker = SwipeSkipTracker()
        _ = tracker.handle(sample(.began, at: 0))
        // 80 pt to the left, then a quick 30 pt back to the right.
        #expect(drag(&tracker, Array(repeating: -8, count: 10), every: 0.05, from: 0.05).isEmpty)
        #expect(drag(&tracker, [10, 10, 10], every: 0.01, from: 0.51).isEmpty)
        let release = tracker.handle(sample(.ended, at: 0.54))
        #expect(release.consumed)
        #expect(release.skip == nil)
    }

    @Test func aCancelledSwipeDoesNotSkip() {
        var tracker = SwipeSkipTracker()
        _ = tracker.handle(sample(.began, at: 0))
        #expect(drag(&tracker, Array(repeating: -20, count: 5), every: 0.01, from: 0.01).isEmpty)
        let cancel = tracker.handle(sample(.cancelled, at: 0.06))
        #expect(cancel.consumed)
        #expect(cancel.skip == nil)
    }

    @Test func aVerticalSwipeIsLeftAlone() {
        var tracker = SwipeSkipTracker()
        _ = tracker.handle(sample(.began, y: 5))
        for _ in 0..<6 {
            let outcome = tracker.handle(sample(.changed, x: 3, y: 14))
            #expect(!outcome.consumed)
            #expect(outcome.skip == nil)
        }
        #expect(!tracker.handle(sample(.ended)).consumed)
        #expect(!tracker.handle(sample(.changed, y: 20, momentum: true)).consumed)
    }

    @Test func aMouseWheelNeverSkips() {
        var tracker = SwipeSkipTracker()
        let wheel = ScrollSample(phase: .none, isMomentum: false, fingerDeltaX: -80, deltaY: 0, isPrecise: false, timestamp: 0)
        #expect(tracker.handle(wheel) == SwipeSkipTracker.Outcome(consumed: false, skip: nil, claimed: false))
    }
}
