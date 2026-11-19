import Foundation
import HumCore
@testable import HumUI
import Testing

/// Frames on demand, so a spring can be run to rest without a display.
@MainActor
private final class ManualFrameDriver: FrameDriving {
    var onFrame: ((TimeInterval) -> Void)?
    private(set) var isRunning = false

    func start() { isRunning = true }
    func stop() { isRunning = false }

    /// Step at 60 fps from `start` until the driver stops or `limit` seconds pass.
    func run(from start: TimeInterval = 10, limit: TimeInterval = 5) {
        var time = start
        while isRunning, time - start < limit {
            onFrame?(time)
            time += 1.0 / 60
        }
    }

    func frames(_ count: Int, from start: TimeInterval = 10) {
        for index in 0..<count {
            onFrame?(start + Double(index) / 60)
        }
    }
}

private func sample(
    _ phase: ScrollSample.Phase,
    x: Double = 0,
    y: Double = 0,
    at time: TimeInterval = 0,
    momentum: Bool = false
) -> ScrollSample {
    ScrollSample(phase: phase, isMomentum: momentum, fingerDeltaX: x, deltaY: y, isPrecise: true, timestamp: time)
}

@MainActor
@Suite("Surface pager")
struct SurfacePagerTests {
    private func pager(on surface: Surface = .now) -> SurfacePager {
        let pager = SurfacePager(surface: surface)
        pager.pageWidth = 200
        return pager
    }

    @Test func nothingMovesUntilTheAxisLocks() {
        let pager = pager()
        #expect(pager.handle(sample(.began)) == .passThrough)
        #expect(pager.handle(sample(.changed, x: -11, at: 0.01)) == .passThrough)
        #expect(pager.position == 0)
        #expect(pager.handle(sample(.changed, x: -2, at: 0.02)) == .consumed)
        // The movement before the lock still counts, so the page meets the fingers.
        #expect(abs(pager.position - 13.0 / 200) < 1e-9)
        #expect(pager.isTracking)
    }

    @Test func aVerticalSwipeIsLeftForWhateverIsUnderThePointer() {
        let pager = pager()
        _ = pager.handle(sample(.began))
        #expect(pager.handle(sample(.changed, x: 4, y: 20, at: 0.01)) == .passThrough)
        #expect(pager.handle(sample(.changed, x: -60, at: 0.02)) == .passThrough)
        #expect(pager.handle(sample(.ended, at: 0.03)) == .passThrough)
        #expect(pager.handle(sample(.changed, x: -10, at: 0.05, momentum: true)) == .passThrough)
        #expect(pager.position == 0)
        #expect(pager.current == .now)
    }

    @Test func aFlickTurnsOnePageAndSettlesThereOnce() {
        let pager = pager()
        let driver = ManualFrameDriver()
        pager.frameDriver = driver
        var changes: [Surface] = []
        var settles = 0
        pager.onSurfaceChange = { changes.append($0) }
        pager.onGestureSettle = { settles += 1 }

        _ = pager.handle(sample(.began))
        for step in 1...3 {
            _ = pager.handle(sample(.changed, x: -15, at: Double(step) * 0.01))
        }
        #expect(pager.handle(sample(.ended, at: 0.035)) == .consumed)
        // However hard the flick, one swipe moves one page.
        #expect(pager.current == .echo)
        #expect(changes == [.echo])
        #expect(pager.isSettling)
        // Its momentum belongs to the page, not to a list underneath.
        #expect(pager.handle(sample(.changed, x: -10, at: 0.05, momentum: true)) == .consumed)

        driver.run()
        #expect(!pager.isSettling)
        #expect(pager.position == 1)
        #expect(settles == 1)
    }

    @Test func aSlowDragThatPausesFallsBackToItsPage() {
        let pager = pager()
        _ = pager.handle(sample(.began))
        _ = pager.handle(sample(.changed, x: -15, at: 0.01))
        _ = pager.handle(sample(.changed, x: -15, at: 0.02))
        _ = pager.handle(sample(.ended, at: 0.5))
        #expect(pager.current == .now)
        #expect(pager.position == 0)
    }

