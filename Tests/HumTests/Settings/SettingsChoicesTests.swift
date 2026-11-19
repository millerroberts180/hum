import AppKit
import Foundation
import HumCore
@testable import HumUI
import Testing

@Suite("Corner and opacity tiles")
struct NearestTileTests {
    @Test func theTilesSetTheDesignsValues() {
        #expect(CornerChoice.allCases.map(\.scale) == [0.5, 1, 1.5])
        #expect(CornerChoice.allCases.map(\.title) == ["Square", "Standard", "Round"])
        #expect(OpacityChoice.allCases.map(\.opacity) == [1, 0.85, 0.7])
        #expect(OpacityChoice.allCases.map(\.title) == ["100%", "85%", "70%"])
    }

    @Test func eachTileMarksItsOwnValue() {
        for choice in CornerChoice.allCases {
            #expect(CornerChoice.nearest(to: choice.scale) == choice)
        }
        for choice in OpacityChoice.allCases {
            #expect(OpacityChoice.nearest(to: choice.opacity) == choice)
        }
    }

    /// A value saved before the tiles, from the old sliders, marks the
    /// nearest tile.
    @Test func aValueInBetweenMarksTheNearestTile() {
        #expect(CornerChoice.nearest(to: 0.6) == .square)
        #expect(CornerChoice.nearest(to: 0.85) == .standard)
        #expect(CornerChoice.nearest(to: 1.2) == .standard)
        #expect(CornerChoice.nearest(to: 1.35) == .round)
        #expect(OpacityChoice.nearest(to: 0.95) == .full)
        #expect(OpacityChoice.nearest(to: 0.9) == .high)
        #expect(OpacityChoice.nearest(to: 0.8) == .high)
        #expect(OpacityChoice.nearest(to: 0.74) == .low)
    }

    @Test func halfwayGoesToTheLarger() {
        #expect(CornerChoice.nearest(to: 0.75) == .standard)
        #expect(CornerChoice.nearest(to: 1.25) == .round)
    }

    @Test func valuesOutsideTheRangeMarkTheEnds() {
        #expect(CornerChoice.nearest(to: 0) == .square)
        #expect(CornerChoice.nearest(to: 4) == .round)
        #expect(OpacityChoice.nearest(to: 0.1) == .low)
        #expect(OpacityChoice.nearest(to: 1.5) == .full)
        #expect(CornerChoice.nearest(to: .nan) == .round)
    }

    /// The look clamps what it stores; every tile's value comes through whole.
    @Test func everyTileValueIsOneTheLookKeeps() {
        for choice in CornerChoice.allCases {
            #expect(StyleLook(cornerRadiusScale: choice.scale).cornerRadiusScale == choice.scale)
        }
        for choice in OpacityChoice.allCases {
            #expect(StyleLook(opacity: choice.opacity).opacity == choice.opacity)
        }
    }
}

/// Whether this Mac has Liquid Glass.
private let hasLiquidGlass = ProcessInfo.processInfo.isOperatingSystemAtLeast(
    OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
)

@Suite("Appearance rows")
struct AppearanceRowTests {
    @Test func materialIsOfferedOnlyWithLiquidGlass() {
        for style in PlayerStyleID.allCases {
            #expect(!AppearanceRow.rows(for: style, liquidGlassAvailable: false).contains(.material))
            #expect(AppearanceRow.rows(for: style, liquidGlassAvailable: true).contains(.material))
        }
    }

    /// On macOS 15 there's no Material row at all (DESIGN.md §8).
    @Test(.enabled(if: !hasLiquidGlass))
    func macOS15HasNoMaterialRow() {
        #expect(!GlassMaterial.isLiquidGlassAvailable)
        for style in PlayerStyleID.allCases {
            #expect(!AppearanceRow.rows(for: style).contains(.material))
        }
    }

    @Test(.enabled(if: hasLiquidGlass))
    func macOS26HasTheMaterialRow() {
        #expect(GlassMaterial.isLiquidGlassAvailable)
        #expect(AppearanceRow.rows(for: .artOnly).contains(.material))
    }

