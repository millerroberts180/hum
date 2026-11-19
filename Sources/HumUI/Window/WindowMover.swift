import AppKit
import HumCore

/// Moves the player when its content is dragged.
///
/// The window follows the pointer 1:1 and keeps the grabbed point under it.
/// Past the edges of the screens it rubber-bands. On release it either settles on
/// the pin position nearest to where the throw was heading, carrying the throw's
/// velocity, or (with snapping off) stays where it was dropped. Grabbing it while
/// it's still moving catches it.
///
/// It also carries the window's size changes (a style switch, growing for Echo
/// or Status) in the same spring as its position, so a resize and a move are
/// one continuous motion. Under Reduce Motion the window fades out, jumps, and
/// fades back in place of every spring.
final class WindowMover {
    private weak var window: NSWindow?
    private let frameDriver: any FrameDriving

    var snapsToCorners: () -> Bool = { true }
    /// The pin positions a throw can settle at: all nine, or Under Menu Bar's
    /// top row.
    var snapPins: () -> [PinPosition] = { PinPosition.allCases }
    /// On release, with where the throw is settling, or `nil` when it was
    /// dropped with snapping off.
    var onRelease: (SnapProjection.Snap?) -> Void = { _ in }
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// After every move the user caused, once the window is at rest.
    var onSettle: () -> Void = {}
    /// The trackpad haptic a throw fires once as it settles.
    var performHaptic: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    /// Where the pointer is, in screen coordinates.
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }
    /// The uptime clock a throw's velocity is read on.
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// Every screen's usable area.
    var visibleFrames: () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) }

    private var grabOffset: CGPoint?
    private var history: [(time: TimeInterval, origin: CGPoint)] = []
    private var flight: Flight?

    private struct Flight {
        var target: CGRect
        var x: SpringSolver
        var y: SpringSolver
        /// Only when the size changes too.
        var width: SpringSolver?
        var height: SpringSolver?
        var start: TimeInterval?
        var completion: (() -> Void)?
    }

    /// Velocity is read over this much of the drag's end.
    static let velocityWindow: TimeInterval = 0.1
    static let restDistance: CGFloat = 0.5
    static let restSpeed: CGFloat = 8

    init(window: NSWindow, frameDriver: any FrameDriving) {
        self.window = window
        self.frameDriver = frameDriver
        frameDriver.onFrame = { [weak self] time in self?.step(to: time) }
    }

    var isMoving: Bool { grabOffset != nil || flight != nil || isCrossfading }

    /// A size change is on its way, so the frame on screen isn't one to remember.
    var isResizing: Bool { flight?.width != nil || isCrossfading }

    /// Where a size change on its way is taking the window: the frame to
    /// remember in place of the one on screen.
    var resizeDestination: CGRect? {
        if let flight, flight.width != nil { return flight.target }
        return isCrossfading ? crossfadeTarget : nil
    }

    private var isCrossfading = false
    private var crossfadeTarget: CGRect?
    /// Run once a Reduce Motion crossfade has brought the window back in.
    private var crossfadeCompletion: (() -> Void)?

    func handle(_ phase: WindowDragPhase) {
        switch phase {
        case .changed(let translation): drag(translation: translation)
        case .ended: release()
        }
    }

    /// Spring the window to `origin`, as the tucked slide does.
    func settle(to origin: CGPoint, parameters: SpringParameters, completion: (() -> Void)? = nil) {
        animate(to: origin, velocity: .zero, parameters: parameters, completion: completion)
    }

    /// Where the window is going: the end of the motion under way, or where
    /// it is.
    var destination: CGRect? {
        if let flight { return flight.target }
        if isCrossfading, let crossfadeTarget { return crossfadeTarget }
        return window?.frame
    }

    /// Spring the window's position and size to `frame` together. Starts from
    /// wherever the window is on screen, so it can interrupt any other motion.
    func settle(to frame: CGRect, parameters: SpringParameters, completion: (() -> Void)? = nil) {
        guard let window else { return }
        let current = window.frame
        if reduceMotion() {
            stop()
            crossfade(to: frame, completion: completion)
            return
        }
        flight = Flight(
            target: frame,
            x: SpringSolver(parameters: parameters, initialDisplacement: current.minX - frame.minX, initialVelocity: 0),
            y: SpringSolver(parameters: parameters, initialDisplacement: current.minY - frame.minY, initialVelocity: 0),
            width: SpringSolver(parameters: parameters, initialDisplacement: current.width - frame.width, initialVelocity: 0),
            height: SpringSolver(parameters: parameters, initialDisplacement: current.height - frame.height, initialVelocity: 0),
            completion: completion
        )
        frameDriver.start()
    }

    /// Stop any motion where it is.
    func stop() {
        flight = nil
        frameDriver.stop()
    }

    // MARK: Dragging

    private func drag(translation: CGSize) {
        guard let window else { return }
        let pointer = pointerLocation()
        let now = self.now()
        if grabOffset == nil {
            let wasMoving = flight != nil
            stop()
            // Where the press landed. SwiftUI's y runs down; the screen's runs up.
            let anchor = wasMoving
                ? pointer
                : CGPoint(x: pointer.x - translation.width, y: pointer.y + translation.height)
            grabOffset = CGPoint(x: anchor.x - window.frame.minX, y: anchor.y - window.frame.minY)
            history.removeAll()
        }
        guard let grabOffset else { return }
        let raw = CGPoint(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y)
        let origin = SnapProjection.rubberBanded(origin: raw, size: window.frame.size, bounds: screenBounds)
        window.setFrameOrigin(origin)
        history.append((now, origin))
        history.removeAll { now - $0.time > Self.velocityWindow * 2 }
    }

    private func release() {
        guard grabOffset != nil, let window else { return }
        grabOffset = nil
        let velocity = releaseVelocity()
        history.removeAll()
        let frame = window.frame
        let visibleFrames = visibleFrames()

        if snapsToCorners(),
           let snap = SnapProjection.target(
               origin: frame.origin,
               size: frame.size,
               velocity: velocity,
               visibleFrames: visibleFrames,
               among: snapPins()
           ) {
            onRelease(snap)
            animate(to: snap.origin, velocity: velocity, parameters: Motion.throwSpring) { [weak self] in
                self?.performHaptic()
            }
            return
        }
        onRelease(nil)

        // Dropped: stay put, but come back inside if it was let go past an edge
        // of the screen it's mostly on.
        let visible = visibleFrames.max { overlap($0, frame) < overlap($1, frame) } ?? frame
        let inside = PlacementResolver.clamp(frame, to: visible).origin
        if inside != frame.origin {
            animate(to: inside, velocity: .zero, parameters: Motion.smoothSpring, completion: nil)
        } else {
            onSettle()
        }
    }

    /// Points per second over the last moment of the drag; zero if the pointer
    /// paused before letting go.
    private func releaseVelocity() -> CGVector {
        let now = self.now()
        guard let last = history.last, now - last.time < Self.velocityWindow else { return .zero }
        let recent = history.filter { last.time - $0.time <= Self.velocityWindow }
        guard let first = recent.first, last.time - first.time > 0.005 else { return .zero }
        let dt = last.time - first.time
        return CGVector(dx: (last.origin.x - first.origin.x) / dt, dy: (last.origin.y - first.origin.y) / dt)
    }

    /// The bounding box of every screen's usable area.
    private var screenBounds: CGRect {
        visibleFrames().reduce(CGRect.null) { $0.union($1) }
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = a.intersection(b)
        return shared.isNull ? 0 : shared.width * shared.height
    }

    // MARK: Springs

    private func animate(
        to target: CGPoint,
        velocity: CGVector,
        parameters: SpringParameters,
        completion: (() -> Void)?
    ) {
        guard let window else { return }
        let origin = window.frame.origin
        if reduceMotion() {
            crossfade(to: CGRect(origin: target, size: window.frame.size), completion: completion)
            return
        }
        flight = Flight(
            target: CGRect(origin: target, size: window.frame.size),
            x: SpringSolver(parameters: parameters, initialDisplacement: origin.x - target.x, initialVelocity: velocity.dx),
            y: SpringSolver(parameters: parameters, initialDisplacement: origin.y - target.y, initialVelocity: velocity.dy),
            completion: completion
        )
        frameDriver.start()
    }

    private func step(to time: TimeInterval) {
        guard var flight, let window else {
            stop()
            return
        }
        let start = flight.start ?? time
        flight.start = start
        self.flight = flight
        let elapsed = time - start
        let states = [flight.x, flight.y, flight.width, flight.height].compactMap { $0?.state(at: elapsed) }
        let atRest = states.allSatisfy { abs($0.displacement) < Self.restDistance && abs($0.velocity) < Self.restSpeed }
        let target = flight.target
        if atRest {
            if flight.width != nil {
                window.setFrame(target, display: true)
            } else {
                window.setFrameOrigin(target.origin)
            }
            stop()
            finish(flight.completion)
            return
        }
        let x = target.minX + flight.x.state(at: elapsed).displacement
        let y = target.minY + flight.y.state(at: elapsed).displacement
        if let width = flight.width, let height = flight.height {
            let frame = CGRect(
                x: x,
                y: y,
                width: target.width + width.state(at: elapsed).displacement,
                height: target.height + height.state(at: elapsed).displacement
            )
            window.setFrame(frame, display: true)
        } else {
            window.setFrameOrigin(CGPoint(x: x, y: y))
        }
    }

    /// Reduce Motion's move: fade out where it is, jump, and fade back in.
    private func crossfade(to frame: CGRect, completion: (() -> Void)?) {
        guard let window else { return }
        let alpha = window.alphaValue
        isCrossfading = true
        crossfadeTarget = frame
        crossfadeCompletion = completion
        let half = Motion.crossfadeDuration / 2
        NSAnimationContext.runAnimationGroup { context in
            context.duration = half
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                window?.setFrame(frame, display: true)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = half
                    window?.animator().alphaValue = alpha
                } completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.isCrossfading = false
                        let completion = self.crossfadeCompletion
                        self.crossfadeCompletion = nil
                        self.finish(completion)
                    }
                }
            }
        }
    }

    private func finish(_ completion: (() -> Void)?) {
        window?.invalidateShadow()
        completion?()
        onSettle()
    }
}
