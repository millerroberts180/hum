import AppKit
import HumCore
@testable import HumUI
import Testing

/// Frames on demand, so a spring can be run to rest without a display.
@MainActor
private final class SteppedFrameDriver: FrameDriving {
    var onFrame: ((TimeInterval) -> Void)?
    private(set) var isRunning = false

    func start() { isRunning = true }
    func stop() { isRunning = false }

    /// Step at 60 fps until the driver stops or `limit` seconds pass.
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

/// A 200 pt player on a window that's never shown, on one 1000 × 800 screen
/// unless the test adds more, with a pointer and a clock the test moves.
@MainActor
private final class MoverRig {
    static let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    static let side: CGFloat = 200

    let window: NSWindow
    let driver = SteppedFrameDriver()
    let mover: WindowMover
    var pointer = CGPoint.zero
    var time: TimeInterval = 100
    var settles = 0
    /// What each release said it was settling on.
    var releases: [SnapProjection.Snap?] = []
    var haptics = 0
    private var pressedAt = CGPoint.zero

    init(origin: CGPoint, snaps: Bool = true, screens: [CGRect] = [screen]) {
        window = NSWindow(
            contentRect: CGRect(origin: origin, size: CGSize(width: Self.side, height: Self.side)),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        mover = WindowMover(window: window, frameDriver: driver)
        mover.snapsToCorners = { snaps }
        mover.reduceMotion = { false }
        mover.pointerLocation = { [unowned self] in pointer }
        mover.now = { [unowned self] in time }
        mover.visibleFrames = { screens }
        mover.onSettle = { [unowned self] in settles += 1 }
        mover.onRelease = { [unowned self] snap in releases.append(snap) }
        mover.performHaptic = { [unowned self] in haptics += 1 }
    }

    var origin: CGPoint { window.frame.origin }

    func press(at point: CGPoint) {
        pressedAt = point
        pointer = point
    }

    /// One drag sample a frame after the last.
    func drag(to point: CGPoint) {
        time += 1.0 / 60
        pointer = point
        // SwiftUI's translation runs down the screen; the screen's y runs up.
        mover.handle(.changed(translation: CGSize(width: point.x - pressedAt.x, height: pressedAt.y - point.y)))
    }

    func release(after delay: TimeInterval = 1.0 / 120) {
        time += delay
        mover.handle(.ended)
    }

    /// A quick flick toward the top right, released mid-motion.
    func throwTowardTopRight() {
        flick(dx: 30, dy: 20)
    }

    /// Five drag samples of `dx`, `dy` a frame each, released mid-motion.
    func flick(dx: CGFloat, dy: CGFloat) {
        press(at: CGPoint(x: origin.x + 50, y: origin.y + 50))
        let start = pointer
        for step in 1...5 {
            drag(to: CGPoint(x: start.x + CGFloat(step) * dx, y: start.y + CGFloat(step) * dy))
        }
        release()
    }

    /// Moved by `dx`, `dy`, then held still long enough to have no speed, and let go.
    func drop(dx: CGFloat, dy: CGFloat) {
        press(at: CGPoint(x: origin.x + 50, y: origin.y + 50))
        drag(to: CGPoint(x: pointer.x + dx, y: pointer.y + dy))
        release(after: 0.5)
    }
}

@Suite("Moving the window")
@MainActor
struct WindowMoverTests {
    @Test func theGrabbedPointStaysUnderThePointer() {
        let rig = MoverRig(origin: CGPoint(x: 300, y: 300))
        rig.press(at: CGPoint(x: 350, y: 320))
        rig.drag(to: CGPoint(x: 360, y: 330))
        #expect(rig.origin == CGPoint(x: 310, y: 310))
        rig.drag(to: CGPoint(x: 600, y: 500))
        #expect(rig.origin == CGPoint(x: 550, y: 480))
    }

