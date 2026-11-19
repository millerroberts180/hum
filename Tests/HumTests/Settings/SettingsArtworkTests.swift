import Foundation
import HumCore
@testable import HumUI
import SwiftUI
import Testing

@MainActor
@Suite("Style tiles")
struct StyleTileLayoutTests {
    /// The seven styles in DESIGN's order (§7, §13.19, §13.29). Every window
    /// style draws its own player; Menu Bar, which has no window, draws a
    /// strip of menu bar (DESIGN.md §8).
    @Test func everyStyleHasATileAndMenuBarDrawsTheMenuBar() {
        #expect(PlayerStyleID.allCases == [.artOnly, .title, .text, .strip, .wide, .bigArt, .menuBar])
        for style in PlayerStyleID.allCases {
            #expect(StyleTileArt.layout(for: style) == (style == .menuBar ? .menuBar : .miniature))
        }
    }

    /// Each miniature fills its tile on one side and keeps the window's shape.
    @Test func everyMiniatureFitsItsTileInItsOwnShape() {
        let box = StyleTileArt.box
        for style in PlayerStyleID.windowStyles {
            let scale = StyleMiniature.fittingScale(style, in: box)
            let drawn = StyleMiniature.drawnSize(style, size: nil, scale: scale)
            let real = StyleGeometry.defaultSize(for: style)
            #expect(drawn.width <= box.width + 0.001 && drawn.height <= box.height + 0.001, "\(style)")
            #expect(abs(drawn.width - box.width) < 0.001 || abs(drawn.height - box.height) < 0.001, "\(style)")
            #expect(abs(drawn.width / drawn.height - real.width / real.height) < 0.001, "\(style)")
        }
    }

    @Test func barsAreDrawnWideAndBigArtTall() {
        for style in PlayerStyleID.windowStyles {
            let drawn = StyleMiniature.drawnSize(style, size: nil, scale: 1)
            if style.isBar {
                #expect(drawn.width > drawn.height * 3, "\(style)")
            } else if style.isPortrait {
                #expect(drawn.height > drawn.width, "\(style)")
            } else if style.isLandscape {
                #expect(drawn.width == drawn.height * 2, "\(style)")
            } else {
                #expect(drawn.width == drawn.height, "\(style)")
            }
        }
    }

    /// A size saved for one shape is drawn in the style's own.
    @Test func aSavedSizeIsDrawnInTheStylesShape() {
        #expect(StyleMiniature.realSize(.title, size: PlayerSize(side: 300)) == CGSize(width: 300, height: 72))
        #expect(StyleMiniature.realSize(.bigArt, size: PlayerSize(side: 300)) == CGSize(width: 300, height: 461))
        #expect(StyleMiniature.realSize(.artOnly, size: PlayerSize(side: 1000)) == CGSize(width: 640, height: 640))
    }

    /// The miniature rounds as the window does: Text a capsule at any corner
    /// setting, Title and Strip a card's corners, Art Only a panel's.
    @Test func theMiniatureRoundsAsTheWindowDoes() {
        let text = StyleMiniature.realSize(.text, size: nil)
        #expect(StyleMiniature.windowRadius(.text, real: text) == text.height / 2)
        #expect(StyleMiniature.windowRadius(.text, real: text, cornerRadiusScale: 0.5) == text.height / 2)
        let title = StyleMiniature.realSize(.title, size: nil)
        #expect(StyleMiniature.windowRadius(.title, real: title) == Radius.card)
        #expect(StyleMiniature.windowRadius(.title, real: title, cornerRadiusScale: 1.5) == Radius.card * 1.5)
        let art = StyleMiniature.realSize(.artOnly, size: nil)
        #expect(StyleMiniature.windowRadius(.artOnly, real: art, cornerRadiusScale: 0.5) == Radius.panel(side: art.width) * 0.5)
    }
}

@Suite("Calendar heat cells")
struct HeatCalendarTokenTests {
    @Test func cellsAndTheirFocusRingUseTheSpacingTokens() {
        #expect(HeatCalendar.cell == 10)
        #expect(HeatCalendar.gap == 4)
        #expect(HeatCalendar.cellRadius == 2)
        // The ring sits 2 pt outside the cell, so its corners are concentric.
        #expect(HeatCalendar.ringRadius == 4)
        #expect(HeatCalendar.ringWidth == 1.5)
    }
}

@Suite("Choice tiles")
struct SystemTileMetricsTests {
    @Test func metricsMatchSystemSettings() {
        #expect(SystemTileMetrics.gap == 14)
        #expect(SystemTileMetrics.cornerRadius == 10)
        #expect(SystemTileMetrics.ringWidth == 3)
        // The ring sits outside the tile, so its corners are concentric.
        #expect(SystemTileMetrics.ringCornerRadius == 13)
    }

    @Test func theSelectedTitleIsSemiboldInLabel() {
        #expect(SystemTileMetrics.titleWeight(isSelected: true) == .semibold)
        #expect(SystemTileMetrics.titleColor(isSelected: true) == .label)
    }

    @Test func otherTitlesAreRegularInSecondaryLabel() {
        #expect(SystemTileMetrics.titleWeight(isSelected: false) == .regular)
        #expect(SystemTileMetrics.titleColor(isSelected: false) == .secondaryLabel)
    }
}

@MainActor
@Suite("Session trail")
struct SessionTrailLayoutTests {
    let side = SessionRibbon.thumbnail
    let gap = SessionRibbon.thumbnailGap

    @Test func everyCoverShowsWhenTheyAllFit() {
        let widths = Array(repeating: side, count: 3)
        #expect(TrailStack.wholeCount(widths, width: 3 * side + 2 * gap, gap: gap) == 3)
        #expect(TrailStack.wholeCount(widths, width: 200, gap: gap) == 3)
    }

    @Test func onlyCoversThatFitWholeShow() {
        let widths = Array(repeating: side, count: 10)
        // Room for four whole covers and most of a fifth: the fifth doesn't show.
        #expect(TrailStack.wholeCount(widths, width: 5 * side + 4 * gap - 1, gap: gap) == 4)
        #expect(TrailStack.wholeCount(widths, width: 5 * side + 4 * gap, gap: gap) == 5)
    }

    @Test func noRoomShowsNoCover() {
        #expect(TrailStack.wholeCount([side, side], width: side - 1, gap: gap) == 0)
        #expect(TrailStack.wholeCount([], width: 100, gap: gap) == 0)
    }
}
