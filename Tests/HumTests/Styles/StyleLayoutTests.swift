import AppKit
import CoreGraphics
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// A bar takes its metrics from the width its window gives it (DESIGN.md §7),
/// even when its content asks for the width it was first given, as Text's
/// spread transport row does. That row used to hold the capsule's content at
/// the default 280 pt, so at 200 and 240 it ran past the capsule's ends.
@MainActor
@Suite("Bar metrics")
struct BarMetricsWidthTests {
    @MainActor
    final class Seen {
        var width: CGFloat?
    }

    /// As wide as its metrics' side, whatever it's offered.
    struct Probe: View {
        let seen: Seen
        @Environment(\.playerMetrics) private var metrics

        var body: some View {
            Color.clear
                .frame(width: metrics.side, height: 10)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    seen.width = width
                }
        }
    }

    @Test(arguments: [200.0, 240, 320])
    func theContentTakesTheWindowsWidth(width: CGFloat) async throws {
        let seen = Seen()
        let size = CGSize(width: width, height: 44)
        let view = NSHostingView(rootView: Probe(seen: seen)
            .barMetrics(playsAtSecondarySize: true)
            .frame(width: size.width, height: size.height)
            .environment(\.playerMetrics, PlayerMetrics(side: PlayerMetrics.defaultSide)))
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(width != PlayerMetrics.defaultSide)
        #expect(seen.width == width)
    }
}

/// Wide's and Big Art's cards (DESIGN.md §7): the cover inset `Spacing.m`
/// on the card, and the stack beside it or under it.
@MainActor
enum CardLayout {
    typealias Pixels = MissingArtworkTests.Pixels

    static let longTrack = Track(
        id: TrackID("long"),
        title: "A Song Whose Title Runs Well Past the Width of Any Player",
        artist: "Mira Okafor and the Long Names Ensemble",
        album: "Everything at Once, Deluxe Edition",
        isExplicit: true
    )

    static func environment(_ view: some View, style: PlayerStyleID, width: CGFloat, player: PreviewPlayer) -> some View {
        player.services.inject(view
            .environment(\.playerMetrics, PlayerMetrics(side: width))
            .environment(\.playerLook, PlayerLook(
                style: style,
                look: player.settings.appearance.look(for: style, in: .dark),
                appearance: .dark,
                isBar: style.isLandscape
            ))
            .environment(player.store)
            .environment(player.settings)
            .environment(player.pager)
            .environment(player.interaction))
    }

    static func render(_ style: PlayerStyleID, width: CGFloat, @ViewBuilder content: () -> some View) async throws -> Pixels {
        let player = PreviewPlayer()
        for _ in 0..<500 where player.store.artwork == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(player.store.artwork != nil)
        let size = style.shape.size(width: width)
        let view = content().frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: environment(view, style: style, width: width, player: player))
        renderer.scale = 1
        return try Pixels(try #require(renderer.cgImage))
    }

    /// The stack's fitting size at `column` wide, with a long explicit title,
    /// Save and More, the album (Big Art), and every control on.
    static func stackSize(_ style: PlayerStyleID, width: CGFloat, column: CGFloat) -> CGSize {
        let player = PreviewPlayer()
        let stack = CardStack(
            track: longTrack,
            menu: TrackMenu(capabilities: PreviewSource.capabilities, isSaved: false, context: .now),
            width: column
        )
        // The metrics `barMetrics` gives the card at `width`, set directly:
        // its overlay has no height of its own to measure.
        .environment(\.playerMetrics, metrics(width: width))
        let view = NSHostingView(rootView: environment(stack, style: style, width: width, player: player))
        return view.fittingSize
    }

    /// The card's metrics at `width`: its type by the width, its controls at
    /// S with play at the secondary size.
    static func metrics(width: CGFloat) -> PlayerMetrics {
        PlayerMetrics(side: width, controlClass: .small, playsAtSecondarySize: true)
    }

    /// The transport's backings, which never close up, side by side.
    static func transportBackings(width: CGFloat) -> CGFloat {
        TransportRow.sizes(metrics(width: width), showsModes: true).reduce(0) { $0 + $1.backing }
    }

    /// Whether `pixel` is within `tolerance` of `color`, unpremultiplied.
    static func isNear(_ pixel: [UInt8], _ color: (r: Double, g: Double, b: Double), tolerance: Double = 0.08) -> Bool {
        guard pixel[3] >= 160 else { return false }
        let alpha = Double(pixel[3])
        let r = Double(pixel[0]) / alpha, g = Double(pixel[1]) / alpha, b = Double(pixel[2]) / alpha
        return abs(r - color.r) <= tolerance && abs(g - color.g) <= tolerance && abs(b - color.b) <= tolerance
    }

