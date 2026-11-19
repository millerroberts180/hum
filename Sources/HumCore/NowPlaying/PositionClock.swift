import Foundation

/// Computes the playback position locally between reports from the source.
///
/// Sources report the position only occasionally (on a notification or a poll), so
/// the UI never asks the source for it. Instead the clock holds the last known
/// position and the time it was true, and runs forward from there while playing.
public struct PositionClock: Equatable, Sendable {
    /// Position, in seconds, at `anchorDate`.
    public private(set) var anchorPosition: TimeInterval
    public private(set) var anchorDate: Date
    /// Whether time is passing (the player is playing).
    public private(set) var isAdvancing: Bool
    public var duration: TimeInterval?

    /// Reports closer than this to the interpolated position are treated as
    /// measurement noise and ignored, so the progress bar never jitters backward.
    public static let reconcileTolerance: TimeInterval = 0.75

    public init(
        position: TimeInterval = 0,
        at date: Date = .distantPast,
        isAdvancing: Bool = false,
        duration: TimeInterval? = nil
    ) {
        self.anchorPosition = max(0, position)
        self.anchorDate = date
        self.isAdvancing = isAdvancing
        self.duration = duration
    }

    public func position(at date: Date) -> TimeInterval {
        var value = anchorPosition
        if isAdvancing {
            value += max(0, date.timeIntervalSince(anchorDate))
        }
        if let duration, duration > 0 {
            value = min(value, duration)
        }
        return max(0, value)
    }

    /// Fraction of the track played, 0...1, or `nil` without a known duration.
    public func progress(at date: Date) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return position(at: date) / duration
    }

    /// Replace the anchor unconditionally (a new track, a seek, or a state change).
    public mutating func rebase(position: TimeInterval, at date: Date, isAdvancing: Bool) {
        anchorPosition = max(0, position)
        anchorDate = date
        self.isAdvancing = isAdvancing
    }

    /// Change whether time advances, keeping the current position.
    public mutating func setAdvancing(_ advancing: Bool, at date: Date) {
        guard advancing != isAdvancing else { return }
        rebase(position: position(at: date), at: date, isAdvancing: advancing)
    }

    /// Fold in a position reported by the source.
    ///
    /// - Returns: `true` if the report moved the clock (it disagreed by more than the
    ///   tolerance, or the advancing state changed).
    @discardableResult
    public mutating func reconcile(
        reported: TimeInterval,
        at date: Date,
        isAdvancing advancing: Bool,
        tolerance: TimeInterval = PositionClock.reconcileTolerance
    ) -> Bool {
        if advancing != isAdvancing {
            rebase(position: reported, at: date, isAdvancing: advancing)
            return true
        }
        if abs(position(at: date) - reported) > tolerance {
            rebase(position: reported, at: date, isAdvancing: advancing)
            return true
        }
        return false
    }

    /// Seconds until the track ends, if the clock is advancing and the duration is known.
    public func remaining(at date: Date) -> TimeInterval? {
        guard let duration, duration > 0 else { return nil }
        return max(0, duration - position(at: date))
    }
}
