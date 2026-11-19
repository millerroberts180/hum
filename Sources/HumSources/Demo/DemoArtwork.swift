import CoreGraphics
import Foundation

/// Paints the demo covers in code: photographs, paintings, and type, made with
/// Core Graphics and vImage from a fixed seed. No image assets ship with Hum,
/// and every run paints the same pixels.
public enum DemoArtwork {
    /// PNG bytes for `cover`, `side` pixels square. Runs off the main actor;
    /// each size is painted once and then kept.
    @concurrent
    public static func pngData(for cover: DemoCover, side: Int = 600) async -> Data? {
        ArtStore.shared.png("demo-cover:" + cover.rawValue, side: side) {
            render(cover, side: side)
        }
    }

    /// The cover as an opaque image, `side` pixels square.
    public static func render(_ cover: DemoCover, side: Int) -> CGImage? {
        guard let canvas = ArtCanvas(side: side) else { return nil }
        CoverArt.paint(cover, on: canvas)
        return canvas.makeImage()
    }
}
