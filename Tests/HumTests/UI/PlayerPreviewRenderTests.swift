import CoreGraphics
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// The live preview in Settings › Appearance, with the demo naming Spotify.
/// Its shadow used to be taken from the player itself, and over a flat
/// backdrop only that shadow drew once Settings was active. Every style has to
/// draw its player, with the cover in it, at rest and with its controls
/// showing; the shadow is drawn from the shape, outside it.
@MainActor
@Suite("Player preview")
struct PlayerPreviewRenderTests {
    typealias Pixels = MissingArtworkTests.Pixels

    /// The room the Appearance pane gives the preview.
    static let room = CGSize(width: 380, height: 240)

    /// The ends of the demo cover's gradient (`PreviewSource.coverData`).
    static let warmEnd = (r: 0.93, g: 0.55, b: 0.36)
    static let coolEnd = (r: 0.27, g: 0.20, b: 0.52)

    /// The preview as the pane draws it, once the demo cover is in, and where
    /// in the picture the player sits.
    func render(_ style: PlayerStyleID, appearance: LookAppearance, showsControls: Bool) async throws -> (Pixels, CGRect) {
        let player = PreviewPlayer(demoAttribution: "Spotify")
        for _ in 0..<500 where player.store.artwork == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(player.store.artwork != nil)
        #expect(player.store.displayedArtworkSource == .demo)

        let view = player.services.inject(
            PlayerPreview(style: style, appearance: appearance, showsControls: showsControls)
                .frame(width: Self.room.width, height: Self.room.height)
                .environment(player.store)
                .environment(player.settings)
                .environment(player.pager)
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let pixels = try Pixels(try #require(renderer.cgImage))

        let size = PlayerPreview.size(for: style, playerSize: nil)
        let scale = PlayerPreview.scale(for: size, in: Self.room)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let frame = CGRect(
            x: (Self.room.width - drawn.width) / 2, y: (Self.room.height - drawn.height) / 2,
            width: drawn.width, height: drawn.height
        )
        return (pixels, frame)
    }

    /// The share of `rect` that's drawn: mostly opaque and not the shadow's
    /// black. A preview that draws only its shadow scores 0.
    func drawnShare(of pixels: Pixels, in rect: CGRect) -> Double {
        let box = Self.inside(pixels, rect.insetBy(dx: 4, dy: 4))
        var drawn = 0, total = 0
        for y in Int(box.minY)..<Int(box.maxY) {
            for x in Int(box.minX)..<Int(box.maxX) {
                let pixel = pixels.pixel(x: x, y: y)
                total += 1
                if pixel[3] >= 160, pixel[0...2].contains(where: { $0 >= 40 }) { drawn += 1 }
            }
        }
        return total == 0 ? 0 : Double(drawn) / Double(total)
    }

    /// Whether some pixel in `rect` is within `tolerance` of `color`, unpremultiplied.
    func contains(_ color: (r: Double, g: Double, b: Double), in pixels: Pixels, rect: CGRect, tolerance: Double = 0.1) -> Bool {
        let box = Self.inside(pixels, rect)
        for y in Int(box.minY)..<Int(box.maxY) {
            for x in Int(box.minX)..<Int(box.maxX) {
                let pixel = pixels.pixel(x: x, y: y)
                guard pixel[3] >= 160 else { continue }
                let alpha = Double(pixel[3])
                let r = Double(pixel[0]) / alpha, g = Double(pixel[1]) / alpha, b = Double(pixel[2]) / alpha
                if abs(r - color.r) <= tolerance, abs(g - color.g) <= tolerance, abs(b - color.b) <= tolerance {
                    return true
                }
            }
        }
        return false
    }

    /// The whole pixels of `rect` inside the picture. A player scaled to the
    /// room's full height, as Big Art is, can start a hair above it, which
    /// `integral` would round out to the row before the first.
    static func inside(_ pixels: Pixels, _ rect: CGRect) -> CGRect {
        rect.integral.intersection(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
    }

    @Test(arguments: PlayerStyleID.allCases, [LookAppearance.light, .dark])
    func everyStyleDrawsItsPlayer(style: PlayerStyleID, appearance: LookAppearance) async throws {
        for showsControls in [false, true] {
            let (pixels, player) = try await render(style, appearance: appearance, showsControls: showsControls)
            let label = "\(style) \(appearance)\(showsControls ? " with controls" : "")"
            #expect(player.width > 100 && player.height > 40)
            let share = drawnShare(of: pixels, in: player)
            #expect(share > 0.9, "\(label): \(share) of the player drawn")
            // The cover, whole, in every style that shows one. Text has
            // none: it's the title and artist in a capsule. The warm end is
            // the cover's lower leading corner. Art Only's controls sit on
            // the scrim over the cover's lower part (§7), so with them showing
            // only the upper, cool end shows as it is, and the warm end is
            // darker. The preview draws Menu Bar as Art Only.
            if style != .text {
                let underScrim = showsControls && [.artOnly, .menuBar].contains(style)
                let hasWarmEnd = contains(Self.warmEnd, in: pixels, rect: player)
                let hasCoolEnd = contains(Self.coolEnd, in: pixels, rect: player)
                #expect(hasCoolEnd, "\(label): no cover")
                #expect(hasWarmEnd != underScrim, "\(label): \(underScrim ? "no scrim" : "no cover")")
            }
        }
    }

    /// Nothing inside the shape, so a translucent player shows what's behind
    /// it; the shadow falls mostly below, as the window's does.
    @Test func theShadowStaysOutsideTheShape() throws {
        let view = PreviewShadow(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(width: 100, height: 100)
            .padding(30)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let pixels = try Pixels(try #require(renderer.cgImage))
        #expect(pixels.width == 160 && pixels.height == 160)

        // The shape spans 30..<130 on both axes.
        for (x, y) in [(80, 80), (40, 40), (120, 120), (80, 127), (33, 80)] {
            #expect(pixels.alpha(x: x, y: y) == 0, "shadow inside the shape at \(x), \(y)")
        }
        let below = pixels.pixel(x: 80, y: 134)
        let above = pixels.alpha(x: 80, y: 26)
        #expect(below[3] > 0)
        #expect(below[3] > above)
        // Black, no stronger than 28%.
        #expect(below[0...2].allSatisfy { $0 <= 2 })
        #expect(below[3] <= 72)
        #expect(pixels.alpha(x: 0, y: 0) == 0)
    }
}
