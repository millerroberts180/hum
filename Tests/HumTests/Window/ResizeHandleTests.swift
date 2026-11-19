import AppKit
import HumCore
@testable import HumUI
import Testing

@Suite("Resize handles")
struct ResizeHandleTests {
    private func resized(
        _ start: NSRect,
        _ position: ResizeHandleView.Position,
        dragX: CGFloat = 0,
        dragY: CGFloat = 0,
        style: PlayerStyleID
    ) -> NSRect {
        ResizeHandleView.resizedFrame(from: start, position: position, dragX: dragX, dragY: dragY, shape: style.shape)
    }

    @Test func aSquareCornerFollowsTheLargerDragAndHoldsTheOppositeCorner() {
        let start = NSRect(x: 100, y: 100, width: 280, height: 280)
        // Dragged 40 right and 10 down.
        let grown = resized(start, .bottomRight, dragX: 40, dragY: -10, style: .artOnly)
        #expect(grown.size == NSSize(width: 320, height: 320))
        #expect(grown.minX == start.minX)
        #expect(grown.maxY == start.maxY)
    }

    @Test func aLeadingEdgeHoldsTheTrailingOne() {
        let start = NSRect(x: 100, y: 100, width: 280, height: 280)
        let grown = resized(start, .left, dragX: -30, style: .artOnly)
        #expect(grown.width == 310)
        #expect(grown.maxX == start.maxX)
    }

    @Test func aSquareStaysInsideItsStylesRange() {
        let start = NSRect(x: 100, y: 100, width: 280, height: 280)
        #expect(resized(start, .topRight, dragX: -500, style: .artOnly).width == 168)
        #expect(resized(start, .topRight, dragX: 900, style: .artOnly).width == 640)
    }

    @Test(arguments: [PlayerStyleID.title, .text, .strip])
    func aBarChangesOnlyItsWidth(_ style: PlayerStyleID) {
        let height = CGFloat(StyleGeometry.defaultSize(for: style).height)
        let start = NSRect(x: 100, y: 500, width: 260, height: height)
        // Pulling the bottom-right corner down as well as right moves only the width.
        let grown = resized(start, .bottomRight, dragX: 40, dragY: -60, style: style)
        #expect(grown.width == 300)
        #expect(grown.height == height)
        #expect(grown.maxY == start.maxY)
        #expect(grown.minX == start.minX)
        // Its range is its own.
        let widths = style.shape.widths
        #expect(resized(start, .right, dragX: 900, style: style).width == CGFloat(widths.upperBound))
        #expect(resized(start, .right, dragX: -900, style: style).width == CGFloat(widths.lowerBound))
    }

    @Test func bigArtKeepsItsControlsUnderTheCover() {
        let start = NSRect(x: 100, y: 100, width: 280, height: 441)
        let grown = resized(start, .right, dragX: 40, style: .bigArt)
        #expect(grown.size == NSSize(width: 320, height: 481))
        #expect(grown.maxY == start.maxY)
        #expect(resized(start, .right, dragX: 900, style: .bigArt).size == NSSize(width: 420, height: 581))
        #expect(resized(start, .right, dragX: -900, style: .bigArt).size == NSSize(width: 220, height: 381))
    }

    /// Wide's width drags and its height follows at half of it (§7): a
    /// vertical drag does nothing, and the edge across from the handle stays.
    @Test func wideFollowsOnlyTheSidewaysDrag() {
        let start = NSRect(x: 100, y: 500, width: 360, height: 180)
        // The trailing edge out: the leading edge and the top hold.
        let wider = resized(start, .right, dragX: 80, style: .wide)
        #expect(wider == NSRect(x: 100, y: 460, width: 440, height: 220))
        // The leading edge in: the trailing edge and the top hold.
        let narrower = resized(start, .left, dragX: 40, style: .wide)
        #expect(narrower == NSRect(x: 140, y: 520, width: 320, height: 160))
        // A corner pulled down and out takes only the sideways part.
        let corner = resized(start, .bottomRight, dragX: 40, dragY: -200, style: .wide)
        #expect(corner.size == NSSize(width: 400, height: 200))
        #expect(corner.maxY == start.maxY)
        // Up and down alone changes nothing.
        #expect(resized(start, .bottomRight, dragY: -200, style: .wide) == start)
        // A top corner holds the bottom, so the window grows up.
        let fromTop = resized(start, .topRight, dragX: 40, dragY: 200, style: .wide)
        #expect(fromTop.size == NSSize(width: 400, height: 200))
        #expect(fromTop.minY == start.minY)
        // Its range is its own.
        #expect(resized(start, .right, dragX: 900, style: .wide).size == NSSize(width: 520, height: 260))
        #expect(resized(start, .right, dragX: -900, style: .wide).size == NSSize(width: 320, height: 160))
    }
}

