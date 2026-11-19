import Foundation
import HumCore
@testable import HumUI
import Testing

@Suite("Style window geometry")
struct StyleGeometryTests {
    @Test func eachStyleOpensAtItsOwnSize() {
        #expect(StyleGeometry.defaultSize(for: .artOnly) == PlayerSize(side: 280))
        #expect(StyleGeometry.defaultSize(for: .title) == PlayerSize(width: 300, height: 72))
        #expect(StyleGeometry.defaultSize(for: .text) == PlayerSize(width: 240, height: 44))
        #expect(StyleGeometry.defaultSize(for: .strip) == PlayerSize(width: 320, height: 48))
        #expect(StyleGeometry.defaultSize(for: .wide) == PlayerSize(width: 360, height: 180))
        #expect(StyleGeometry.defaultSize(for: .bigArt) == PlayerSize(width: 280, height: 441))
        // Menu Bar has no window; it answers with Art Only's.
        #expect(StyleGeometry.defaultSize(for: .menuBar) == StyleGeometry.defaultSize(for: .artOnly))
    }

    @Test func eachStyleHasItsShape() {
        #expect(PlayerStyleID.artOnly.shape == .square(sides: 168...640))
        #expect(PlayerStyleID.title.shape == .bar(height: 72, widths: 240...420))
        #expect(PlayerStyleID.text.shape == .bar(height: 44, widths: 180...360))
        #expect(PlayerStyleID.strip.shape == .bar(height: 48, widths: 260...440))
        #expect(PlayerStyleID.wide.shape == .landscape(widths: 320...520, heightRatio: 0.5))
        #expect(PlayerStyleID.bigArt.shape == .portrait(widths: 220...420, controlsHeight: 161))
        #expect(PlayerStyleID.menuBar.shape == PlayerStyleID.artOnly.shape)
        #expect(PlayerStyleID.allCases.filter(\.isBar) == [.title, .text, .strip])
        #expect(PlayerStyleID.allCases.filter(\.isSquare) == [.artOnly, .menuBar])
        #expect(PlayerStyleID.allCases.filter(\.isPortrait) == [.bigArt])
        #expect(PlayerStyleID.allCases.filter(\.isLandscape) == [.wide])
        // Only the width drags for bars and Wide; the height follows.
        #expect(PlayerStyleID.allCases.filter(\.shape.resizesSideways) == [.title, .text, .strip, .wide])
    }

    /// Wide is half as tall as it's wide at every width it takes.
    @Test(arguments: [320.0, 360, 440, 520])
    func wideIsHalfAsTallAsItIsWide(width: Double) {
        #expect(PlayerStyleID.wide.shape.size(width: width) == PlayerSize(width: width, height: width / 2))
        #expect(StyleGeometry.clamp(PlayerSize(width: width, height: 400), for: .wide) == PlayerSize(width: width, height: width / 2))
    }

    @Test func wideStaysInsideItsRange() {
        #expect(StyleGeometry.clamp(PlayerSize(width: 200, height: 100), for: .wide) == PlayerSize(width: 320, height: 160))
        #expect(StyleGeometry.clamp(PlayerSize(width: 900, height: 450), for: .wide) == PlayerSize(width: 520, height: 260))
        #expect(StyleGeometry.clamp(PlayerSize(width: .nan, height: 10), for: .wide) == PlayerSize(width: 360, height: 180))
    }

    @Test func bigArtStaysInsideItsRange() {
        #expect(StyleGeometry.clamp(PlayerSize(width: 200, height: 400), for: .bigArt) == PlayerSize(width: 220, height: 381))
        #expect(StyleGeometry.clamp(PlayerSize(width: 900, height: 900), for: .bigArt) == PlayerSize(width: 420, height: 581))
    }