    @Test func theFirstPageResistsLikeRubber() {
        let pager = pager()
        _ = pager.handle(sample(.began))
        _ = pager.handle(sample(.changed, x: 100, at: 0.01))
        #expect(pager.position < 0)
        #expect(pager.position > -0.5)
    }

    @Test func aPageCaughtMidFlightCarriesOnIfTheFingersLiftWithoutMoving() {
        let pager = pager()
        let driver = ManualFrameDriver()
        pager.frameDriver = driver
        pager.go(to: .echo, animated: true)
        driver.frames(4)
        let caught = pager.position
        #expect(caught > 0 && caught < 1)

        _ = pager.handle(sample(.mayBegin))
        #expect(!pager.isSettling)
        #expect(pager.position == caught)

        _ = pager.handle(sample(.began))
        _ = pager.handle(sample(.ended, at: 0.01))
        #expect(pager.isSettling)
        driver.run()
        #expect(pager.position == 1)
        #expect(pager.current == .echo)
    }

    @Test func underReduceMotionASwipeSwitchesOnceWithoutSliding() {
        let pager = pager()
        pager.reduceMotion = true
        _ = pager.handle(sample(.began))
        #expect(pager.handle(sample(.changed, x: -15, at: 0.01)) == .consumed)
        #expect(!pager.isTracking)
        #expect(pager.current == .now)
        _ = pager.handle(sample(.changed, x: -30, at: 0.02))
        #expect(pager.current == .echo)
        #expect(pager.position == 1)
        _ = pager.handle(sample(.changed, x: -60, at: 0.03))
        #expect(pager.handle(sample(.ended, at: 0.04)) == .consumed)
        #expect(pager.current == .echo)
    }

    @Test func anUnanimatedChangeIsInstant() {
        // Restoring the last surface on launch, or putting it back after an expansion.
        let pager = pager()
        let driver = ManualFrameDriver()
        pager.frameDriver = driver
        pager.go(to: .echo, animated: false)
        #expect(pager.position == 1)
        #expect(!driver.isRunning)
        pager.forward(animated: false)
        #expect(pager.current == .status)
        #expect(pager.position == 2)
        // Status is the last page.
        pager.forward(animated: false)
        #expect(pager.current == .status)
    }
}

@Suite("Paging physics")
struct PagingPhysicsTests {
    @Test func theRubberBandGivesLessThanTheDragAndNeverAPage() {
        #expect(PagingPhysics.rubberBand(0, dimension: 200) == 0)
        var previous = 0.0
        for overshoot in stride(from: 10.0, through: 2000, by: 10) {
            let banded = PagingPhysics.rubberBand(overshoot, dimension: 200)
            #expect(banded > previous)
            #expect(banded < overshoot)
            #expect(banded < 200)
            previous = banded
        }
        #expect(PagingPhysics.rubberBand(-50, dimension: 200) == -PagingPhysics.rubberBand(50, dimension: 200))
    }

    @Test func unbandingUndoesBanding() {
        for overshoot in [-300.0, -40, 5, 120, 900] {
            let banded = PagingPhysics.rubberBand(overshoot, dimension: 200)
            #expect(abs(PagingPhysics.unrubberBand(banded, dimension: 200) - overshoot) < 1e-6)
        }
        for raw in [-0.4, 0.5, 2.2, 3.3] {
            let banded = PagingPhysics.bandedPosition(raw, pageCount: 4, pageWidth: 200)
            #expect(abs(PagingPhysics.rawPosition(fromBanded: banded, pageCount: 4, pageWidth: 200) - raw) < 1e-6)
        }
    }

    @Test func positionsBetweenTheEndsAreUntouched() {
        #expect(PagingPhysics.bandedPosition(1.25, pageCount: 4, pageWidth: 200) == 1.25)
        #expect(PagingPhysics.bandedPosition(3.4, pageCount: 4, pageWidth: 200) < 3.4)
    }