/// The system's own resize, from the window's edge outside the handles,
/// which `PlayerWindowController` answers as the panel's delegate: the
/// window keeps its style's shape and range (§7) whichever way it's pulled.
@MainActor
@Suite("System resize")
struct SystemResizeTests {
    /// What a player in `style` answers when the system pulls its window
    /// from `current` to `proposed`.
    func answer(_ style: PlayerStyleID, from current: NSSize, to proposed: NSSize) -> NSSize {
        let settings = SettingsStore(fileURL: nil)
        settings.appearance.style = style
        let player = PlayerWindowController(
            store: NowPlayingStore(sources: []),
            settings: settings,
            launchOptions: LaunchOptions(),
            actions: PlayerActions()
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: current),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        return player.windowWillResize(window, to: proposed)
    }

    /// A drag on macOS 15, 360×180 pulled out to 440 wide, came to 440×180.
    @Test func wideKeepsItsHeightAtHalfItsWidth() {
        let start = NSSize(width: 360, height: 180)
        #expect(answer(.wide, from: start, to: NSSize(width: 440, height: 180)) == NSSize(width: 440, height: 220))
        #expect(answer(.wide, from: start, to: NSSize(width: 330, height: 180)) == NSSize(width: 330, height: 165))
        // Up or down alone changes nothing.
        #expect(answer(.wide, from: start, to: NSSize(width: 360, height: 260)) == start)
        #expect(answer(.wide, from: start, to: NSSize(width: 900, height: 180)) == NSSize(width: 520, height: 260))
        #expect(answer(.wide, from: start, to: NSSize(width: 44, height: 44)) == NSSize(width: 320, height: 160))
    }

    @Test(arguments: [PlayerStyleID.title, .text, .strip])
    func aBarKeepsItsHeight(style: PlayerStyleID) throws {
        guard case .bar(let height, let widths) = style.shape else {
            Issue.record("\(style) isn't a bar")
            return
        }
        let start = NSSize(width: widths.lowerBound + 20, height: height)
        #expect(answer(style, from: start, to: NSSize(width: start.width + 40, height: height + 40))
            == NSSize(width: start.width + 40, height: height))
        #expect(answer(style, from: start, to: NSSize(width: start.width, height: height + 40)) == start)
        #expect(answer(style, from: start, to: NSSize(width: 900, height: height)) == NSSize(width: widths.upperBound, height: height))
        #expect(answer(style, from: start, to: NSSize(width: 44, height: 44)) == NSSize(width: widths.lowerBound, height: height))
    }

    @Test func bigArtFollowsItsWidthOrItsHeight() {
        let start = NSSize(width: 280, height: 441)
        #expect(answer(.bigArt, from: start, to: NSSize(width: 320, height: 441)) == NSSize(width: 320, height: 481))
        // Pulled only up or down, the width follows, as with its handles.
        #expect(answer(.bigArt, from: start, to: NSSize(width: 280, height: 521)) == NSSize(width: 360, height: 521))
        #expect(answer(.bigArt, from: start, to: NSSize(width: 280, height: 100)) == NSSize(width: 220, height: 381))
        #expect(answer(.bigArt, from: start, to: NSSize(width: 900, height: 900)) == NSSize(width: 420, height: 581))
    }

    /// The panel's minimum lets the system go down to 44; a square stops at
    /// its own range.
    @Test func aSquareStaysSquareInItsRange() {
        let start = NSSize(width: 300, height: 300)
        #expect(answer(.artOnly, from: start, to: NSSize(width: 340, height: 340)) == NSSize(width: 340, height: 340))
        #expect(answer(.artOnly, from: start, to: NSSize(width: 340, height: 300)) == NSSize(width: 340, height: 340))
        #expect(answer(.artOnly, from: start, to: NSSize(width: 300, height: 360)) == NSSize(width: 360, height: 360))
        #expect(answer(.artOnly, from: start, to: NSSize(width: 60, height: 60)) == NSSize(width: 168, height: 168))
        #expect(answer(.artOnly, from: start, to: NSSize(width: 900, height: 900)) == NSSize(width: 640, height: 640))
    }
}
