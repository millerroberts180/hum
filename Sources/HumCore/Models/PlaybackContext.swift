/// Where the current track is playing from, when the source says.
///
/// Sources that can't tell leave `PlaybackSnapshot.context` `nil`; nothing should
/// guess one.
public struct PlaybackContext: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case playlist, album, artist, queue, search, radio, library, liked
    }

    public var kind: Kind
    /// Shown to the user, for example the playlist's name.
    public var name: String?
    /// The source's own identifier for the context, for example a Spotify URI.
    public var identifier: String?

    public init(kind: Kind, name: String? = nil, identifier: String? = nil) {
        self.kind = kind
        self.name = name
        self.identifier = identifier
    }
}
