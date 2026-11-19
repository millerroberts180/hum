import Foundation

/// Where a song outside Now gets its picture.
///
/// `key` names the image in the thumbnail cache and is unique per picture, so two
/// rows of the same album share one decoded thumbnail. `url` is set when the
/// source hosts the image on the web; sources that hand over bytes directly
/// (Music, the demo) leave it `nil` and answer `LibraryProvider.artworkData(for:)`.
///
/// `source` is where the picture came from, which decides how it may be drawn
/// (DESIGN.md §3.6.1), so a list that mixes sources draws each by its own rules.
/// It's `nil` for art cached before Hum recorded it.
public struct LibraryArtwork: Hashable, Codable, Sendable {
    public var key: String
    public var url: URL?
    public var source: SourceID?

    public init(key: String, url: URL? = nil, source: SourceID? = nil) {
        self.key = key
        self.url = url
        self.source = source
    }
}

/// A song to act on outside Now: one of Echo's or the History window's, which
/// Play Now starts and Favorite saves.
public struct LibraryTrack: Identifiable, Hashable, Codable, Sendable {
    /// The source's own identifier: a Spotify URI, a Music persistent ID.
    public var id: TrackID
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds, when known.
    public var duration: TimeInterval?
    public var artwork: LibraryArtwork?
    public var isExplicit: Bool

    public init(
        id: TrackID,
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval? = nil,
        artwork: LibraryArtwork? = nil,
        isExplicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artwork = artwork
        self.isExplicit = isExplicit
    }

    /// The row for the track that's playing, from what Now knows about it.
    /// `source` is the one playing it, for art made from the track's URL.
    public init(_ track: Track, artwork: LibraryArtwork? = nil, source: SourceID? = nil) {
        self.init(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            artwork: artwork ?? track.artworkURL.map { LibraryArtwork(key: $0.absoluteString, url: $0, source: source) },
            isExplicit: track.isExplicit
        )
    }
}

/// A speaker, computer, or phone the source can play on.
public struct PlaybackDevice: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case computer, speaker, tv, phone, headphones, other
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var isActive: Bool
    /// The source lists it but won't switch to it.
    public var isRestricted: Bool
    /// The Mac Hum runs on, rather than another device the music has moved to.
    public var isThisMac: Bool

    public init(id: String, name: String, kind: Kind, isActive: Bool, isRestricted: Bool = false, isThisMac: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isActive = isActive
        self.isRestricted = isRestricted
        self.isThisMac = isThisMac
    }
}
