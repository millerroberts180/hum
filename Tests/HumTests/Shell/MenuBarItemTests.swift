import AppKit
import HumCore
@testable import HumUI
import Testing

@Suite("Menu Bar item")
struct MenuBarItemTests {
    typealias Layout = MenuBarPlayerItemView.Layout

    @Test func thePiecesSitInOrderSixPointsApart() throws {
        let frames = Layout.frames(titleWidth: 100, height: 22, showsPlayPause: true, showsNext: true)
        #expect(frames.cover == CGRect(x: Layout.leading, y: 2, width: 18, height: 18))
        #expect(frames.title.minX == frames.cover.maxX + 6)
        #expect(frames.title.width == 100)
        let playPause = try #require(frames.playPause)
        let next = try #require(frames.next)
        #expect(playPause.minX == frames.title.maxX + 6)
        #expect(next.minX == playPause.maxX + 6)
        #expect(frames.width == next.maxX)
    }

    @Test func theCoverIsEighteenPointsWithCornersOfFour() {
        #expect(Layout.coverSide == 18)
        #expect(Layout.coverRadius == 4)
    }

    @Test func eachGlyphHasATwentyTwoPointHitAreaTheItemsHeight() {
        let frames = Layout.frames(titleWidth: 80, height: 24, showsPlayPause: true, showsNext: true)
        for frame in [frames.playPause, frames.next] {
            #expect(frame?.width == 22)
            #expect(frame?.height == 24)
            #expect(frame?.minY == 0)
        }
    }

    @Test func aLongTitleStopsAt160Points() {
        let frames = Layout.frames(titleWidth: 420, height: 22, showsPlayPause: true, showsNext: true)
        #expect(frames.title.width == 160)
        let short = Layout.frames(titleWidth: 420, height: 22, showsPlayPause: false, showsNext: false)
        #expect(short.width == short.title.maxX)
        #expect(frames.width == short.width + 2 * (6 + 22))
    }

    @Test func glyphsTheSourceCantUseLeaveNoGap() {
        let frames = Layout.frames(titleWidth: 50, height: 22, showsPlayPause: true, showsNext: false)
        #expect(frames.next == nil)
        #expect(frames.width == frames.playPause?.maxX)
    }

    @Test func voiceOverHearsHumThenTheSong() {
        #expect(MenuBarPlayerItemView.accessibilityLabel(title: "Song", artist: "Band") == "Hum, Song by Band")
        #expect(MenuBarPlayerItemView.accessibilityLabel(title: "Song", artist: "") == "Hum, Song")
    }

    @Test @MainActor func theGlyphsSayWhatTheyDo() throws {
        let view = MenuBarPlayerItemView()
        let content = MenuBarPlayerItemView.Content(title: "Song", artist: "Band", isPlaying: true, canPlayPause: true, canSkip: true)
        view.update(content, artwork: nil)
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        #expect(buttons.map { $0.accessibilityLabel() ?? "" } == ["Pause", "Next Track"])
        var paused = content
        paused.isPlaying = false
        view.update(paused, artwork: nil)
        #expect(buttons.first?.accessibilityLabel() == "Play")
        // The cover and the title are read as part of the item's own label.
        let others = view.subviews.filter { !($0 is NSButton) }
        #expect(others.allSatisfy { !$0.isAccessibilityElement() })
    }

    @Test @MainActor func glyphsTheSourceCantUseAreHidden() {
        let view = MenuBarPlayerItemView()
        let all = MenuBarPlayerItemView.Content(title: "Song", artist: "Band", isPlaying: true, canPlayPause: true, canSkip: true)
        view.update(all, artwork: nil)
        let wide = view.preferredWidth
        var noSkip = all
        noSkip.canSkip = false
        view.update(noSkip, artwork: nil)
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        #expect(buttons.map(\.isHidden) == [false, true])
        #expect(view.preferredWidth == wide - 6 - 22)
    }

    @Test @MainActor func onlyTheGlyphsTakeClicks() {
        let view = MenuBarPlayerItemView()
        view.update(.init(title: "Song", artist: "Band", isPlaying: true, canPlayPause: true, canSkip: true), artwork: nil)
        // In a button-sized container, as in the status item. Everything is
        // centered on the item's middle line, so flipping doesn't move it.
        let container = NSView(frame: CGRect(x: 0, y: 0, width: view.preferredWidth, height: 22))
        view.frame = container.bounds
        container.addSubview(view)
        view.layout()
        let middle: CGFloat = 11
        // Over the cover and the title, the click goes to the status item's button.
        for piece in view.subviews where !(piece is NSButton) {
            #expect(view.hitTest(CGPoint(x: piece.frame.midX, y: middle)) == nil)
        }
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        #expect(buttons.count == 2)
        for button in buttons {
            #expect(view.hitTest(CGPoint(x: button.frame.midX, y: middle)) === button)
        }
    }

