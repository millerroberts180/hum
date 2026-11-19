import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decoded artwork in memory, plus re-encoded copies and palettes on disk.
///
/// An actor so decoding, palette measurement, and file I/O never run on the main
/// actor. Memory holds the most recently used covers; disk holds a few hundred,
/// pruned oldest first.
public actor ArtworkCache {
    private let directory: URL?
    private let memoryLimit: Int
    private let diskLimit: Int
    private var memory: [String: ArtworkImage] = [:]
    /// Least recently used first.
    private var recency: [String] = []
    private var insertsSincePrune = 0
    /// Whether this run has trimmed the disk yet. Every run trims once, so
    /// runs that each add fewer covers than a prune waits for can't pile up.
    private var hasPrunedThisRun = false

    /// - Parameter directory: Where to keep files, or `nil` for memory only.
    public init(directory: URL?, memoryLimit: Int = 24, diskLimit: Int = 300) {
        self.directory = directory
        self.memoryLimit = max(1, memoryLimit)
        self.diskLimit = max(1, diskLimit)
    }

    public func image(forKey key: String) -> ArtworkImage? {
        // After the lookup, which marks this cover as just used.
        defer { pruneOnceThisRun() }
        if let cached = memory[key] {
            touch(key)
            return cached
        }
        guard let urls = fileURLs(for: key),
              let data = try? Data(contentsOf: urls.image),
              let cgImage = ArtworkImage.decode(data) else { return nil }
        let stored = (try? Data(contentsOf: urls.palette)).flatMap {
            try? JSONDecoder().decode(ArtworkPalette.self, from: $0)
        }
        let palette = stored ?? ArtworkPalette.measure(cgImage)
        if stored == nil {
            // Missing, or written by an older palette format: store the new one so
            // the cover is never measured twice.
            try? JSONEncoder().encode(palette).write(to: urls.palette, options: .atomic)
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: urls.image.path)
        let image = ArtworkImage(key: key, cgImage: cgImage, palette: palette)
        remember(image)
        return image
    }

    /// Decode `data`, measure its palette, and keep it. Returns `nil` for data that
    /// isn't an image.
    @discardableResult
    public func insert(_ data: Data, forKey key: String) -> ArtworkImage? {
        guard let cgImage = ArtworkImage.decode(data) else { return nil }
        let image = ArtworkImage(key: key, cgImage: cgImage, palette: ArtworkPalette.measure(cgImage))
        remember(image)
        writeToDisk(image)
        pruneOnceThisRun()
        return image
    }

    public func removeAll() {
        memory.removeAll()
        recency.removeAll()
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: Memory

    private func remember(_ image: ArtworkImage) {
        memory[image.key] = image
        touch(image.key)
        while recency.count > memoryLimit {
            memory[recency.removeFirst()] = nil
        }
    }

    private func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    // MARK: Disk

    static func fileStem(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURLs(for key: String) -> (image: URL, palette: URL)? {
        guard let directory else { return nil }
        let stem = Self.fileStem(for: key)
        return (
            directory.appendingPathComponent(stem).appendingPathExtension("jpg"),
            directory.appendingPathComponent(stem).appendingPathExtension("json")
        )
    }

    private func writeToDisk(_ image: ArtworkImage) {
        guard let directory, let urls = fileURLs(for: image.key) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoded = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image.cgImage, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return }
            try (encoded as Data).write(to: urls.image, options: .atomic)
            try JSONEncoder().encode(image.palette).write(to: urls.palette, options: .atomic)
        } catch {
            return
        }
        insertsSincePrune += 1
        if insertsSincePrune >= 20 {
            insertsSincePrune = 0
            pruneDisk()
        }
    }

    private func pruneOnceThisRun() {
        guard !hasPrunedThisRun else { return }
        hasPrunedThisRun = true
        insertsSincePrune = 0
        pruneDisk()
    }

    private func pruneDisk() {
        guard let directory else { return }
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        ).filter({ $0.pathExtension == "jpg" }), files.count > diskLimit else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return a < b
        }
        for file in sorted.prefix(files.count - diskLimit) {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: file.deletingPathExtension().appendingPathExtension("json"))
        }
    }
}