    /// The demo cover's lower leading corner is its gradient's warm end and
    /// its upper trailing corner the cool end; whether both show at a square
    /// `side` wide whose top leading corner is at `origin`, and the card
    /// shows just outside it.
    static func expectCover(_ pixels: Pixels, origin: CGPoint, side: CGFloat, _ label: String) {
        let x = Int(origin.x), y = Int(origin.y), s = Int(side)
        let lowerLeading = pixels.pixel(x: x + 8, y: y + s - 8)
        let upperTrailing = pixels.pixel(x: x + s - 8, y: y + 8)
        #expect(isNear(lowerLeading, PlayerPreviewRenderTests.warmEnd), "\(label): \(lowerLeading)")
        #expect(isNear(upperTrailing, PlayerPreviewRenderTests.coolEnd), "\(label): \(upperTrailing)")
        // The inset is the card, not the cover.
        let beforeLeading = pixels.pixel(x: x - 4, y: y + s - 8)
        let aboveTrailing = pixels.pixel(x: x + s - 8, y: y - 4)
        #expect(!isNear(beforeLeading, PlayerPreviewRenderTests.warmEnd), "\(label): \(beforeLeading)")
        #expect(!isNear(aboveTrailing, PlayerPreviewRenderTests.coolEnd), "\(label): \(aboveTrailing)")
    }
}

/// Big Art is a portrait card (DESIGN.md §7, §13.29): the cover inset
/// `Spacing.m` from the top and sides, and the stack under it with
/// `Spacing.m` below. It used to run the cover edge to edge over an
/// `artBackdrop`.
@MainActor
@Suite("Big Art layout")
struct BigArtLayoutTests {
    @Test(arguments: [220.0, 280, 420])
    func theCoverIsInsetOnTheCard(width: CGFloat) async throws {
        let pixels = try await CardLayout.render(.bigArt, width: width) { BigArtNowLayout() }
        let inset = Spacing.m
        #expect(pixels.width == Int(width))
        #expect(pixels.height == Int(width + CGFloat(StyleGeometry.bigArtControlsHeight)))
        let side = BigArtNowLayout.coverSide(width: width)
        #expect(side == width - 2 * inset)
        CardLayout.expectCover(pixels, origin: CGPoint(x: inset, y: inset), side: side, "\(width)")
        // The stack is under it, not more cover.
        let underneath = pixels.pixel(x: Int(inset) + 8, y: Int(inset + side) + 4)
        #expect(!CardLayout.isNear(underneath, PlayerPreviewRenderTests.warmEnd), "\(width): \(underneath)")
    }

    /// The room under the cover is the stack's, less `Spacing.m` below it.
    @Test func theRoomUnderTheCoverIsTheStacksAndAnInset() {
        let width = 280.0
        let size = PlayerStyleID.bigArt.shape.size(width: width)
        let cover = BigArtNowLayout.coverSide(width: width)
        let below = size.height - Spacing.m - cover - Spacing.m
        #expect(below == BigArtNowLayout.stackRoom + Spacing.m)
    }

    /// The larger title (§13.20), 17 pt at L, still leaves the stack room
    /// under the cover at every width, with a long explicit title, the album,
    /// Save and More, and every control.
    @Test(arguments: [220.0, 239, 240, 280, 360, 379, 380, 420])
    func theStackFitsUnderTheCover(width: CGFloat) {
        let column = BigArtNowLayout.coverSide(width: width)
        let fitting = CardLayout.stackSize(.bigArt, width: width, column: column)
        #expect(fitting.height > 100, "\(width): \(fitting)")
        #expect(fitting.height <= BigArtNowLayout.stackRoom, "\(width): \(fitting)")
        #expect(fitting.width <= column + 0.5, "\(width): \(fitting)")
        #expect(CardLayout.transportBackings(width: width) <= column, "\(width)")
    }

    /// The room fits the stack at M and L to the point, so a taller stack
    /// fails `theStackFitsUnderTheCover` rather than crowding the inset.
    @Test func theRoomIsTheStacksHeight() {
        let fitting = CardLayout.stackSize(.bigArt, width: 280, column: BigArtNowLayout.coverSide(width: 280))
        #expect(BigArtNowLayout.stackRoom - fitting.height < 4, "\(fitting)")
    }
}