    /// The material is kept even where it isn't offered, so a Mac that moves
    /// to macOS 26 finds the choice as it was.
    @Test(arguments: GlassMaterial.allCases)
    func theMaterialRoundTrips(material: GlassMaterial) throws {
        var appearance = AppearanceSettings()
        appearance.material = material
        appearance.style = .text
        let data = try JSONEncoder().encode(appearance)
        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: data)
        #expect(decoded.material == material)
        #expect(decoded == appearance)
    }

    @Test func rowsComeInTheDesignsOrder() {
        #expect(AppearanceRow.rows(for: .artOnly, liquidGlassAvailable: true)
            == [.style, .appearance, .material, .accent, .corners, .opacity, .progress])
        #expect(AppearanceRow.rows(for: .bigArt, liquidGlassAvailable: false)
            == [.style, .appearance, .accent, .corners, .opacity])
    }

    @Test func onlyArtOnlyOffersProgressAndOnlyTextAlbumTint() {
        for style in PlayerStyleID.allCases {
            let rows = AppearanceRow.rows(for: style, liquidGlassAvailable: false)
            #expect(rows.contains(.progress) == (style == .artOnly), "\(style)")
            #expect(rows.contains(.albumTint) == (style == .text), "\(style)")
        }
    }

    /// Menu Bar has no window to round or fade; Text's capsule stays one
    /// whatever the corner setting.
    @Test func menuBarHasNoCornersOrOpacityAndTextNoCorners() {
        let menuBar = AppearanceRow.rows(for: .menuBar, liquidGlassAvailable: false)
        #expect(!menuBar.contains(.corners))
        #expect(!menuBar.contains(.opacity))
        let text = AppearanceRow.rows(for: .text, liquidGlassAvailable: false)
        #expect(!text.contains(.corners))
        #expect(text.contains(.opacity))
    }
}

@Suite("Player rows")
struct PlayerRowTests {
    /// Menu Bar has no window to size, place or show, its popover always
    /// shows its controls, and it has Now only, so there's nothing to swipe
    /// between (DESIGN.md §7.1).
    @Test func menuBarHidesWhatItsPopoverDoesntUse() {
        let rows = PlayerRow.rows(for: .menuBar)
        #expect(!rows.contains(.alwaysShowControls))
        #expect(!rows.contains(.size))
        #expect(!rows.contains(.position))
        #expect(!rows.contains(.visibility))
        #expect(!rows.contains(.gestures))
        #expect(rows == [.controls, .window])
    }

    @Test(arguments: PlayerStyleID.windowStyles)
    func everyWindowStyleHasThem(style: PlayerStyleID) {
        #expect(PlayerRow.rows(for: style) == [.alwaysShowControls, .controls, .size, .position, .visibility, .window, .gestures])
    }
}

@Suite("Position tile")
struct PositionTileTests {
    /// The width the Player pane gives a row in the 688-pt window.
    let tile = CGSize(width: 440, height: PositionTile.height)

    @Test func clickingATargetPinsThere() {
        for position in PinPosition.allCases {
            let point = PositionTileLayout.target(position, in: tile)
            #expect(PositionTileLayout.position(at: point, in: tile) == position)
        }
    }

    @Test func aClickNearATargetPinsThere() {
        for position in PinPosition.allCases {
            let target = PositionTileLayout.target(position, in: tile)
            let point = CGPoint(x: target.x + 6, y: target.y - 5)
            #expect(PositionTileLayout.position(at: point, in: tile) == position)
        }
    }

