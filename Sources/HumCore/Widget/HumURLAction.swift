import Foundation

/// What a widget asks Hum to do, as a `hum://` link (DESIGN.md §7.3).
///
/// Hum is built without Xcode's App Intents tooling, so the transport buttons in
/// medium and large widgets are links to Hum, and a small widget's click shows
/// the player. Hum's `Info.plist` claims the `hum` scheme.
public enum HumURLAction: String, CaseIterable, Sendable {
    case playPause = "play-pause", next, previous, shuffle, `repeat`, show

    public static let scheme = "hum"

    /// The action `url` names: `hum://` and an action's raw value, nothing else.
    /// No path, query, fragment, port or user, so a link can't smuggle in more.
    public init?(url: URL) {
        guard
            url.scheme?.lowercased() == Self.scheme,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.user == nil, components.password == nil, components.port == nil,
            components.path.isEmpty, components.query == nil, components.fragment == nil,
            let host = components.host,
            let action = HumURLAction(rawValue: host)
        else { return nil }
        self = action
    }

    public var url: URL {
        // Every raw value is a valid host, so this always succeeds.
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }
}
