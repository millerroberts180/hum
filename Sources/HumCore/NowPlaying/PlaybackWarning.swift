/// A degraded state worth explaining: playback still works, but something the
/// user asked for keeps not happening.
public struct PlaybackWarning: Equatable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

/// Which way the last track change went, so the title can slide in from the
/// matching edge.
public enum TrackChangeDirection: Equatable, Sendable {
    case forward
    case backward
}

/// Counts failures of the same kind in a row. One failure is shrugged off (the
/// display quietly reverts); a second in a row earns an explanation.
struct FailureStreak: Equatable, Sendable {
    /// How many failures in a row of the same kind make a warning.
    static let threshold = 2

    private(set) var kind: String?
    private(set) var count = 0

    /// Record a failure. Returns `true` when this one reaches the threshold.
    mutating func fail(_ failureKind: String) -> Bool {
        if failureKind == kind {
            count += 1
        } else {
            kind = failureKind
            count = 1
        }
        return count == Self.threshold
    }

    mutating func succeed() {
        kind = nil
        count = 0
    }
}
