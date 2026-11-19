import CoreGraphics
import HumCore
@testable import HumUI
import Testing

@Suite("Pins")
struct PinPlacementTests {
    static let plain = CGRect(x: 0, y: 0, width: 1000, height: 800)
    /// A 1440 × 900 laptop screen under a 25 pt menu bar, with a 70 pt Dock
    /// along the bottom.
    static let laptop = CGRect(x: 0, y: 70, width: 1440, height: 805)
    /// The same screen with the Dock on the left.
    static let dockLeft = CGRect(x: 64, y: 0, width: 1376, height: 875)
    /// A second display to the left of the main one.
    static let leftDisplay = CGRect(x: -1920, y: 0, width: 1920, height: 1055)

    static let displays = [plain, laptop, dockLeft, leftDisplay]
    static let square = CGSize(width: 280, height: 280)
    static let titleBar = CGSize(width: 300, height: 72)

    @Test func theNinePinsSitSixteenPointsInAndCenterAtTheCenter() {
        let size = CGSize(width: 200, height: 200)
        let origins = PinPosition.allCases.map { PlacementResolver.frame(for: $0, size: size, in: Self.plain).origin }
        #expect(origins == [
            CGPoint(x: 16, y: 584), CGPoint(x: 400, y: 584), CGPoint(x: 784, y: 584),
            CGPoint(x: 16, y: 300), CGPoint(x: 400, y: 300), CGPoint(x: 784, y: 300),
            CGPoint(x: 16, y: 16), CGPoint(x: 400, y: 16), CGPoint(x: 784, y: 16),
        ])
    }

    @Test(arguments: PinPlacementTests.displays)
    func everyPinKeepsClearOfTheMenuBarAndTheDock(_ visible: CGRect) {
        for size in [Self.square, Self.titleBar] {
            for pin in PinPosition.allCases {
                let frame = PlacementResolver.frame(for: pin, size: size, in: visible)
                #expect(frame.size == size, "\(pin)")
                #expect(visible.contains(frame), "\(pin)")
                switch pin.column {
                case -1: #expect(frame.minX == visible.minX + 16, "\(pin)")
                case 0: #expect(abs(frame.midX - visible.midX) <= 0.5, "\(pin)")
                default: #expect(frame.maxX == visible.maxX - 16, "\(pin)")
                }
                switch pin.row {
                case 1: #expect(frame.maxY == visible.maxY - 16, "\(pin)")
                case 0: #expect(abs(frame.midY - visible.midY) <= 0.5, "\(pin)")
                default: #expect(frame.minY == visible.minY + 16, "\(pin)")
                }
            }
        }
    }

    @Test func onALaptopTheCornersFollowTheVisibleFrame() {
        #expect(PlacementResolver.frame(for: .topRight, size: Self.square, in: Self.laptop).origin == CGPoint(x: 1144, y: 579))
        #expect(PlacementResolver.frame(for: .bottomLeft, size: Self.square, in: Self.laptop).origin == CGPoint(x: 16, y: 86))
        #expect(PlacementResolver.frame(for: .center, size: Self.square, in: Self.laptop).origin == CGPoint(x: 580, y: 333))
        #expect(PlacementResolver.frame(for: .left, size: Self.square, in: Self.dockLeft).minX == 80)
    }

    @Test func aDisplayTooSmallStillHoldsThePlayer() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 200)
        for pin in PinPosition.allCases {
            let frame = PlacementResolver.frame(for: pin, size: Self.square, in: tiny)
            #expect(tiny.contains(frame), "\(pin)")
            #expect(frame.width == frame.height, "\(pin)")
        }
    }

    @Test func eachPinHoldsTheMatchingPointOfTheWindow() {
        #expect(PlacementResolver.anchor(of: .topLeft) == CGPoint(x: 0, y: 1))
        #expect(PlacementResolver.anchor(of: .top) == CGPoint(x: 0.5, y: 1))
        #expect(PlacementResolver.anchor(of: .center) == CGPoint(x: 0.5, y: 0.5))
        #expect(PlacementResolver.anchor(of: .right) == CGPoint(x: 1, y: 0.5))
        #expect(PlacementResolver.anchor(of: .bottomRight) == CGPoint(x: 1, y: 0))
    }

    /// The point a pin holds, in screen coordinates.
    private func pinnedPoint(_ frame: CGRect, _ pin: PinPosition) -> CGPoint {
        let anchor = PlacementResolver.anchor(of: pin)
        return CGPoint(x: frame.minX + frame.width * anchor.x, y: frame.minY + frame.height * anchor.y)
    }

    private func isClose(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) <= 0.5 && abs(a.y - b.y) <= 0.5
    }

    @Test(arguments: PinPosition.allCases)
    func resizingHoldsThePinnedPoint(_ pin: PinPosition) {
        for visible in Self.displays {
            let start = PlacementResolver.frame(for: pin, size: Self.square, in: visible)
            for side in [168.0, 360, 640] {
                let resized = PlacementResolver.frame(resizing: start, to: CGSize(width: side, height: side), pin: pin, in: visible)
                #expect(resized.size == CGSize(width: side, height: side))
                #expect(isClose(pinnedPoint(resized, pin), pinnedPoint(start, pin)), "\(pin) at \(side)")
            }
        }
    }

    /// Switching styles changes the window's shape: from Art Only's square to
    /// Title's bar and to Big Art's portrait, the pinned point stays put.
    @Test(arguments: PinPosition.allCases)
    func aShapeChangeHoldsThePinnedPoint(_ pin: PinPosition) {
        let shapes = [Self.square, Self.titleBar, CGSize(width: 260, height: 392), CGSize(width: 240, height: 44)]
        for visible in Self.displays {
            var frame = PlacementResolver.frame(for: pin, size: Self.square, in: visible)
            let held = pinnedPoint(frame, pin)
            for shape in shapes {
                frame = PlacementResolver.frame(resizing: frame, to: shape, pin: pin, in: visible)
                #expect(frame.size == shape)
                #expect(isClose(pinnedPoint(frame, pin), held), "\(pin) as \(shape)")
            }
        }
    }

    @Test func anUnpinnedWindowHoldsItsNearestThird() {
        // Dropped in the top-right third, not at a pin.
        let dropped = CGRect(x: 690, y: 480, width: 280, height: 280)
        let grown = PlacementResolver.frame(resizing: dropped, to: CGSize(width: 300, height: 300), pin: nil, in: Self.plain)
        #expect(grown.maxX == dropped.maxX)
        #expect(grown.maxY == dropped.maxY)
        // Dropped in the middle, it grows from its center.
        let middle = CGRect(x: 360, y: 260, width: 280, height: 280)
        let bar = PlacementResolver.frame(resizing: middle, to: Self.titleBar, pin: nil, in: Self.plain)
        #expect(bar.midX == middle.midX)
        #expect(bar.midY == middle.midY)
    }

    // MARK: Memory

    private func display(_ visible: CGRect = plain) -> DisplayInfo {
        DisplayInfo(id: "display-a", visibleFrame: visible)
    }

    @Test func aDisplayWithNoPlacementStartsAtTheInitialPin() {
        #expect(PinPosition.initial == .topRight)
        #expect(PlacementResolver.pin(for: nil, size: Self.square, on: display()) == .topRight)
        #expect(PlacementResolver.frame(for: nil, size: Self.square, on: display())
            == PlacementResolver.frame(for: .topRight, size: Self.square, in: Self.plain))
    }

    @Test func aPinnedPlacementComesBackAtItsPin() {
        let frame = PlacementResolver.frame(for: .left, size: Self.square, in: Self.plain)
        let placement = PlacementResolver.placement(for: frame, on: display(), surface: .now, pin: .left)
        #expect(placement.pin == .left)
        #expect(PlacementResolver.pin(for: placement, size: Self.square, on: display()) == .left)
        #expect(PlacementResolver.frame(for: placement, size: Self.square, on: display()) == frame)
    }

    /// The Dock moved or the resolution changed: a pinned player is still
    /// at its pin, not at the old offset.
    @Test func aPinnedPlacementFollowsTheVisibleFrame() {
        let placement = WindowPlacement(offsetX: 704, offsetY: 16, side: 280, pin: .bottomRight)
        let moved = PlacementResolver.frame(for: placement, size: Self.square, on: display(Self.laptop))
        #expect(moved == PlacementResolver.frame(for: .bottomRight, size: Self.square, in: Self.laptop))
        #expect(moved.minY == Self.laptop.minY + 16)
    }

    /// Before pins, the player started 24 pt in from the top-right corner;
    /// that and anything else within a few points of a pin is pinned there.
    @Test func oldPlacementsNearAPinArePinnedThere() {
        let oldDefault = WindowPlacement(offsetX: 1000 - 24 - 280, offsetY: 800 - 24 - 280, side: 280)
        #expect(PlacementResolver.pin(for: oldDefault, size: Self.square, on: display()) == .topRight)
        let nearBottomLeft = WindowPlacement(offsetX: 10, offsetY: 22, side: 280)
        #expect(PlacementResolver.pin(for: nearBottomLeft, size: Self.square, on: display()) == .bottomLeft)
        let nearCenter = WindowPlacement(offsetX: 365, offsetY: 255, side: 280)
        #expect(PlacementResolver.pin(for: nearCenter, size: Self.square, on: display()) == .center)
    }

    @Test func oldPlacementsElsewhereStayUnpinnedWhereTheyWere() {
        let elsewhere = WindowPlacement(offsetX: 300, offsetY: 150, side: 280)
        #expect(PlacementResolver.pin(for: elsewhere, size: Self.square, on: display()) == nil)
        #expect(PlacementResolver.frame(for: elsewhere, size: Self.square, on: display()).origin == CGPoint(x: 300, y: 150))
        // Just past the tolerance is still elsewhere.
        let justPast = WindowPlacement(offsetX: 1000 - 25 - 280, offsetY: 800 - 16 - 280, side: 280)
        #expect(PlacementResolver.pin(for: justPast, size: Self.square, on: display()) == nil)
    }

    @Test func underTheMenuBarEachColumnTucksAtItsTop() {
        for row in PinPosition.rows {
            #expect(row.map(\.tuckPosition) == PinPosition.rows[0])
        }
    }
}
