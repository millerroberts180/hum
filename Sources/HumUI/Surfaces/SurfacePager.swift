import HumCore
import Observation
import SwiftUI

/// Moves the player between its three surfaces.
///
/// `position` is a fractional page index that the container renders directly: 0 is
/// Now, 1.5 is halfway between History and Status. A two-finger swipe moves it 1:1 with
/// the fingers, the ends resist like rubber, and on release a spring carries it to
/// the page the flick was heading for, starting at the fingers' velocity. Touching
/// the trackpad again mid-flight catches the page where it is.
///
/// Clicks and keys animate with a critically damped spring.
/// With Reduce Motion, nothing slides: a swipe past a short threshold switches
/// surfaces with a crossfade.
@MainActor
@Observable
public final class SurfacePager {
    public private(set) var position: Double
    public private(set) var navigation: SurfaceNavigation
    /// Fingers are on the trackpad and the page is following them.
    public private(set) var isTracking = false
    /// A spring is carrying the page to rest.
    public private(set) var isSettling = false

    public var current: Surface { navigation.current }
    /// The page is anywhere but at rest on `current`.
    public var isMoving: Bool { isTracking || isSettling }

    public var reduceMotion = false
    /// Width of one page, in points. The container keeps this up to date.
    @ObservationIgnored var pageWidth: Double = PlayerMetrics.defaultSide

    /// Called when `current` changes, however it changed.
    @ObservationIgnored public var onSurfaceChange: (@MainActor (Surface) -> Void)?

    /// Called once when a page thrown by a swipe comes to rest, for the haptic.
    @ObservationIgnored var onGestureSettle: (() -> Void)?
    @ObservationIgnored private var isSettlingFromGesture = false

    /// Whether the page indicator shows: only while this pager's page changes
    /// (DESIGN.md §6). Made on first use; tests set their own first.
    @ObservationIgnored lazy var indicator = PageIndicatorVisibility(following: self)

    @ObservationIgnored var frameDriver: (any FrameDriving)? {
        didSet {
            oldValue?.stop()
            frameDriver?.onFrame = { [weak self] time in self?.step(to: time) }
            if isSettling { frameDriver?.start() }
        }
    }

    // MARK: Gesture state

    private enum Axis { case undecided, horizontal, vertical }

    @ObservationIgnored private var axis: Axis?
    @ObservationIgnored private var pendingX = 0.0
    @ObservationIgnored private var pendingY = 0.0
    @ObservationIgnored private var rawPosition = 0.0
    @ObservationIgnored private var gestureStartPage = 0
    @ObservationIgnored private var history: [(time: TimeInterval, position: Double)] = []
    @ObservationIgnored private var swallowMomentum = false
    @ObservationIgnored private var reduceMotionCommitted = false
    @ObservationIgnored private var swipeDistance = 0.0
    /// The page a caught spring was heading for, in case the fingers lift without moving.
    @ObservationIgnored private var caughtTarget: Int?

    // MARK: Spring state

    @ObservationIgnored private var spring: SpringSolver?
    @ObservationIgnored private var springTarget = 0
    @ObservationIgnored private var springStart: TimeInterval?
    @ObservationIgnored private var lastFrameTime: TimeInterval?

    /// Movement before the gesture commits to an axis (DESIGN.md §4.2).
    static let axisLockDistance = 12.0
    /// Horizontal movement must beat vertical by this factor to page.
    static let axisDominance = 1.3
    /// Velocity is measured over this much recent movement.
    static let velocityWindow = PagingPhysics.velocityWindow
    /// Under Reduce Motion, a swipe this long (points) switches surfaces.
    static let reduceMotionThreshold = 40.0

    private static var pageCount: Int { Surface.allCases.count }

    public init(surface: Surface = .now) {
        navigation = SurfaceNavigation(current: surface)
        position = Double(surface.index)
    }

    // MARK: Direct navigation

    /// Show `surface`. Animated changes slide with a spring (or crossfade under
    /// Reduce Motion); unanimated ones jump.
    public func go(to surface: Surface, animated: Bool) {
        if animated, !reduceMotion {
            commit(surface)
            settle(to: surface.index, velocity: currentVelocity(), parameters: Motion.pageDirect)
        } else if animated {
            stopSpring()
            withAnimation(Motion.crossfade) {
                commit(surface)
                position = Double(surface.index)
            }
        } else {
            stopSpring()
            commit(surface)
            position = Double(surface.index)
        }
    }

    public func forward(animated: Bool) {
        guard let next = Surface(index: current.index + 1) else { return }
        go(to: next, animated: animated)
    }

    public func back(animated: Bool) {
        guard let previous = Surface(index: current.index - 1) else { return }
        go(to: previous, animated: animated)
    }

    // MARK: Scroll gestures

    enum Disposition: Equatable {
        /// The pager used the event; nothing else should see it.
        case consumed
        /// Not a paging gesture; let it scroll whatever is under the pointer.
        case passThrough
    }

    func handle(_ sample: ScrollSample) -> Disposition {
        if sample.isMomentum {
            return swallowMomentum ? .consumed : .passThrough
        }
        guard sample.isPrecise else { return .passThrough }

        switch sample.phase {
        case .none:
            return .passThrough
        case .mayBegin:
            catchSpring()
            return .passThrough
        case .began:
            begin(at: sample.timestamp)
            return track(sample)
        case .changed:
            if axis == nil { begin(at: sample.timestamp) }
            return track(sample)
        case .ended, .cancelled:
            return end(sample, cancelled: sample.phase == .cancelled)
        }
    }