    @Test(arguments: [
        (PlayerSizePreset.small, PlayerStyleID.artOnly, PlayerSize(side: 200)),
        (.medium, .artOnly, PlayerSize(side: 280)),
        (.large, .artOnly, PlayerSize(side: 400)),
        (.small, .title, PlayerSize(width: 260, height: 72)),
        (.medium, .title, PlayerSize(width: 300, height: 72)),
        (.large, .title, PlayerSize(width: 380, height: 72)),
        (.small, .text, PlayerSize(width: 200, height: 44)),
        (.large, .text, PlayerSize(width: 320, height: 44)),
        (.small, .strip, PlayerSize(width: 280, height: 48)),
        (.large, .strip, PlayerSize(width: 400, height: 48)),
        (.small, .wide, PlayerSize(width: 320, height: 160)),
        (.medium, .wide, PlayerSize(width: 360, height: 180)),
        (.large, .wide, PlayerSize(width: 440, height: 220)),
        (.small, .bigArt, PlayerSize(width: 240, height: 401)),
        (.medium, .bigArt, PlayerSize(width: 280, height: 441)),
        (.large, .bigArt, PlayerSize(width: 360, height: 521)),
    ])
    func presetsFollowTheDesignTable(preset: PlayerSizePreset, style: PlayerStyleID, size: PlayerSize) {
        #expect(preset.size(for: style) == size)
        // And a window of that size reads back as the same preset.
        #expect(PlayerSizePreset(size, style: style) == preset)
    }

    @Test func theMediumPresetIsTheDefaultSize() {
        for style in PlayerStyleID.allCases {
            #expect(PlayerSizePreset.medium.size(for: style) == StyleGeometry.defaultSize(for: style))
        }
    }

    @Test func aSizeReadsAsItsNearestPreset() {
        #expect(PlayerSizePreset(PlayerSize(side: 239), style: .artOnly) == .small)
        // Halfway between Small and Medium goes to the larger.
        #expect(PlayerSizePreset(PlayerSize(side: 240), style: .artOnly) == .medium)
        #expect(PlayerSizePreset(PlayerSize(side: 360), style: .artOnly) == .large)
        #expect(PlayerSizePreset(PlayerSize(side: 640), style: .artOnly) == .large)
        #expect(PlayerSizePreset(PlayerSize(width: 279, height: 72), style: .title) == .small)
        #expect(PlayerSizePreset(PlayerSize(width: 420, height: 72), style: .title) == .large)
        // Wide's Small and Medium are 40 apart, Medium and Large 80.
        #expect(PlayerSizePreset(PlayerSize(width: 339, height: 170), style: .wide) == .small)
        #expect(PlayerSizePreset(PlayerSize(width: 400, height: 200), style: .wide) == .large)
        #expect(PlayerSizePreset(PlayerSize(width: 520, height: 260), style: .wide) == .large)
    }

    @Test func squaresStayInsideTheirRange() {
        #expect(StyleGeometry.clamp(PlayerSize(side: 90), for: .artOnly) == PlayerSize(side: 168))
        #expect(StyleGeometry.clamp(PlayerSize(side: 900), for: .artOnly) == PlayerSize(side: 640))
        #expect(StyleGeometry.clamp(PlayerSize(side: 300), for: .artOnly) == PlayerSize(side: 300))
        #expect(StyleGeometry.clamp(PlayerSize(width: .nan, height: 10), for: .artOnly) == PlayerSize(side: 280))
        #expect(StyleGeometry.clamp(PlayerSize(width: .infinity, height: 10), for: .title) == PlayerSize(width: 300, height: 72))
    }

