import Foundation

/// The service the demo says it plays from (`--demo-attribution`).
public enum DemoAttribution {
    /// The attribution that makes the demo behave as Spotify does.
    public static let spotifyName = "Spotify"

    /// Whether the demo's attribution names Spotify, compared
    /// case-insensitively. The demo then does what Spotify can and can't
    /// (DESIGN.md §1.3).
    public static func namesSpotify(_ attribution: String?) -> Bool {
        attribution?.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(spotifyName) == .orderedSame
    }
}