    private func begin(at time: TimeInterval) {
        swallowMomentum = false
        reduceMotionCommitted = false
        swipeDistance = 0
        axis = .undecided
        pendingX = 0
        pendingY = 0
        if isSettling {
            catchSpring()
        }
        gestureStartPage = caughtTarget ?? Int(position.rounded())
        rawPosition = PagingPhysics.rawPosition(fromBanded: position, pageCount: Self.pageCount, pageWidth: pageWidth)
        history = [(time, position)]
    }

    private func track(_ sample: ScrollSample) -> Disposition {
        switch axis {
        case nil, .vertical:
            return .passThrough
        case .undecided:
            pendingX += sample.fingerDeltaX
            pendingY += sample.deltaY
            guard max(abs(pendingX), abs(pendingY)) >= Self.axisLockDistance else {
                return .passThrough
            }
            if abs(pendingX) > abs(pendingY) * Self.axisDominance {
                axis = .horizontal
                swallowMomentum = true
                caughtTarget = nil
                isTracking = !reduceMotion
                move(by: pendingX, at: sample.timestamp)
                return .consumed
            } else {
                axis = .vertical
                if let caughtTarget {
                    self.caughtTarget = nil
                    settle(to: caughtTarget, velocity: 0, parameters: Motion.pageDirect)
                }
                return .passThrough
            }
        case .horizontal:
            move(by: sample.fingerDeltaX, at: sample.timestamp)
            return .consumed
        }
    }

    private func move(by fingerDelta: Double, at time: TimeInterval) {
        if reduceMotion {
            swipeDistance += fingerDelta
            guard !reduceMotionCommitted, abs(swipeDistance) >= Self.reduceMotionThreshold else { return }
            reduceMotionCommitted = true
            if swipeDistance < 0 { forward(animated: true) } else { back(animated: true) }
            return
        }
        // Fingers moving left pull the next page in from the right.
        rawPosition -= fingerDelta / max(pageWidth, 1)
        position = PagingPhysics.bandedPosition(rawPosition, pageCount: Self.pageCount, pageWidth: pageWidth)
        history.append((time, position))
        history.removeAll { time - $0.time > Self.velocityWindow * 2 }
    }

    private func end(_ sample: ScrollSample, cancelled: Bool) -> Disposition {
        defer {
            axis = nil
            isTracking = false
            history.removeAll()
        }
        guard axis == .horizontal else {
            // Fingers lifted without paging: let a caught page carry on to where
            // it was going.
            if let caughtTarget {
                self.caughtTarget = nil
                settle(to: caughtTarget, velocity: 0, parameters: Motion.pageDirect)
            }
            return .passThrough
        }
        guard !reduceMotion else { return .consumed }

        let velocity = cancelled ? 0 : releaseVelocity(at: sample.timestamp)
        let target = PagingPhysics.targetPage(
            position: position,
            velocity: velocity,
            startPage: gestureStartPage,
            pageCount: Self.pageCount,
            pageWidth: pageWidth
        )
        if let surface = Surface(index: target) {
            commit(surface)
        }
        settle(to: target, velocity: velocity, parameters: Motion.pageMomentum)
        if isSettling { isSettlingFromGesture = true }
        return .consumed
    }

    /// Pages per second over the last few events. If the fingers paused before
    /// lifting, the swipe has no velocity left.
    private func releaseVelocity(at time: TimeInterval) -> Double {
        PagingPhysics.releaseVelocity(history.map { ($0.time, $0.position) }, at: time)
    }

    // MARK: Spring

    private func settle(to page: Int, velocity: Double, parameters: SpringParameters) {
        let displacement = position - Double(page)
        springTarget = page
        guard frameDriver != nil, abs(displacement) > SpringSolver.restDisplacement || abs(velocity) > SpringSolver.restVelocity else {
            finishSpring()
            return
        }
        spring = SpringSolver(parameters: parameters, initialDisplacement: displacement, initialVelocity: velocity)
        springStart = nil
        lastFrameTime = nil
        isSettling = true
        frameDriver?.start()
    }

    /// Advance the spring to `time`. Called by the frame driver once per frame.
    func step(to time: TimeInterval) {
        guard let spring else {
            frameDriver?.stop()
            return
        }
        let start = springStart ?? time
        springStart = start
        lastFrameTime = time
        let elapsed = time - start
        if spring.isAtRest(at: elapsed) {
            finishSpring()
        } else {
            position = Double(springTarget) + spring.state(at: elapsed).displacement
        }
    }

    private func currentVelocity() -> Double {
        guard let spring, let springStart, let lastFrameTime else { return 0 }
        return spring.state(at: lastFrameTime - springStart).velocity
    }

    /// Stop the spring where it is so the fingers can take over.
    private func catchSpring() {
        guard isSettling else { return }
        caughtTarget = springTarget
        stopSpring()
    }

    private func stopSpring() {
        isSettlingFromGesture = false
        spring = nil
        springStart = nil
        lastFrameTime = nil
        isSettling = false
        frameDriver?.stop()
    }

    private func finishSpring() {
        let fromGesture = isSettlingFromGesture
        stopSpring()
        position = Double(springTarget)
        if fromGesture { onGestureSettle?() }
    }

    private func commit(_ surface: Surface) {
        guard navigation.go(to: surface) else { return }
        onSurfaceChange?(surface)
    }
}
