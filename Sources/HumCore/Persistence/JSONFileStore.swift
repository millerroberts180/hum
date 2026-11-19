import Foundation

/// Small helpers for reading and writing one JSON document safely.
public enum JSONFileStore {
    /// Decode the file at `url`. Returns `nil` if it doesn't exist; throws if it
    /// exists but can't be read or decoded.
    public static func load<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    /// Encode `value` and replace the file atomically, creating folders as needed.
    public static func save<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Move an unreadable file aside so defaults can be written without losing it.
    @discardableResult
    public static func quarantine(_ url: URL, now: Date = .now) -> URL? {
        let stamp = Int(now.timeIntervalSince1970)
        let destination = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp)")
            .appendingPathExtension(url.pathExtension)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
