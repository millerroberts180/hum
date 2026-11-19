import Foundation

/// When a listen counts as a play, and how it ended. Pure, so it can be tested
/// without a store or a clock.
public enum PlayRules {
    /// Every play needs at least this much listening.
    public static let minimumPlay: TimeInterval = 30
    /// A play also needs half the song, or this much for long tracks.
    public static let longPlay: TimeInterval = 240
    /// Listens shorter than this aren't recorded at all.
    public static let minimumRecorded: TimeInterval = 2
    /// Listening to this share of a song makes it complete.
    public static let completedShare = 0.9
    /// A skip leaves a song within this many seconds of starting it.
    public static let skipWindow: TimeInterval = 30
    /// A skip leaves at least this much of the song unheard, so a track that
    /// simply ran out isn't called a skip.
    public static let skipMinimumRemaining: TimeInterval = 10

    /// How a listen finished.
    public enum Exit: Equatable, Sendable {
        /// Another track started while this one was playing.
        case changedTrack
        /// Playback stopped, the source went away, or Hum quit.
        case stopped
    }

    /// Whether a listen of `listened` seconds of a `duration`-second track counts.
    public static func counts(listened: TimeInterval, duration: TimeInterval?) -> Bool {
        guard listened >= minimumPlay else { return false }
        if listened >= longPlay { return true }
        guard let duration, duration > 0 else { return false }
        return listened >= duration * 0.5
    }

    /// Classify the end of a listen. Skips are called conservatively: only an early
    /// change to another track, mid-song, when the length is known.
    public static func ending(listened: TimeInterval, duration: TimeInterval?, exit: Exit, wasPlaying: Bool) -> ListenEnding {
        if let duration, duration > 0, listened >= duration * completedShare {
            return .completed
        }
        guard exit == .changedTrack, wasPlaying, let duration, duration > 0 else { return .partial }
        if listened < skipWindow, listened + skipMinimumRemaining < duration {
            return .skipped
        }
        return .partial
    }

    /// Whether a listen is long enough to keep.
    public static func shouldRecord(listened: TimeInterval) -> Bool {
        listened >= minimumRecorded
    }
}
