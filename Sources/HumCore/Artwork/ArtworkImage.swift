import CoreGraphics
import Foundation
import ImageIO

/// A decoded cover and its palette.
///
/// `@unchecked Sendable` is sound here: every stored property is immutable, and
/// `CGImage` is an immutable, thread-safe Core Graphics object.
public final class ArtworkImage: @unchecked Sendable, Equatable {
    public let key: String
    public let cgImage: CGImage
    public let palette: ArtworkPalette

    public init(key: String, cgImage: CGImage, palette: ArtworkPalette) {
        self.key = key
        self.cgImage = cgImage
        self.palette = palette
    }

    public var pixelSize: CGSize {
        CGSize(width: cgImage.width, height: cgImage.height)
    }

    public static func == (lhs: ArtworkImage, rhs: ArtworkImage) -> Bool {
        lhs === rhs || (lhs.key == rhs.key && lhs.cgImage === rhs.cgImage)
    }

    /// Decode image bytes, downsampling anything larger than `maxPixelSize`.
    public static func decode(_ data: Data, maxPixelSize: Int = 1024) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}