    @Test func pastTheScreensEdgeItResists() {
        let rig = MoverRig(origin: CGPoint(x: 300, y: 300))
        rig.press(at: CGPoint(x: 350, y: 350))
        // The pointer takes the window 200 pt past the left edge.
        rig.drag(to: CGPoint(x: -150, y: 350))
        let first = rig.origin
        #expect(first.x < 0)
        #expect(first.x > -200)
        #expect(first.y == 300)
        // Another 200 pt gains less than the first did.
        rig.drag(to: CGPoint(x: -350, y: 350))
        #expect(rig.origin.x < first.x)
        #expect(first.x - rig.origin.x < 0 - first.x)
    }

    @Test func aThrowSettlesOnTheCornerItWasHeadingFor() {
        let rig = MoverRig(origin: CGPoint(x: 500, y: 300))
        rig.throwTowardTopRight()
        #expect(rig.driver.isRunning)
        #expect(rig.mover.isMoving)
        // It's pinned Top Right as it's let go.
        #expect(rig.releases == [SnapProjection.Snap(pin: .topRight, origin: CGPoint(x: 784, y: 584), visibleFrame: MoverRig.screen)])
        #expect(rig.haptics == 0)
        rig.driver.run()
        // The top-right corner, inset 16 pt.
        #expect(rig.origin == CGPoint(x: 784, y: 584))
        #expect(!rig.mover.isMoving)
        #expect(rig.settles == 1)
        // One alignment tap as it lands.
        #expect(rig.haptics == 1)
    }

    @Test func aDropWithSnappingOnGoesToTheNearestOfTheNinePins() {
        let rig = MoverRig(origin: CGPoint(x: 300, y: 300))
        rig.drop(dx: 10, dy: 0)
        #expect(rig.releases.map { $0?.pin } == [.center])
        rig.driver.run()
        #expect(rig.origin == CGPoint(x: 400, y: 300))
        #expect(rig.haptics == 1)
        #expect(rig.settles == 1)
    }

    @Test func aThrowOntoTheNextDisplayLandsOnOneOfItsPins() throws {
        let second = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let rig = MoverRig(origin: CGPoint(x: 700, y: 100), screens: [MoverRig.screen, second])
        rig.flick(dx: 30, dy: 0)
        let snap = try #require(rig.releases.first ?? nil)
        #expect(snap.visibleFrame == second)
        #expect(SnapProjection.targets(size: rig.window.frame.size, visibleFrame: second).contains { $0.pin == snap.pin && $0.origin == snap.origin })
        rig.driver.run()
        #expect(rig.origin == snap.origin)
        #expect(second.contains(rig.window.frame))
        #expect(rig.haptics == 1)
    }

    @Test func underTheMenuBarItSnapsOnlyAlongTheTop() {
        let rig = MoverRig(origin: CGPoint(x: 700, y: 100))
        rig.mover.snapPins = { PinPosition.rows[0] }
        rig.drop(dx: 0, dy: 0)
        #expect(rig.releases.map { $0?.pin } == [.topRight])
        rig.driver.run()
        #expect(rig.origin == CGPoint(x: 784, y: 584))
    }

    @Test func aThrowCarriesItsSpeedIntoTheSpring() {
        let rig = MoverRig(origin: CGPoint(x: 500, y: 300))
        rig.throwTowardTopRight()
        let released = rig.origin
        // Two frames in, a spring starting from rest would have covered about
        // 13 pt across and 18 pt up; one carrying the throw covers about 48 and 42.
        rig.driver.frames(3)
        #expect(rig.origin.x - released.x > 30)
        #expect(rig.origin.y - released.y > 30)
    }

    @Test func droppedWithSnappingOffItStaysWhereItWasLetGo() {
        let rig = MoverRig(origin: CGPoint(x: 300, y: 300), snaps: false)
        rig.press(at: CGPoint(x: 350, y: 350))
        rig.drag(to: CGPoint(x: 420, y: 380))
        rig.release()
        #expect(!rig.driver.isRunning)
        #expect(rig.origin == CGPoint(x: 370, y: 330))
        #expect(rig.settles == 1)
        // Unpinned, with no momentum and no haptic.
        #expect(rig.releases == [nil])
        #expect(rig.haptics == 0)
    }