    @Test func switchingShapesKeepsASensibleSize() {
        // A bar handed to a square becomes a square from its longer side.
        #expect(StyleGeometry.clamp(PlayerSize(width: 400, height: 48), for: .artOnly) == PlayerSize(side: 400))
        #expect(StyleGeometry.clamp(PlayerSize(width: 400, height: 72), for: .menuBar) == PlayerSize(side: 400))
        // A portrait handed to a square keeps its cover's side, the width.
        #expect(StyleGeometry.clamp(PlayerSize(width: 280, height: 441), for: .artOnly) == PlayerSize(side: 280))
        // So does a landscape: its width is its longer side.
        #expect(StyleGeometry.clamp(PlayerSize(width: 360, height: 180), for: .artOnly) == PlayerSize(side: 360))
        // A square handed to a bar or a portrait takes its width.
        #expect(StyleGeometry.clamp(PlayerSize(side: 300), for: .title) == PlayerSize(width: 300, height: 72))
        #expect(StyleGeometry.clamp(PlayerSize(side: 640), for: .text) == PlayerSize(width: 360, height: 44))
        #expect(StyleGeometry.clamp(PlayerSize(side: 168), for: .strip) == PlayerSize(width: 260, height: 48))
        #expect(StyleGeometry.clamp(PlayerSize(side: 300), for: .bigArt) == PlayerSize(width: 300, height: 461))
        #expect(StyleGeometry.clamp(PlayerSize(side: 400), for: .wide) == PlayerSize(width: 400, height: 200))
        // Between bars, portraits and Wide, the width carries over, within
        // the new style's range.
        #expect(StyleGeometry.clamp(PlayerSize(width: 300, height: 72), for: .strip) == PlayerSize(width: 300, height: 48))
        #expect(StyleGeometry.clamp(PlayerSize(width: 300, height: 72), for: .bigArt) == PlayerSize(width: 300, height: 461))
        #expect(StyleGeometry.clamp(PlayerSize(width: 420, height: 581), for: .title) == PlayerSize(width: 420, height: 72))
        #expect(StyleGeometry.clamp(PlayerSize(width: 300, height: 72), for: .wide) == PlayerSize(width: 320, height: 160))
        #expect(StyleGeometry.clamp(PlayerSize(width: 440, height: 220), for: .bigArt) == PlayerSize(width: 420, height: 581))
        #expect(StyleGeometry.clamp(PlayerSize(width: 440, height: 220), for: .strip) == PlayerSize(width: 440, height: 48))
        // A square and back again comes home.
        let bigArt = PlayerSize(width: 300, height: 461)
        #expect(StyleGeometry.clamp(StyleGeometry.clamp(bigArt, for: .artOnly), for: .bigArt) == bigArt)
        let wide = PlayerSize(width: 440, height: 220)
        #expect(StyleGeometry.clamp(StyleGeometry.clamp(wide, for: .artOnly), for: .wide) == wide)
    }

    @Test func aBarsHeightNeverChanges() {
        for style in PlayerStyleID.allCases where style.isBar {
            let height = StyleGeometry.defaultSize(for: style).height
            for width in [0.0, 200, 300, 500, 2000] {
                #expect(StyleGeometry.clamp(PlayerSize(width: width, height: 300), for: style).height == height)
            }
        }
    }

    /// The bars and Wide are too short for History and Status, so they grow
    /// to the 300-pt square (§7.2); Art Only and Big Art show them in their
    /// own frame.
    @Test func theBarsAndWideGrowForHistoryAndStatus() {
        #expect(StyleGeometry.surfaceSide == 300)
        for style in [PlayerStyleID.title, .text, .strip, .wide] {
            #expect(StyleGeometry.needsExpansion(for: .echo, style: style))
            #expect(StyleGeometry.needsExpansion(for: .status, style: style))
            #expect(!StyleGeometry.needsExpansion(for: .now, style: style))
        }
        for style in [PlayerStyleID.artOnly, .bigArt] {
            #expect(!StyleGeometry.needsExpansion(for: .echo, style: style))
            #expect(!StyleGeometry.needsExpansion(for: .status, style: style))
            #expect(!StyleGeometry.needsExpansion(for: .now, style: style))
        }
    }

    @Test func draggingAStripChangesOnlyItsWidth() {
        let start = NSRect(x: 100, y: 500, width: 320, height: 48)
        func drag(_ position: ResizeHandleView.Position, x: CGFloat, y: CGFloat = 0) -> NSRect {
            ResizeHandleView.resizedFrame(
                from: start, position: position, dragX: x, dragY: y, shape: PlayerStyleID.strip.shape
            )
        }
        // Dragging the right edge out holds the left edge and the top.
        let wider = drag(.right, x: 60)
        #expect(wider == NSRect(x: 100, y: 500, width: 380, height: 48))
        #expect(wider.maxY == start.maxY)
        // Dragging the left edge holds the right edge.
        let narrower = drag(.left, x: 30)
        #expect(narrower.maxX == start.maxX)
        #expect(narrower.width == 290)
        // A corner drag up or down still only changes the width.
        let corner = drag(.bottomRight, x: 0, y: -80)
        #expect(corner.size == start.size)
        // Ends clamp.
        #expect(drag(.right, x: 900).width == 440)
        #expect(drag(.right, x: -900).width == 260)
    }

