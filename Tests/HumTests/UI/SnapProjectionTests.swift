import CoreGraphics
import HumCore
@testable import HumUI
import Testing

@Suite("Snap projection")
struct SnapProjectionTests {
    static let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
    static let size = CGSize(width: 200, height: 200)

    @Test func aThrowTravelsLikeAScrollFlick() {
        #expect(SnapProjection.distance(velocity: 0) == 0)
        #expect(abs(SnapProjection.distance(velocity: 1000) - 499) < 0.001)
        #expect(SnapProjection.distance(velocity: -1000) == -SnapProjection.distance(velocity: 1000))
    }

    @Test func targetsAreTheNinePinsInOrder() {
        let targets = SnapProjection.targets(size: Self.size, visibleFrame: Self.display)
        #expect(targets.map(\.pin) == PinPosition.allCases)
        #expect(targets.map(\.origin) == [
            CGPoint(x: 16, y: 584), CGPoint(x: 400, y: 584), CGPoint(x: 784, y: 584),
            CGPoint(x: 16, y: 300), CGPoint(x: 400, y: 300), CGPoint(x: 784, y: 300),
            CGPoint(x: 16, y: 16), CGPoint(x: 400, y: 16), CGPoint(x: 784, y: 16),
        ])
    }

    @Test func targetsCanBeLimitedToTheTopRow() {
        let targets = SnapProjection.targets(size: Self.size, visibleFrame: Self.display, among: PinPosition.rows[0])
        #expect(targets.map(\.pin) == [.topLeft, .top, .topRight])
        #expect(targets.map(\.origin) == [CGPoint(x: 16, y: 584), CGPoint(x: 400, y: 584), CGPoint(x: 784, y: 584)])
    }

    @Test func aDropWithoutVelocityGoesToTheNearestPin() {
        let snap = SnapProjection.target(
            origin: CGPoint(x: 700, y: 100),
            size: Self.size,
            velocity: .zero,
            visibleFrames: [Self.display]
        )
        #expect(snap == .init(pin: .bottomRight, origin: CGPoint(x: 784, y: 16), visibleFrame: Self.display))
    }

    @Test func aDropNearTheMiddleGoesToCenter() {
        let snap = SnapProjection.target(
            origin: CGPoint(x: 430, y: 270),
            size: Self.size,
            velocity: .zero,
            visibleFrames: [Self.display]
        )
        #expect(snap?.pin == .center)
        #expect(snap?.origin == CGPoint(x: 400, y: 300))
    }

    @Test func aDropNearAnEdgeMidpointGoesThere() {
        let snap = SnapProjection.target(
            origin: CGPoint(x: 60, y: 330),
            size: Self.size,
            velocity: .zero,
            visibleFrames: [Self.display]
        )
        #expect(snap?.pin == .left)
        #expect(snap?.origin == CGPoint(x: 16, y: 300))
    }

    @Test func aThrowLandsWhereItWasHeading() {
        // Released near the bottom-left corner, thrown right and up.
        let snap = SnapProjection.target(
            origin: CGPoint(x: 40, y: 40),
            size: Self.size,
            velocity: CGVector(dx: 1500, dy: 1200),
            visibleFrames: [Self.display]
        )
        #expect(snap == .init(pin: .topRight, origin: CGPoint(x: 784, y: 584), visibleFrame: Self.display))
    }

    @Test func aShortThrowUpwardStopsAtTheMiddleRow() {
        // From the bottom-right corner, a flick up that travels about 250 pt.
        let snap = SnapProjection.target(
            origin: CGPoint(x: 784, y: 16),
            size: Self.size,
            velocity: CGVector(dx: 0, dy: 500),
            visibleFrames: [Self.display]
        )
        #expect(snap?.pin == .right)
    }

    @Test func aThrowCanCrossToTheNextDisplay() {
        let second = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let snap = SnapProjection.target(
            origin: CGPoint(x: 700, y: 100),
            size: Self.size,
            velocity: CGVector(dx: 1000, dy: 0),
            visibleFrames: [Self.display, second]
        )
        #expect(snap == .init(pin: .bottomLeft, origin: CGPoint(x: 1016, y: 16), visibleFrame: second))
    }

    @Test func aThrowOntoADisplayAboveUsesItsPins() {
        // A smaller display stacked above, with its own menu bar inset.
        let above = CGRect(x: 200, y: 800, width: 800, height: 575)
        let snap = SnapProjection.target(
            origin: CGPoint(x: 700, y: 500),
            size: Self.size,
            velocity: CGVector(dx: 0, dy: 1400),
            visibleFrames: [Self.display, above]
        )
        #expect(snap?.visibleFrame == above)
        #expect(snap?.pin == .topRight)
        #expect(snap?.origin == CGPoint(x: 784, y: 1159))
    }

    @Test func aThrowOffEveryDisplayUsesTheNearestOne() {
        let snap = SnapProjection.target(
            origin: CGPoint(x: 700, y: 100),
            size: Self.size,
            velocity: CGVector(dx: 4000, dy: 0),
            visibleFrames: [Self.display]
        )
        #expect(snap?.pin == .bottomRight)
        #expect(snap?.origin == CGPoint(x: 784, y: 16))
    }

    @Test func underTheMenuBarOnlyTheTopRowIsATarget() {
        let snap = SnapProjection.target(
            origin: CGPoint(x: 700, y: 100),
            size: Self.size,
            velocity: .zero,
            visibleFrames: [Self.display],
            among: PinPosition.rows[0]
        )
        #expect(snap?.pin == .topRight)
        #expect(snap?.origin == CGPoint(x: 784, y: 584))
    }

    @Test func noDisplaysOrPinsMeansNoTarget() {
        #expect(SnapProjection.target(origin: .zero, size: Self.size, velocity: .zero, visibleFrames: []) == nil)
        #expect(SnapProjection.target(origin: .zero, size: Self.size, velocity: .zero, visibleFrames: [Self.display], among: []) == nil)
    }

    @Test func dragsPastTheEdgeMeetResistance() {
        let inside = CGPoint(x: 100, y: 100)
        #expect(SnapProjection.rubberBanded(origin: inside, size: Self.size, bounds: Self.display) == inside)

        let pastLeft = SnapProjection.rubberBanded(origin: CGPoint(x: -100, y: 100), size: Self.size, bounds: Self.display)
        #expect(pastLeft.x < 0)
        #expect(pastLeft.x > -100)
        #expect(pastLeft.y == 100)

        // The second hundred points past the edge move it less than the first.
        let further = SnapProjection.rubberBanded(origin: CGPoint(x: -200, y: 100), size: Self.size, bounds: Self.display)
        #expect(further.x < pastLeft.x)
        #expect(pastLeft.x - further.x < -pastLeft.x)

        let pastTop = SnapProjection.rubberBanded(origin: CGPoint(x: 100, y: 700), size: Self.size, bounds: Self.display)
        #expect(pastTop.y > 600)
        #expect(pastTop.y < 700)
    }
}
