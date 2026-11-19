import Foundation

/// One stretch of listening to one track, as Hum recorded it.
public struct Listen: Identifiable, Hashable, Codable, Sendable {
    /// The row id. Zero until the listen is stored.
    public var id: Int64
    public var trackID: TrackID
    /// Groups the same song across sources and re-releases. See `SongKey`.
    public var songKey: String
    public var title: String
    public var artist: String
    public var album: String
    public var source: SourceID
    /// Where it played from, when the source said. Never guessed.
    public var context: PlaybackContext?
    /// When the track first started playing.
    public var startedAt: Date
    /// When the listen finished, in wall-clock time (pauses included).
    public var endedAt: Date
    /// Seconds actually heard. Paused time and sleep never count.
    public var listened: TimeInterval
    public var duration: TimeInterval?
    public var ending: ListenEnding
    /// Whether this counts as a play (see `PlayRules`).
    public var counts: Bool
    public var origin: ListenOrigin

    public init(
        id: Int64 = 0,
        trackID: TrackID,
        songKey: String? = nil,
        title: String,
        artist: String,
        album: String = "",
        source: SourceID,
        context: PlaybackContext? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        listened: TimeInterval,
        duration: TimeInterval?,
        ending: ListenEnding,
        counts: Bool,
        origin: ListenOrigin = .tracked
    ) {
        self.id = id
        self.trackID = trackID
        self.songKey = songKey ?? SongKey.make(artist: artist, title: title)
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.context = context
        self.startedAt = startedAt
        self.endedAt = endedAt ?? startedAt.addingTimeInterval(listened)
        self.listened = listened
        self.duration = duration
        self.ending = ending
        self.counts = counts
        self.origin = origin
    }

    /// The track as the artwork cache and the sources know it.
    public var track: Track {
        Track(id: trackID, title: title, artist: artist, album: album, duration: duration)
    }

    public var artworkKey: String { track.artworkKey(source: source) }
    public var wasSkipped: Bool { ending == .skipped }
}

/// How a listen finished.
public enum ListenEnding: String, Codable, Sendable, CaseIterable {
    /// Played to (nearly) the end.
    case completed
    /// Left early for another track, soon after starting. See `PlayRules`.
    case skipped
    /// Anything in between: stopped, quit, or left partway through.
    case partial
}

/// Where a listen came from. v1 records `.tracked` listens and imports
/// `.imported` ones from Spotify's data download (`HistoryImport`).
public enum ListenOrigin: String, Codable, Sendable, CaseIterable {
    /// Observed by Hum while it ran.
    case tracked
    /// Brought in from an export file.
    case imported
    /// Reported by a streaming service's own history.
    case service
}
