import Foundation

/// Everything a source knows about its player at one moment.
///
/// Optional fields mean "unknown", not "off": a distributed notification may carry
/// the track and state but no volume, and the store keeps the last known value.
public struct PlaybackSnapshot: Equatable, Sendable {
    public var track: Track?
    public var status: PlaybackStatus
    /// Seconds into the track at `timestamp`.
    public var position: TimeInterval?
    /// When `position` was sampled. Interpolation runs forward from here.
    public var timestamp: Date
    /// 0...1.
    public var volume: Double?
    public var shuffle: Bool?
    public var repeatMode: RepeatMode?
    public var isFavorite: Bool?
    /// Where the track is playing from, if the source reports it.
    public var context: PlaybackContext?

    public init(
        track: Track? = nil,
        status: PlaybackStatus = .stopped,
        position: TimeInterval? = nil,
        timestamp: Date = .now,
        volume: Double? = nil,
        shuffle: Bool? = nil,
        repeatMode: RepeatMode? = nil,
        isFavorite: Bool? = nil,
        context: PlaybackContext? = nil
    ) {
        self.track = track
        self.status = status
        self.position = position
        self.timestamp = timestamp
        self.volume = volume
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.isFavorite = isFavorite
        self.context = context
    }

    public static let empty = PlaybackSnapshot(timestamp: .distantPast)

    /// Fills unknown fields from an older snapshot of the same track, so a sparse
    /// update (for example a notification without volume) doesn't erase known state.
    public func filling(from older: PlaybackSnapshot?) -> PlaybackSnapshot {
        guard let older else { return self }
        var merged = self
        merged.volume = volume ?? older.volume
        merged.shuffle = shuffle ?? older.shuffle
        merged.repeatMode = repeatMode ?? older.repeatMode
        if track?.id == older.track?.id {
            merged.isFavorite = isFavorite ?? older.isFavorite
            merged.context = context ?? older.context
            if merged.track?.artworkURL == nil {
                merged.track?.artworkURL = older.track?.artworkURL
            }
            if merged.track?.duration == nil {
                merged.track?.duration = older.track?.duration
            }
        }
        return merged
    }
}