    @Test func theTargetPageComesFromTheProjectedRest() {
        // At rest it's the nearest page.
        #expect(PagingPhysics.targetPage(position: 0.4, velocity: 0, startPage: 0, pageCount: 4, pageWidth: 200) == 0)
        #expect(PagingPhysics.targetPage(position: 0.6, velocity: 0, startPage: 0, pageCount: 4, pageWidth: 200) == 1)
        // A short quick flick still turns it; a flick back returns.
        #expect(PagingPhysics.targetPage(position: 0.1, velocity: 3, startPage: 0, pageCount: 4, pageWidth: 200) == 1)
        #expect(PagingPhysics.targetPage(position: 0.6, velocity: -3, startPage: 0, pageCount: 4, pageWidth: 200) == 0)
        // Never more than one page, and never past the ends.
        #expect(PagingPhysics.targetPage(position: 1.2, velocity: 40, startPage: 1, pageCount: 4, pageWidth: 200) == 2)
        #expect(PagingPhysics.targetPage(position: 3.1, velocity: 40, startPage: 3, pageCount: 4, pageWidth: 200) == 3)
        #expect(PagingPhysics.targetPage(position: -0.1, velocity: -40, startPage: 0, pageCount: 4, pageWidth: 200) == 0)
    }

    @Test func aSlightFlickBackPastHalfwayStillReturns() {
        // 0.75 pages a second on a 200-pt page is 150 pt/s: a flick, backward.
        #expect(PagingPhysics.targetPage(position: 0.6, velocity: -0.75, startPage: 0, pageCount: 4, pageWidth: 200) == 0)
        #expect(PagingPhysics.targetPage(position: 1.4, velocity: 0.75, startPage: 1, pageCount: 4, pageWidth: 200) == 2)
        // A drift too slow to be a flick leaves it to the nearest page.
        #expect(PagingPhysics.targetPage(position: 0.6, velocity: -0.1, startPage: 0, pageCount: 4, pageWidth: 200) == 1)
        // From exactly on a page, a flick still turns it.
        #expect(PagingPhysics.targetPage(position: 1, velocity: 0.75, startPage: 1, pageCount: 4, pageWidth: 200) == 2)
    }

    @Test func aFlickProjectsLikeAScrollView() {
        #expect(abs(PagingPhysics.projectedDistance(velocity: 1000) - 499) < 1e-9)
        #expect(PagingPhysics.projectedDistance(velocity: 0) == 0)
    }
}

@MainActor
@Suite("Spring solver")
struct SpringSolverTests {
    @Test func everySpringStartsWhereItWasToldTo() {
        for damping in [0.6, 1.0, 1.5] {
            let spring = SpringSolver(
                parameters: SpringParameters(response: 0.35, dampingRatio: damping),
                initialDisplacement: -0.7,
                initialVelocity: 2
            )
            let start = spring.state(at: 0)
            #expect(abs(start.displacement + 0.7) < 1e-9)
            #expect(abs(start.velocity - 2) < 1e-9)
        }
    }

    /// Damping 1 is the default for anything without momentum: it arrives
    /// without overshooting.
    @Test func aCriticallyDampedSpringNeverOvershoots() {
        let spring = SpringSolver(parameters: Motion.smoothSpring, initialDisplacement: 1, initialVelocity: 0)
        for step in 0...200 {
            #expect(spring.state(at: Double(step) * 0.01).displacement >= 0)
        }
        #expect(!spring.isAtRest(at: 0))
        #expect(spring.isAtRest(at: 1))
    }

    @Test func onlyTheMomentumSpringOvershoots() {
        let spring = SpringSolver(parameters: Motion.pageMomentum, initialDisplacement: -0.5, initialVelocity: 6)
        let highest = (0...200).map { spring.state(at: Double($0) * 0.01).displacement }.max() ?? 0
        #expect(highest > 0)
        #expect(spring.isAtRest(at: 2))
    }

    @Test func anOverdampedSpringCreepsInFromOneSide() {
        let spring = SpringSolver(
            parameters: SpringParameters(response: 0.35, dampingRatio: 1.5),
            initialDisplacement: 1,
            initialVelocity: 0
        )
        for step in 0...300 {
            #expect(spring.state(at: Double(step) * 0.01).displacement >= 0)
        }
    }

    @Test func timeBeforeTheStartReadsAsTheStart() {
        let spring = SpringSolver(parameters: Motion.smoothSpring, initialDisplacement: 1, initialVelocity: 0)
        #expect(spring.state(at: -1).displacement == spring.state(at: 0).displacement)
    }
}