    /// The item fills the status item's button as its length grows from the
    /// mark's square, so the cover sits on the bar's middle line, not half
    /// above it.
    @Test @MainActor func theItemFillsItsButtonAsItGrows() throws {
        let button = NSView(frame: CGRect(x: 0, y: 0, width: 22, height: 24))
        let view = MenuBarPlayerItemView()
        view.embed(in: button)
        view.update(.init(title: "Song", artist: "Band", isPlaying: true, canPlayPause: true, canSkip: true), artwork: nil)
        button.setFrameSize(NSSize(width: view.preferredWidth, height: 24))
        view.layoutSubtreeIfNeeded()
        #expect(view.frame == button.bounds)
        let cover = try #require(view.subviews.first { $0 is NSImageView })
        #expect(cover.frame == CGRect(x: Layout.leading, y: 3, width: 18, height: 18))
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        #expect(buttons.allSatisfy { $0.frame.height == 24 })
    }

    /// A title shorter than 160 pt shows whole, its text 6 pt after the
    /// cover: the label's frame takes in the 2 pt its text sits inside on
    /// each side.
    @Test @MainActor func aShortTitleShowsWhole() throws {
        let button = NSView(frame: CGRect(x: 0, y: 0, width: 22, height: 24))
        let view = MenuBarPlayerItemView()
        view.embed(in: button)
        view.update(.init(title: "Low Tide Radio", artist: "Marlow Fields", isPlaying: true, canPlayPause: true, canSkip: true), artwork: nil)
        button.setFrameSize(NSSize(width: view.preferredWidth, height: 24))
        view.layoutSubtreeIfNeeded()
        let title = try #require(view.subviews.lazy.compactMap { $0 as? NSTextField }.first)
        let cell = try #require(title.cell)
        #expect(title.frame.width >= cell.cellSize.width)
        let cover = try #require(view.subviews.first { $0 is NSImageView })
        #expect(title.alignmentRect(forFrame: title.frame).minX == cover.frame.maxX + 6)
    }

    // MARK: The mark

    /// The menu bar draws the same small cut the icon uses below 32 px: every
    /// point of `vibratoPath(small: true)`, in order.
    @Test func theMarkIsTheSmallCutOfTheIcon() throws {
        let script = try String(
            contentsOf: AppBundleResourceTests.repository.appendingPathComponent("scripts/make-icon.swift"),
            encoding: .utf8
        )
        let small = try #require(script.range(of: "if small {"))
        let large = try #require(script.range(of: "} else {", range: small.upperBound..<script.endIndex))
        let code = script[small.upperBound..<large.lowerBound]
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        // Numbers only, not the digits in names like `control1`.
        let expected = code.matches(of: /[A-Za-z_]\w*|-?\d+(?:\.\d+)?/).compactMap { Double(code[$0.range]) }

        var points: [Double] = []
        HumMark.centerline().applyWithBlock { element in
            let count = switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            default: 0
            }
            // The script names a curve's end point before its controls.
            var curve = (0..<count).map { element.pointee.points[$0] }
            if count == 3 { curve = [curve[2], curve[0], curve[1]] }
            points += curve.flatMap { [Double($0.x), Double($0.y)] }
        }
        #expect(!expected.isEmpty)
        #expect(points == expected)
        #expect(HumMark.lineWidth == 32)
    }

    @Test func theMarkFitsItsSquareWithEvenMargins() {
        for side in [16.0, 18.0, 22.0] {
            let bounds = HumMark.outline(side: side).boundingBoxOfPath
            let square = CGRect(x: 0, y: 0, width: side, height: side)
            #expect(square.contains(bounds), "\(side)")
            // Centered both ways, to well under a point.
            #expect(abs(bounds.midX - side / 2) < 0.05, "\(side)")
            #expect(abs(bounds.midY - side / 2) < 0.05, "\(side)")
            // Wide and short: a line with ripples, not a blob.
            #expect(bounds.width > bounds.height * 2, "\(side)")
        }
    }

    @Test @MainActor func theMarkIsATemplateImage() {
        let image = HumMark.templateImage()
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.accessibilityDescription == "Hum")
        let dimmed = HumMark.templateImage(accessibilityDescription: "Hum, no music app available")
        #expect(dimmed.accessibilityDescription == "Hum, no music app available")
    }

    @Test @MainActor func theMarkDrawsInk() throws {
        let image = HumMark.templateImage(side: 18)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = NSSize(width: 18, height: 18)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        var inked = 0
        for x in 0..<36 {
            for y in 0..<36 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                inked += 1
            }
        }
        // Some of the square, nowhere near all of it.
        #expect(inked > 36 * 36 / 20)
        #expect(inked < 36 * 36 / 3)
        // The middle row crosses the line; the corners are clear.
        #expect((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) == 0)
        #expect((rep.colorAt(x: 35, y: 35)?.alphaComponent ?? 1) == 0)
    }
}
