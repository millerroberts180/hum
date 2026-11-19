import Foundation

/// The listen in progress, checkpointed so a crash or a dead battery during sleep
/// loses nothing that was heard. Recovered and finished on the next launch.
public struct PendingListen: Codable, Equatable, Sendable {
    public var trackID: TrackID
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval?
    public var source: SourceID
    public var context: PlaybackContext?
    public var startedAt: Date
    /// The last moment it was heard playing.
    public var lastPlayedAt: Date
    /// Seconds heard up to `lastPlayedAt`.
    public var listened: TimeInterval

    public init(
        track: Track,
        source: SourceID,
        context: PlaybackContext?,
        startedAt: Date,
        lastPlayedAt: Date,
        listened: TimeInterval
    ) {
        trackID = track.id
        title = track.title
        artist = track.artist
        album = track.album
        duration = track.duration
        self.source = source
        self.context = context
        self.startedAt = startedAt
        self.lastPlayedAt = lastPlayedAt
        self.listened = listened
    }

    public var track: Track {
        Track(id: trackID, title: title, artist: artist, album: album, duration: duration)
    }

    /// The finished listen, or `nil` if too little was heard to keep.
    public func finished(exit: PlayRules.Exit, wasPlaying: Bool) -> Listen? {
        guard PlayRules.shouldRecord(listened: listened) else { return nil }
        return Listen(
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            source: source,
            context: context,
            startedAt: startedAt,
            endedAt: max(lastPlayedAt, startedAt),
            listened: listened,
            duration: duration,
            ending: PlayRules.ending(listened: listened, duration: duration, exit: exit, wasPlaying: wasPlaying),
            counts: PlayRules.counts(listened: listened, duration: duration)
        )
    }
}
