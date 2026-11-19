import Foundation

/// Where Hum keeps its files.
public struct AppDirectories: Sendable {
    public static let bundleIdentifier = "com.millerroberts.hum"

    /// `~/Library/Application Support/com.millerroberts.hum`
    public let applicationSupport: URL
    /// `~/Library/Caches/com.millerroberts.hum`
    public let caches: URL

    public init(applicationSupport: URL, caches: URL) {
        self.applicationSupport = applicationSupport
        self.caches = caches
    }

    /// The user's Library folders, or, when `HUM_SUPPORT_DIR` is set, `Application
    /// Support` and `Caches` folders inside it. The override keeps development and
    /// screenshot runs from sharing data with each other or with real use.
    public static var standard: AppDirectories {
        if let root = ProcessInfo.processInfo.environment["HUM_SUPPORT_DIR"], !root.isEmpty {
            let base = URL(fileURLWithPath: root, isDirectory: true)
            return AppDirectories(
                applicationSupport: base.appendingPathComponent("Application Support", isDirectory: true),
                caches: base.appendingPathComponent("Caches", isDirectory: true)
            )
        }
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return AppDirectories(
            applicationSupport: support.appendingPathComponent(bundleIdentifier, isDirectory: true),
            caches: caches.appendingPathComponent(bundleIdentifier, isDirectory: true)
        )
    }

    /// Demo runs keep their own settings so screenshots never disturb real ones.
    public func settingsFile(demo: Bool) -> URL {
        applicationSupport.appendingPathComponent(demo ? "Settings-Demo.json" : "Settings.json")
    }

    public var artworkCache: URL {
        caches.appendingPathComponent("Artwork", isDirectory: true)
    }
}
