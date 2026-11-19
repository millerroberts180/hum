import CoreGraphics
import Foundation
import HumCore
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Counts how often a closure was asked for bytes, from any task.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func increment() {
        lock.withLock { value += 1 }
    }
}

@Suite("Thumbnail cache")
struct ThumbnailCacheTests {
    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func image(width: Int, height: Int) -> CGImage {
        let data = png(width: width, height: height)
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }

    /// A folder of its own under the temporary directory, removed by the caller.
    static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hum-thumbnails-\(UUID().uuidString)", isDirectory: true)
    }

    static func files(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    static let noDownload: ThumbnailCache.Download = { _ in nil }

    @Test func rowsAndCardsHaveTheirOwnSizes() {
        #expect(ThumbnailCache.Size.fitting(pixelSide: 44) == .row)
        #expect(ThumbnailCache.Size.fitting(pixelSide: 128) == .row)
        #expect(ThumbnailCache.Size.fitting(pixelSide: 129) == .card)
        #expect(ThumbnailCache.Size.fitting(pixelSide: 1200) == .card)
    }

    @Test func decodesAtTheSizeItsDrawn() async throws {
        let cache = ThumbnailCache(directory: nil, download: Self.noDownload)
        let bytes = Self.png(width: 1000, height: 500)
        let row = try #require(await cache.thumbnail(for: LibraryArtwork(key: "a"), size: .row) { bytes })
        #expect(max(row.cgImage.width, row.cgImage.height) <= 128)
        let card = try #require(await cache.thumbnail(for: LibraryArtwork(key: "a"), size: .card) { bytes })
        #expect(max(card.cgImage.width, card.cgImage.height) <= 400)
        #expect(card.cgImage.width > row.cgImage.width)
    }

    @Test func asksOnceThenAnswersFromMemory() async throws {
        let cache = ThumbnailCache(directory: nil, download: Self.noDownload)
        let asked = Counter()
        let bytes = Self.png(width: 64, height: 64)
        let artwork = LibraryArtwork(key: "a")
        #expect(await cache.cached(artwork, size: .row) == nil)
        _ = await cache.thumbnail(for: artwork, size: .row) { asked.increment(); return bytes }
        _ = await cache.thumbnail(for: artwork, size: .row) { asked.increment(); return bytes }
        #expect(asked.count == 1)
        #expect(await cache.cached(artwork, size: .row) != nil)
    }

    @Test func rowsAskingTogetherShareOneLoad() async {
        let cache = ThumbnailCache(directory: nil, download: Self.noDownload)
        let asked = Counter()
        let bytes = Self.png(width: 64, height: 64)
        let artwork = LibraryArtwork(key: "a")
        let load: @Sendable () async -> Data? = {
            asked.increment()
            try? await Task.sleep(for: .milliseconds(50))
            return bytes
        }
        async let first = cache.thumbnail(for: artwork, size: .row, bytes: load)
        async let second = cache.thumbnail(for: artwork, size: .row, bytes: load)
        let results = await [first, second]
        #expect(results.allSatisfy { $0 != nil })
        #expect(asked.count == 1)
    }

    @Test func memoryForgetsTheLeastRecentlyUsed() async {
        let cache = ThumbnailCache(directory: nil, memoryLimit: 2, download: Self.noDownload)
        let bytes = Self.png(width: 32, height: 32)
        let (a, b, c) = (LibraryArtwork(key: "a"), LibraryArtwork(key: "b"), LibraryArtwork(key: "c"))
        _ = await cache.thumbnail(for: a, size: .row) { bytes }
        _ = await cache.thumbnail(for: b, size: .row) { bytes }
        // Looking at "a" again makes "b" the oldest.
        _ = await cache.cached(a, size: .row)
        _ = await cache.thumbnail(for: c, size: .row) { bytes }
        #expect(await cache.cached(a, size: .row) != nil)
        #expect(await cache.cached(b, size: .row) == nil)
        #expect(await cache.cached(c, size: .row) != nil)
    }

    @Test func webImagesAreKeptOnDiskForTheNextLaunch() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let downloads = Counter()
        let bytes = Self.png(width: 300, height: 300)
        let artwork = LibraryArtwork(key: "web", url: URL(string: "https://img.example/cover.jpg"))

        let first = ThumbnailCache(directory: folder) { _ in downloads.increment(); return bytes }
        #expect(await first.thumbnail(for: artwork, size: .row) { nil } != nil)
        #expect(downloads.count == 1)
        #expect(Self.files(in: folder).count == 1)

        // A new cache on the same folder, as after a relaunch, doesn't download.
        let second = ThumbnailCache(directory: folder) { _ in downloads.increment(); return nil }
        #expect(await second.thumbnail(for: artwork, size: .row) { nil } != nil)
        #expect(downloads.count == 1)
    }

    @Test func theSourcesOwnBytesStayOffDisk() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ThumbnailCache(directory: folder, download: Self.noDownload)
        let bytes = Self.png(width: 64, height: 64)
        #expect(await cache.thumbnail(for: LibraryArtwork(key: "music:1"), size: .row) { bytes } != nil)
        #expect(Self.files(in: folder).isEmpty)
    }

    @Test func aFailedDownloadFallsBackToTheSource() async throws {
        let cache = ThumbnailCache(directory: nil, download: Self.noDownload)
        let bytes = Self.png(width: 64, height: 64)
        let artwork = LibraryArtwork(key: "web", url: URL(string: "https://img.example/cover.jpg"))
        #expect(await cache.thumbnail(for: artwork, size: .row) { bytes } != nil)
    }

    @Test func somethingThatIsntAPictureIsntKept() async {
        let cache = ThumbnailCache(directory: nil, download: Self.noDownload)
        let artwork = LibraryArtwork(key: "junk")
        #expect(await cache.thumbnail(for: artwork, size: .row) { Data("not a picture".utf8) } == nil)
        #expect(await cache.cached(artwork, size: .row) == nil)
        // A later answer is still asked for.
        let bytes = Self.png(width: 64, height: 64)
        #expect(await cache.thumbnail(for: artwork, size: .row) { bytes } != nil)
    }

    @Test func aPictureHumHasIsKeptAtBothSizes() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ThumbnailCache(directory: folder, download: Self.noDownload)
        let artwork = LibraryArtwork(key: "observed")
        await cache.insert(Self.image(width: 800, height: 800), for: artwork)
        let row = try #require(await cache.cached(artwork, size: .row))
        let card = try #require(await cache.cached(artwork, size: .card))
        #expect(row.cgImage.width == 128)
        #expect(card.cgImage.width == 400)
        #expect(Self.files(in: folder).count == 2)
    }

    @Test func onlySecureWebAddressesAreDownloaded() async {
        #expect(await ThumbnailCache.urlSessionDownload(URL(string: "http://img.example/cover.jpg")!) == nil)
        #expect(await ThumbnailCache.urlSessionDownload(URL(fileURLWithPath: "/etc/hosts")) == nil)
    }
}
