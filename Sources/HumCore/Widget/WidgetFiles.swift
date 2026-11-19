import Foundation

/// Where Hum leaves the widget snapshot and its cover, and how both are read and
/// written.
///
/// The folder is fixed: `~/Library/Application Support/Hum/widget/` in the
/// user's real home, **even when `HUM_SUPPORT_DIR` points Hum's other files
/// elsewhere**. The widget extension runs in the App Sandbox, where it can't see
/// Hum's environment, and reads this one folder through its
/// `com.apple.security.temporary-exception.files.home-relative-path.read-only`
/// entitlement (`Resources/HumWidgets/HumWidgets.entitlements`). An App Group
/// would need a team signature, which an ad hoc build doesn't have. Keep the
/// path, the entitlement and `relativePath` in step.
public enum WidgetFiles {
    /// The folder, relative to the home folder, as the entitlement names it.
    public static let relativePath = "Library/Application Support/Hum/widget"
    public static let snapshotName = "snapshot.json"
    /// Covers are written as `cover-<token>.png`, a new name for each cover, so
    /// a snapshot never points at a half-replaced image.
    static let coverPrefix = "cover-"
    static let coverExtension = "png"

    /// `~/Library/Application Support/Hum/widget/`. Inside the sandbox the home
    /// folder Foundation reports is the extension's container, so this asks for
    /// the account's own home instead.
    public static var directory: URL {
        URL(fileURLWithPath: realHome, isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
    }

    private static var realHome: String {
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            return String(cString: home)
        }
        return NSHomeDirectory()
    }

    // MARK: Reading

    /// The snapshot in `directory`, or `nil` when there's none or it isn't a
    /// snapshot at all. Fields it gets wrong fall back one by one.
    public static func readSnapshot(in directory: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(snapshotName)) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// The cover `snapshot` names, if it's there.
    public static func coverURL(for snapshot: WidgetSnapshot, in directory: URL) -> URL? {
        guard let name = snapshot.coverFile, isCoverName(name) else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Writing

    /// Write `cover` (if it's new) and then `snapshot`, each atomically, and
    /// remove covers nothing points at any more. A reader sees either the old
    /// pair or the new one, never a snapshot without its cover.
    ///
    /// - Parameter cover: PNG data for a cover that isn't on disk yet. `nil`
    ///   keeps `snapshot.coverFile` as it is.
    /// - Returns: The snapshot as written, with `coverFile` set for a new cover.
    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot, cover: Data?, to directory: URL) throws -> WidgetSnapshot {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var written = snapshot
        if let cover {
            let name = coverPrefix + UUID().uuidString.lowercased() + "." + coverExtension
            try cover.write(to: directory.appendingPathComponent(name), options: .atomic)
            written.coverFile = name
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(written).write(to: directory.appendingPathComponent(snapshotName), options: .atomic)

        let keep = written.coverFile
        for name in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        where isCoverName(name) && name != keep {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        return written
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    /// A file name this module wrote as a cover: no folders, no other files.
    static func isCoverName(_ name: String) -> Bool {
        name.hasPrefix(coverPrefix) && name.hasSuffix("." + coverExtension) && !name.contains("/")
    }
}
