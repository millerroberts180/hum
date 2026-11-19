import Foundation

/// Metadata for one playable item, as reported by a source.
public struct Track: Identifiable, Hashable, Sendable {
    public var id: TrackID
    public var title: String
    public var artist: String
    public var album: String
    /// Length in seconds, when the source knows it.
    public var duration: TimeInterval?
    /// A remote image the source advertises for this track. Sources that hand over
    /// image bytes directly (Music.app, the demo) leave this `nil`.
    public var artworkURL: URL?
    /// Whether the source marks the song explicit. `false` where it can't say:
    /// Music's and Spotify.app's scripting don't report it.
    public var isExplicit: Bool

    public init(
        id: TrackID,
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval? = nil,
        artworkURL: URL? = nil,
        isExplicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.isExplicit = isExplicit
    }

    /// The key the artwork cache stores this track's image under.
    ///
    /// Deliberately independent of `artworkURL`: a source may learn the URL a moment
    /// after the track itself, and the image shouldn't be fetched twice.
    public func artworkKey(source: SourceID) -> String {
        source.rawValue + ":" + id.rawValue
    }
}