    @Test func aWindowIsABarWhenItIsTwiceAsWideAsTall() {
        #expect(PlayerShapeReader.isBar(CGSize(width: 400, height: 68)))
        #expect(!PlayerShapeReader.isBar(CGSize(width: 280, height: 280)))
        #expect(!PlayerShapeReader.isBar(CGSize(width: 300, height: 200)))
        #expect(!PlayerShapeReader.isBar(.zero))
        // Wide is exactly twice as wide as tall, and reads as one.
        #expect(PlayerShapeReader.isBar(CGSize(width: 320, height: 160)))
        #expect(PlayerShapeReader.isBar(CGSize(width: 520, height: 260)))
        #expect(!PlayerShapeReader.isBar(CGSize(width: 300, height: 160)))
    }
}

@Suite("Placement while resizing")
struct ResizeAnchorTests {
    let visible = CGRect(x: 0, y: 0, width: 1500, height: 900)

    @Test func theAnchorFollowsTheThirdOfTheScreen() {
        let topRight = CGRect(x: 1200, y: 600, width: 280, height: 280)
        #expect(PlacementResolver.anchor(of: topRight, in: visible) == CGPoint(x: 1, y: 1))
        let bottomLeft = CGRect(x: 10, y: 10, width: 280, height: 280)
        #expect(PlacementResolver.anchor(of: bottomLeft, in: visible) == CGPoint(x: 0, y: 0))
        let middle = CGRect(x: 610, y: 310, width: 280, height: 280)
        #expect(PlacementResolver.anchor(of: middle, in: visible) == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func growingHoldsTheAnchoredCorner() {
        let frame = CGRect(x: 1196, y: 596, width: 280, height: 280)
        let grown = PlacementResolver.frame(resizing: frame, to: CGSize(width: 400, height: 400), anchor: CGPoint(x: 1, y: 1), in: visible)
        #expect(grown.maxX == frame.maxX)
        #expect(grown.maxY == frame.maxY)
        #expect(grown.size == CGSize(width: 400, height: 400))
    }

    @Test func aStripKeepsItsShapeWhenKeptOnScreen() {
        let offScreen = CGRect(x: 1400, y: -40, width: 400, height: 68)
        let clamped = PlacementResolver.clamp(offScreen, to: visible)
        #expect(clamped.size == offScreen.size)
        #expect(visible.contains(clamped))
    }

    @Test func aSquareStaysSquareOnATinyDisplay() {
        let tiny = CGRect(x: 0, y: 0, width: 500, height: 300)
        let clamped = PlacementResolver.clamp(CGRect(x: 0, y: 0, width: 400, height: 400), to: tiny)
        #expect(clamped.width == clamped.height)
        #expect(clamped.height == 300)
    }
}

/// The order everywhere (DESIGN.md §7): Art Only, Title, Text, Strip, Wide,
/// Big Art, then Menu Bar; the Style ▸ menu lists the six window styles.
@Suite("Style order and stored values")
struct StyleOrderTests {
    @Test func wideSitsBetweenStripAndBigArt() {
        #expect(PlayerStyleID.allCases == [.artOnly, .title, .text, .strip, .wide, .bigArt, .menuBar])
        #expect(PlayerStyleID.windowStyles == [.artOnly, .title, .text, .strip, .wide, .bigArt])
        #expect(PlayerStyleID.allCases.map(\.title) == ["Art Only", "Title", "Text", "Strip", "Wide", "Big Art", "Menu Bar"])
    }

    /// Big Art was rebuilt in place (§13.29): a saved `bigArt` is still Big
    /// Art, and its old size opens in the new shape at the same width.
    @Test func aSavedBigArtStillDecodes() throws {
        let decoded = try JSONDecoder().decode([PlayerStyleID].self, from: Data(#"["bigArt", "wide"]"#.utf8))
        #expect(decoded == [.bigArt, .wide])
        #expect(PlayerStyleID.bigArt.rawValue == "bigArt")
        #expect(PlayerStyleID.wide.rawValue == "wide")
        let encoded = try JSONEncoder().encode([PlayerStyleID.wide, .bigArt])
        #expect(String(decoding: encoded, as: UTF8.self) == #"["wide","bigArt"]"#)
        // The old Big Art was the width plus 132.
        #expect(StyleGeometry.clamp(PlayerSize(width: 260, height: 392), for: .bigArt) == PlayerSize(width: 260, height: 421))
    }
}
