import Foundation

/// A run of listening with no gap longer than `SessionBuilder.gap`.
public struct ListeningSession: Hashable, Sendable {
    /// Every listen, oldest first. The last may still be in progress.
    public var listens: [Listen]
    public var start: Date
    public var end: Date
    /// Seconds actually heard.
    public var listened: TimeInterval
    public var songCount: Int
    public var artistCount: Int
    /// Albums in the order they came up, consecutive repeats folded together.
    public var trail: [TrailStop]
    /// Songs that came back within the session, most returns first.
    public var returns: [SongReturn]
    /// Listens beyond the first of each song: high means repeats, low means variety.
    public var repeatCount: Int
    /// Songs heard before this session.
    public var familiarCount: Int
    /// Songs first heard in this session.
    public var newCount: Int
    /// Where listens came from, for the ones whose source said. Largest first.
    public var sourceMix: [SourceShare]
    /// How many listens had a known context.
    public var knownContextCount: Int
    /// For example "Tuesday afternoon listening".
    public var chapterName: String
    public var timeOfDay: TimeOfDay
    /// Whether the session's newest listen is still playing.
    public var isOngoing: Bool

    public init(
        listens: [Listen],
        start: Date,
        end: Date,
        listened: TimeInterval,
        songCount: Int,
        artistCount: Int,
        trail: [TrailStop],
        returns: [SongReturn],
        repeatCount: Int,
        familiarCount: Int,
        newCount: Int,
        sourceMix: [SourceShare],
        knownContextCount: Int,
        chapterName: String,
        timeOfDay: TimeOfDay,
        isOngoing: Bool
    ) {
        self.listens = listens
        self.start = start
        self.end = end
        self.listened = listened
        self.songCount = songCount
        self.artistCount = artistCount
        self.trail = trail
        self.returns = returns
        self.repeatCount = repeatCount
        self.familiarCount = familiarCount
        self.newCount = newCount
        self.sourceMix = sourceMix
        self.knownContextCount = knownContextCount
        self.chapterName = chapterName
        self.timeOfDay = timeOfDay
        self.isOngoing = isOngoing
    }
}

/// One album on a session's trail.
public struct TrailStop: Identifiable, Hashable, Sendable {
    /// Position on the trail; stable while the session grows.
    public var id: Int
    public var album: String
    public var artist: String
    /// The first track heard from it, for artwork and labels.
    public var title: String
    /// That track, which the source can look the album up by.
    public var trackID: TrackID
    public var artworkKey: String
    /// Where that first track played from, which decides how its cover may be
    /// drawn (DESIGN.md §3.6.1).
    public var source: SourceID
    public var listens: Int

    public init(
        id: Int,
        album: String,
        artist: String,
        title: String,
        trackID: TrackID = TrackID(""),
        artworkKey: String,
        source: SourceID,
        listens: Int
    ) {
        self.id = id
        self.album = album
        self.artist = artist
        self.title = title
        self.trackID = trackID
        self.artworkKey = artworkKey
        self.source = source
        self.listens = listens
    }
}

/// A song heard more than once in one session.
public struct SongReturn: Hashable, Sendable {
    public var songKey: String
    public var title: String
    public var artist: String
    public var times: Int

    public init(songKey: String, title: String, artist: String, times: Int) {
        self.songKey = songKey
        self.title = title
        self.artist = artist
        self.times = times
    }
}

/// How many of a session's listens came from one playlist, album, or other context.
public struct SourceShare: Hashable, Sendable {
    public var kind: PlaybackContext.Kind
    public var name: String?
    public var listens: Int

    public init(kind: PlaybackContext.Kind, name: String?, listens: Int) {
        self.kind = kind
        self.name = name
        self.listens = listens
    }

    /// "Late Shift", or the kind when the source gave no name ("your library").
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        switch kind {
        case .playlist: return "a playlist"
        case .album: return "an album"
        case .artist: return "an artist"
        case .queue: return "the queue"
        case .search: return "search"
        case .radio: return "radio"
        case .library: return "your library"
        case .liked: return "your favorites"
        }
    }
}
