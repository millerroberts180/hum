/// Whether the app behind a source can be reached.
public enum SourceAvailability: String, Sendable, Codable {
    /// The app isn't on this Mac.
    case notInstalled
    /// Installed but not running. Hum never launches it except when the user presses play.
    case notRunning
    case running

    public var isInstalled: Bool { self != .notInstalled }
    public var isRunning: Bool { self == .running }
}