/// Wide is a landscape card half as tall as it is wide (DESIGN.md §7): the
/// cover a square at the leading edge, inset `Spacing.m` on three sides, and
/// the stack in the column beside it.
@MainActor
@Suite("Wide layout")
struct WideLayoutTests {
    @Test(arguments: [320.0, 360, 440, 520])
    func theCoverIsAtTheLeadingEdge(width: CGFloat) async throws {
        let pixels = try await CardLayout.render(.wide, width: width) { WideNowLayout() }
        let inset = Spacing.m
        #expect(pixels.width == Int(width))
        #expect(pixels.height == Int(width / 2))
        let side = WideNowLayout.coverSide(height: width / 2)
        #expect(side == width / 2 - 2 * inset)
        CardLayout.expectCover(pixels, origin: CGPoint(x: inset, y: inset), side: side, "\(width)")
        // The column beside it isn't cover.
        let beside = pixels.pixel(x: Int(inset + side) + 4, y: Int(inset + side) - 8)
        #expect(!CardLayout.isNear(beside, PlayerPreviewRenderTests.warmEnd), "\(width): \(beside)")
    }

    @Test(arguments: [(320.0, 148.0), (360, 168), (440, 208), (520, 248)])
    func theColumnIsWhatTheCoverLeaves(width: CGFloat, column: CGFloat) {
        let size = PlayerStyleID.wide.shape.size(width: width)
        #expect(WideNowLayout.columnWidth(size: CGSize(width: size.width, height: size.height)) == column)
    }

    /// From the narrowest to the widest, and at every preset, the stack fits
    /// the column's width and the card's height, with a long explicit title,
    /// Save and More, and every control. Centered, it keeps at least
    /// `Spacing.xs` above and below: at 320 the card is 160 tall and the
    /// stack about 149, so the `Spacing.m` inset holds from 360 up.
    @Test(arguments: [320.0, 360, 380, 440, 520])
    func theStackFitsBesideTheCover(width: CGFloat) {
        let size = PlayerStyleID.wide.shape.size(width: width)
        let column = WideNowLayout.columnWidth(size: CGSize(width: size.width, height: size.height))
        let fitting = CardLayout.stackSize(.wide, width: width, column: column)
        #expect(fitting.height > 100, "\(width): \(fitting)")
        #expect(fitting.height <= size.height - 2 * Spacing.xs, "\(width): \(fitting)")
        #expect(fitting.width <= column + 0.5, "\(width): \(fitting)")
        #expect(CardLayout.transportBackings(width: width) <= column, "\(width)")
    }
}

/// The player's content clips to the window's own corners, so a card's 1-pt
/// edge and its content meet at the same 12 pt. It used to clip to a panel's
/// radius, which on macOS 26 grows with the size: 14 pt for Wide, 21 for Big
/// Art at their defaults.
@Suite("Player corners")
struct PlayerCornerTests {
    @Test func theCardsKeepACardsCornersOnNow() {
        let wide = CGSize(width: 360, height: 180)
        let bigArt = CGSize(width: 280, height: 441)
        #expect(PlayerRootView.cornerRadius(style: .wide, surface: .now, size: wide, scale: 1) == Radius.card)
        #expect(PlayerRootView.cornerRadius(style: .bigArt, surface: .now, size: bigArt, scale: 1) == Radius.card)
        // Big Art shows History in its own frame, with its own corners.
        #expect(PlayerRootView.cornerRadius(style: .bigArt, surface: .echo, size: bigArt, scale: 1) == Radius.card)
        #expect(PlayerRootView.cornerRadius(style: .wide, surface: .now, size: wide, scale: 0.5) == Radius.card * 0.5)
    }

    /// Grown to the square for History and Status, the window is a panel.
    @Test(arguments: [PlayerStyleID.title, .strip, .wide])
    func theSquareForHistoryAndStatusHasAPanelsCorners(style: PlayerStyleID) {
        let square = CGSize(width: StyleGeometry.surfaceSide, height: StyleGeometry.surfaceSide)
        for surface in [Surface.echo, .status] {
            #expect(PlayerRootView.cornerRadius(style: style, surface: surface, size: square, scale: 1) == Radius.panel(side: square.width))
        }
    }

    @Test func artOnlyAndTextKeepTheirOwn() {
        let artOnly = CGSize(width: 280, height: 280)
        #expect(PlayerRootView.cornerRadius(style: .artOnly, surface: .now, size: artOnly, scale: 1) == Radius.panel(side: 280))
        let text = CGSize(width: 240, height: 44)
        #expect(PlayerRootView.cornerRadius(style: .text, surface: .now, size: text, scale: 1) == 22)
    }
}
