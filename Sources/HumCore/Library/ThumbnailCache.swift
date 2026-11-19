import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A small decoded picture for a row or card.
public final class LibraryThumbnail: @unchecked Sendable {
    public let key: String
    public let cgImage: CGImage

    public init(key: String, cgImage: CGImage) {
        self.key = key
        self.cgImage = cgImage
    }
}

/// Row and card artwork, decoded once at the size it's drawn and kept small.
///
/// Images load only when a row asks (as it appears on screen), each at most once
/// at a time. Memory holds a few hundred; disk keeps re-encoded copies of web
/// images so a relaunch doesn't download them again. Bytes from the source itself
/// (Music, the demo) aren't written to disk, since asking again is cheap.
public actor ThumbnailCache {
    /// The two decode sizes, in pixels: list rows and cards.
    public enum Size: Int, Sendable {
        case row = 128
        case card = 400

        public static func fitting(pixelSide: Int) -> Size {
            pixelSide <= Size.row.rawValue ? .row : .card
        }
    }

    public typealias Download = @Sendable (URL) async -> Data?

    private let directory: URL?
    private let memoryLimit: Int
    private let download: Download
    private var memory: [String: LibraryThumbnail] = [:]
    /// Least recently used first.
    private var recency: [String] = []
    private var loading: [String: Task<LibraryThumbnail?, Never>] = [:]

    public init(directory: URL?, memoryLimit: Int = 300, download: @escaping Download = ThumbnailCache.urlSessionDownload) {
        self.directory = directory
        self.memoryLimit = max(1, memoryLimit)
        self.download = download
    }

    public static func directory(in directories: AppDirectories) -> URL {
        directories.caches.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    public static let urlSessionDownload: Download = { url in
        guard url.scheme == "https" else { return nil }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// The cached thumbnail, if it's already in memory.
    public func cached(_ artwork: LibraryArtwork, size: Size) -> LibraryThumbnail? {
        let key = Self.key(artwork, size)
        guard let thumbnail = memory[key] else { return nil }
        touch(key)
        return thumbnail
    }

    /// The thumbnail, from memory, disk, the web, or `bytes` (for artwork without
    /// a URL), in that order.
    public func thumbnail(
        for artwork: LibraryArtwork,
        size: Size,
        bytes: @escaping @Sendable () async -> Data?
    ) async -> LibraryThumbnail? {
        let key = Self.key(artwork, size)
        if let cached = memory[key] {
            touch(key)
            return cached
        }
        if let pending = loading[key] { return await pending.value }
        let task = Task { await self.load(artwork, size: size, key: key, bytes: bytes) }
        loading[key] = task
        let result = await task.value
        loading[key] = nil
        if let result { remember(result) }
        return result
    }

    /// Keeps a picture Hum already has, such as the cover playing when a context
    /// was observed.
    public func insert(_ image: CGImage, for artwork: LibraryArtwork) {
        for size in [Size.row, .card] {
            guard let scaled = Self.downscale(image, to: size.rawValue) else { continue }
            let thumbnail = LibraryThumbnail(key: Self.key(artwork, size), cgImage: scaled)
            remember(thumbnail)
            writeToDisk(thumbnail)
        }
    }

    private func load(
        _ artwork: LibraryArtwork,
        size: Size,
        key: String,
        bytes: @Sendable () async -> Data?
    ) async -> LibraryThumbnail? {
        if let url = fileURL(for: key), let data = try? Data(contentsOf: url),
           let image = ArtworkImage.decode(data, maxPixelSize: size.rawValue) {
            return LibraryThumbnail(key: key, cgImage: image)
        }
        if let url = artwork.url, let data = await download(url),
           let image = ArtworkImage.decode(data, maxPixelSize: size.rawValue) {
            let thumbnail = LibraryThumbnail(key: key, cgImage: image)
            writeToDisk(thumbnail)
            return thumbnail
        }
        if let data = await bytes(), let image = ArtworkImage.decode(data, maxPixelSize: size.rawValue) {
            return LibraryThumbnail(key: key, cgImage: image)
        }
        return nil
    }

    // MARK: Memory

    private func remember(_ thumbnail: LibraryThumbnail) {
        memory[thumbnail.key] = thumbnail
        touch(thumbnail.key)
        while recency.count > memoryLimit {
            memory[recency.removeFirst()] = nil
        }
    }

    private func touch(_ key: String) {
        if let index = recency.lastIndex(of: key) { recency.remove(at: index) }
        recency.append(key)
    }

    // MARK: Disk

    static func key(_ artwork: LibraryArtwork, _ size: Size) -> String {
        "\(artwork.key)@\(size.rawValue)"
    }

    private func fileURL(for key: String) -> URL? {
        guard let directory else { return nil }
        let stem = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(stem).appendingPathExtension("jpg")
    }

    private func writeToDisk(_ thumbnail: LibraryThumbnail) {
        guard let directory, let url = fileURL(for: thumbnail.key) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, thumbnail.cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        try? (encoded as Data).write(to: url, options: .atomic)
    }

    private static func downscale(_ image: CGImage, to side: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > side else { return image }
        let scale = Double(side) / Double(longest)
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