    @Test func thrownWithSnappingOffItStillStopsWhereItWasLetGo() {
        let rig = MoverRig(origin: CGPoint(x: 300, y: 300), snaps: false)
        rig.throwTowardTopRight()
        let released = rig.origin
        #expect(!rig.driver.isRunning)
        #expect(rig.origin == released)
        #expect(rig.releases == [nil])
        #expect(rig.haptics == 0)
    }

    @Test func droppedPastAnEdgeItComesBackInside() {
        let rig = MoverRig(origin: CGPoint(x: 100, y: 300), snaps: false)
        rig.press(at: CGPoint(x: 150, y: 350))
        rig.drag(to: CGPoint(x: 20, y: 350))
        #expect(rig.origin.x < 0)
        rig.release(after: 0.5)
        #expect(rig.driver.isRunning)
        rig.driver.run()
        #expect(rig.origin == CGPoint(x: 0, y: 300))
        #expect(rig.settles == 1)
    }

    @Test func grabbingItInFlightCatchesItWhereItIs() {
        let rig = MoverRig(origin: CGPoint(x: 500, y: 300))
        rig.throwTowardTopRight()
        rig.driver.frames(6)
        let caught = rig.origin
        #expect(caught != CGPoint(x: 784, y: 584))

        rig.press(at: CGPoint(x: caught.x + 40, y: caught.y + 40))
        rig.drag(to: CGPoint(x: caught.x + 45, y: caught.y + 40))
        // It stops under the pointer instead of jumping by the press's travel.
        #expect(!rig.driver.isRunning)
        #expect(rig.origin == caught)
        rig.drag(to: CGPoint(x: caught.x + 55, y: caught.y + 40))
        #expect(rig.origin == CGPoint(x: caught.x + 10, y: caught.y))
        // The throw it caught never landed, so it never tapped.
        #expect(rig.haptics == 0)
    }

    @Test func aSizeChangeSpringsTogetherWithThePosition() {
        let rig = MoverRig(origin: CGPoint(x: 300, y: 300))
        let target = CGRect(x: 200, y: 400, width: 320, height: 320)
        var completions = 0
        rig.mover.settle(to: target, parameters: Motion.smoothSpring) { completions += 1 }
        #expect(rig.mover.isResizing)

        rig.driver.frames(6)
        let midway = rig.window.frame
        #expect(midway.width > 200 && midway.width < 320)
        #expect(midway.minX < 300 && midway.minX > 200)
        #expect(midway.minY > 300 && midway.minY < 400)

        rig.driver.run()
        #expect(rig.window.frame == target)
        #expect(!rig.mover.isMoving)
        #expect(completions == 1)
        #expect(rig.settles == 1)
    }

    /// Sent to Echo again while a short style still shrinks back from its
    /// square (⌘2, Esc, ⌘2), the player remembers the size it's shrinking to,
    /// not the size it was caught at, so the next Esc brings it back to where
    /// it started.
    @Test func caughtMidShrinkItRemembersTheSizeItWasHeadingFor() {
        let rig = MoverRig(origin: CGPoint(x: 300, y: 300))
        let start = rig.window.frame
        rig.window.setFrame(CGRect(x: 300, y: 300, width: 480, height: 480), display: false)
        rig.mover.settle(to: start, parameters: Motion.smoothSpring)

        rig.driver.frames(6)
        let caught = rig.window.frame
        #expect(caught.width > start.width && caught.width < 480)
        #expect(rig.mover.resizeDestination == start)
        #expect(PlayerExpansion.restoreSize(frame: caught, heading: rig.mover.resizeDestination) == start.size)

        rig.driver.run()
        #expect(rig.mover.resizeDestination == nil)
        #expect(PlayerExpansion.restoreSize(frame: rig.window.frame, heading: rig.mover.resizeDestination) == start.size)
    }

    /// A move that keeps the size isn't on its way to a new one.
    @Test func aMoveAloneHeadsForNoNewSize() {
        let rig = MoverRig(origin: CGPoint(x: 300, y: 300))
        rig.mover.settle(to: CGPoint(x: 600, y: 500), parameters: Motion.smoothSpring)
        rig.driver.frames(6)
        #expect(rig.mover.isMoving)
        #expect(rig.mover.resizeDestination == nil)
    }
}
