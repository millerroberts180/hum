import Foundation

/// Counts how long the current track has actually been playing, in wall-clock time.
/// Seeking doesn't change the count; pausing stops it.
public struct ListeningTally: Equatable, Sendable {
    public private(set) var trackID: TrackID?
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    public init() {}

    public func listened(at date: Date) -> TimeInterval {
        accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Update for the latest snapshot. Returns the total for the previous track when
    /// the track changed.
    public mutating func update(track: TrackID?, isPlaying: Bool, at date: Date) -> TimeInterval? {
        var finished: TimeInterval?
        if track != trackID {
            finished = trackID == nil ? nil : listened(at: date)
            trackID = track
            accumulated = 0
            runningSince = nil
        }
        if isPlaying, track != nil {
            if runningSince == nil { runningSince = date }
        } else if let since = runningSince {
            accumulated += max(0, date.timeIntervalSince(since))
            runningSince = nil
        }
        return finished
    }

    /// Start the count again for the same track, as when it starts over under
    /// Hum's repeat one. Returns the total heard before.
    public mutating func restart(at date: Date) -> TimeInterval {
        let heard = listened(at: date)
        accumulated = 0
        if runningSince != nil { runningSince = date }
        return heard
    }
}
