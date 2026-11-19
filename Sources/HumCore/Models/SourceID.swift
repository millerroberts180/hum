/// Stable identifier for a playback source.
///
/// A struct rather than an enum so a new source can be added without editing
/// this file.
public struct SourceID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// Spotify.app, controlled with Apple Events.
    public static let spotifyApp = SourceID("spotify-app")
    /// Music.app, controlled with Apple Events.
    public static let musicApp = SourceID("music-app")
    /// The fake source used by `--demo`, tests, and screenshots.
    public static let demo = SourceID("demo")
}
