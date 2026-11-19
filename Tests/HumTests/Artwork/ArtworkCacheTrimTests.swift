import CoreGraphics
import Foundation
@testable import HumCore
import ImageIO
import Testing
import UniformTypeIdentifiers

/// The covers on disk stay near their limit however Hum is used: every run
/// trims them once, as well as after every 20 new ones.
@Suite("Artwork cache trimming")
struct ArtworkCacheTrimTests {
    static func png(shade: Double) -> Data {
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: shade, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hum-artwork-trim-\(UUID().uuidString)", isDirectory: true)
    }

    static func files(in folder: URL, extension pathExtension: String) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == pathExtension }
    }

    static func cover(_ key: String, in folder: URL) -> URL {
        folder.appendingPathComponent(ArtworkCache.fileStem(for: key)).appendingPathExtension("jpg")
    }

    /// Mark a cover as last used `secondsAgo`.
    static func age(_ key: String, in folder: URL, secondsAgo: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-secondsAgo)],
            ofItemAtPath: cover(key, in: folder).path
        )
    }

    /// Runs that each add only a few covers, far fewer than the 20 a prune
    /// waits for, used to leave every one behind.
    @Test func shortRunsDontPileUp() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let limit = 5
        var shade = 0.0
        for run in 0 ..< 6 {
            let cache = ArtworkCache(directory: folder, diskLimit: limit)
            for index in 0 ..< 3 {
                shade += 0.04
                #expect(await cache.insert(Self.png(shade: shade), forKey: "run\(run)-\(index)") != nil)
            }
            // At most one run's covers past the limit, never all of them.
            #expect(Self.files(in: folder, extension: "jpg").count <= limit + 2)
        }
        // The next run's first lookup trims to the limit.
        _ = await ArtworkCache(directory: folder, diskLimit: limit).image(forKey: "run5-2")
        #expect(Self.files(in: folder, extension: "jpg").count == limit)
        #expect(Self.files(in: folder, extension: "json").count == limit, "each cover's palette goes with it")
    }

    /// The trim comes after the lookup that starts a run, which marks that
    /// cover as just used, so an old cover asked for again is kept.
    @Test func theCoverARunStartsWithIsKept() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let keys = (0 ..< 5).map { "cover\($0)" }
        let first = ArtworkCache(directory: folder, diskLimit: 3)
        for (index, key) in keys.enumerated() {
            #expect(await first.insert(Self.png(shade: Double(index) / 5), forKey: key) != nil)
        }
        // cover0 the oldest, cover4 the newest.
        for (index, key) in keys.enumerated() {
            try Self.age(key, in: folder, secondsAgo: Double(100 - index))
        }
        #expect(Self.files(in: folder, extension: "jpg").count == 5)

        let next = ArtworkCache(directory: folder, diskLimit: 3)
        #expect(await next.image(forKey: "cover0") != nil)
        let kept = Set(Self.files(in: folder, extension: "jpg").map(\.lastPathComponent))
        let expected = Set(["cover0", "cover3", "cover4"].map { Self.cover($0, in: folder).lastPathComponent })
        #expect(kept == expected)
    }

    /// One trim per run: later lookups in the same run leave the folder alone
    /// until 20 new covers ask for the next.
    @Test func aRunTrimsOnlyOnce() async throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ArtworkCache(directory: folder, diskLimit: 2)
        for index in 0 ..< 4 {
            #expect(await cache.insert(Self.png(shade: Double(index) / 4), forKey: "song\(index)") != nil)
        }
        // The first insert trimmed (one cover, under the limit); the rest wait.
        #expect(Self.files(in: folder, extension: "jpg").count == 4)
        _ = await cache.image(forKey: "song0")
        #expect(Self.files(in: folder, extension: "jpg").count == 4)
    }
}