    @Test func theScreensCornersAndEdgesPinThere() {
        let screen = PositionTileLayout.screen(in: tile)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.minX + 1, y: screen.minY + 1), in: tile) == .topLeft)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.maxX - 1, y: screen.minY + 1), in: tile) == .topRight)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.minX + 1, y: screen.maxY - 1), in: tile) == .bottomLeft)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.maxX - 1, y: screen.maxY - 1), in: tile) == .bottomRight)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.midX, y: screen.minY + 1), in: tile) == .top)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.midX, y: screen.midY), in: tile) == .center)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.minX + 1, y: screen.midY), in: tile) == .left)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.maxX - 1, y: screen.midY), in: tile) == .right)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.midX, y: screen.maxY - 1), in: tile) == .bottom)
    }

    @Test func aClickBesideTheScreenPinsNothing() {
        let screen = PositionTileLayout.screen(in: tile)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.minX - 2, y: screen.midY), in: tile) == nil)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.maxX + 2, y: screen.midY), in: tile) == nil)
        #expect(PositionTileLayout.position(at: CGPoint(x: screen.midX, y: screen.maxY + 2), in: tile) == nil)
    }

    @Test func theTargetsSitBelowTheMenuBarInTheirPlaces() {
        let area = PositionTileLayout.visibleArea(in: tile)
        for position in PinPosition.allCases {
            let target = PositionTileLayout.target(position, in: tile)
            #expect(area.contains(target), "\(position)")
            for other in PinPosition.allCases {
                let otherTarget = PositionTileLayout.target(other, in: tile)
                if other.column > position.column { #expect(otherTarget.x > target.x) }
                if other.row > position.row { #expect(otherTarget.y < target.y) }
            }
        }
    }

    @Test func theDrawnScreenKeepsTheDisplaysShape() {
        let wide = PositionTileLayout.screen(in: tile, aspect: 16.0 / 9.0)
        #expect(abs(wide.width / wide.height - 16.0 / 9.0) < 0.001)
        #expect(abs(wide.midX - tile.width / 2) < 0.001)
        #expect(abs(wide.midY - tile.height / 2) < 0.001)
        #expect(wide.height == PositionTileLayout.screenHeight)
    }

    @Test func thePinnedPlayerSitsAgainstItsPlace() {
        let player = CGSize(width: 40, height: 40)
        let area = PositionTileLayout.visibleArea(in: tile).insetBy(dx: PositionTileLayout.inset / 2, dy: PositionTileLayout.inset / 2)
        let topLeft = PositionTileLayout.playerFrame(player, at: .topLeft, in: tile)
        #expect(topLeft.origin == CGPoint(x: area.minX, y: area.minY))
        let bottomRight = PositionTileLayout.playerFrame(player, at: .bottomRight, in: tile)
        #expect(bottomRight.maxX == area.maxX)
        #expect(bottomRight.maxY == area.maxY)
        let center = PositionTileLayout.playerFrame(player, at: .center, in: tile)
        #expect(center.midX == area.midX)
        #expect(center.midY == area.midY)
    }

    /// The arrow keys step to the neighbouring place, and stop at the edges.
    @Test func arrowsStepToTheNeighbouringPlace() {
        #expect(PinPosition.topLeft.neighbor(columns: 1, rows: 0) == .top)
        #expect(PinPosition.top.neighbor(columns: 0, rows: -1) == .center)
        #expect(PinPosition.center.neighbor(columns: 0, rows: 1) == .top)
        #expect(PinPosition.right.neighbor(columns: -1, rows: 0) == .center)
        #expect(PinPosition.topLeft.neighbor(columns: -1, rows: 0) == nil)
        #expect(PinPosition.bottomRight.neighbor(columns: 0, rows: -1) == nil)
    }
}

@Suite("Size tiles")
struct SizeTileTests {
    /// Small, Medium and Large are drawn at one scale, so they compare as the
    /// real sizes do, and Large fits its tile.
    @MainActor
    @Test(arguments: PlayerStyleID.windowStyles)
    func theThreeSizesCompareAtOneScale(style: PlayerStyleID) {
        let scale = SizeTileArt.scale(for: style)
        let drawn = PlayerSizePreset.allCases.map { StyleMiniature.drawnSize(style, size: $0.size(for: style), scale: scale) }
        #expect(drawn[0].width < drawn[1].width)
        #expect(drawn[1].width < drawn[2].width)
        #expect(drawn[2].width <= SizeTileArt.box.width + 0.001)
        #expect(drawn[2].height <= SizeTileArt.box.height + 0.001)
        if style.isBar {
            // A bar's height doesn't follow its width.
            #expect(drawn[0].height == drawn[2].height)
        }
    }
}

@Suite("Source tiles")
struct SourceChoiceTests {
    @Test func theTilesNameTheApps() {
        #expect(SourceChoice.allCases.map(\.title) == ["Automatic", "Music", "Spotify"])
    }

    @Test func eachTileStoresItsSource() {
        #expect(SourceChoice.automatic.sourceID == nil)
        #expect(SourceChoice.music.sourceID == .musicApp)
        #expect(SourceChoice.spotify.sourceID == .spotifyApp)
    }

    @Test func aStoredPreferenceMarksItsTile() {
        #expect(SourceChoice(preferred: nil) == .automatic)
        #expect(SourceChoice(preferred: .musicApp) == .music)
        #expect(SourceChoice(preferred: .spotifyApp) == .spotify)
        // The demo isn't offered here; it reads as following whatever plays.
        #expect(SourceChoice(preferred: .demo) == .automatic)
    }

    @MainActor
    @Test func automaticCanAlwaysBePicked() {
        #expect(SourceApps.isInstalled(.automatic))
    }
}
