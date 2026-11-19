import Foundation

/// Optimistic state for commands that are still in flight.
///
/// When the user presses pause, the UI shows "paused" immediately. A report from the
/// source that was already on its way still says "playing"; without this, the button
/// would flicker back for a moment. Each intent overrides the matching reported field
/// until the source confirms it or the intent's deadline passes, after which the
/// source's word is final.
public struct PendingIntents: Equatable, Sendable {
    public struct Intent<Value: Equatable & Sendable>: Equatable, Sendable {
        public var value: Value
        public var issuedAt: Date
        public var deadline: Date
    }

    /// The fields an intent can hold.
    public enum Field: Hashable, Sendable, CaseIterable {
        case status, seek, volume, shuffle, repeatMode, favorite
    }

    /// What `resolve(_:at:)` found.
    public struct Resolution: Equatable, Sendable {
        /// What the user should see: the report with in-flight intents applied.
        public var snapshot: PlaybackSnapshot
        /// Intents the report agreed with.
        public var confirmed: Set<Field> = []
        /// Intents whose deadline passed without the report agreeing. The display
        /// has reverted to what the source says.
        public var expired: Set<Field> = []
    }

    /// How long an unconfirmed intent stays in force before the display reverts.
    public static let lifetime: TimeInterval = 1.5
    /// A reported position within this distance of a seek target confirms the seek.
    public static let seekTolerance: TimeInterval = 1.5

    public var status: Intent<PlaybackStatus>?
    /// The position the user seeked to, at `issuedAt`.
    public var seek: Intent<TimeInterval>?
    public var volume: Intent<Double>?
    public var shuffle: Intent<Bool>?
    public var repeatMode: Intent<RepeatMode>?
    public var favorite: Intent<Bool>?

    public init() {}

    public var isEmpty: Bool {
        status == nil && seek == nil && volume == nil && shuffle == nil
            && repeatMode == nil && favorite == nil
    }

    /// Record the optimistic effect of `command`, given the snapshot the user saw.
    public mutating func record(_ command: PlaybackCommand, current: PlaybackSnapshot, at date: Date) {
        let deadline = date.addingTimeInterval(Self.lifetime)
        func intent<V>(_ value: V) -> Intent<V> {
            Intent(value: value, issuedAt: date, deadline: deadline)
        }
        switch command {
        case .play:
            status = intent(.playing)
        case .pause:
            status = intent(.paused)
        case .togglePlayPause:
            status = intent(current.status.isPlaying ? .paused : .playing)
        case .seek(let position):
            seek = intent(position)
        case .setVolume(let value):
            volume = intent(value)
        case .setShuffle(let value):
            shuffle = intent(value)
        case .setRepeat(let mode):
            repeatMode = intent(mode)
        case .setFavorite(let value):
            favorite = intent(value)
        case .next, .previous:
            // The next track is unknown until the source reports it. A skip clears
            // intents tied to the old track.
            seek = nil
            favorite = nil
        case .beginScan, .endScan:
            // The position moves at the source's own pace; reports show it.
            seek = nil
        }
    }

    /// The snapshot the user should see: `reported` with in-flight intents applied.
    /// Intents the report confirms, or whose deadline has passed, are removed.
    public mutating func apply(to reported: PlaybackSnapshot, at date: Date) -> PlaybackSnapshot {
        resolve(reported, at: date).snapshot
    }

    /// Like `apply(to:at:)`, also saying which intents were confirmed and which
    /// ran out of time.
    public mutating func resolve(_ reported: PlaybackSnapshot, at date: Date) -> Resolution {
        var result = Resolution(snapshot: reported)

        func note(_ field: Field, _ outcome: Outcome) {
            switch outcome {
            case .confirmed: result.confirmed.insert(field)
            case .expired: result.expired.insert(field)
            case .pending, .none: break
            }
        }
        note(.status, resolve(&status, reported: reported.status, at: date) { result.snapshot.status = $0 })
        note(.volume, resolve(&volume, reported: reported.volume, at: date, matches: { abs($0 - $1) < 0.02 }) {
            result.snapshot.volume = $0
        })
        note(.shuffle, resolve(&shuffle, reported: reported.shuffle, at: date) { result.snapshot.shuffle = $0 })
        note(.repeatMode, resolve(&repeatMode, reported: reported.repeatMode, at: date) {
            result.snapshot.repeatMode = $0
        })
        note(.favorite, resolve(&favorite, reported: reported.isFavorite, at: date) {
            result.snapshot.isFavorite = $0
        })

        if let pending = seek {
            let elapsed = (result.snapshot.status.isPlaying ? max(0, date.timeIntervalSince(pending.issuedAt)) : 0)
            let expected = pending.value + elapsed
            if let reportedPosition = reported.position,
               abs(reportedPosition - expected) <= Self.seekTolerance {
                seek = nil
                result.confirmed.insert(.seek)
            } else if date >= pending.deadline {
                seek = nil
                result.expired.insert(.seek)
            } else {
                result.snapshot.position = expected
                result.snapshot.timestamp = date
            }
        }
        return result
    }

    /// The earliest moment an intent still in force runs out, if any is.
    public var nextDeadline: Date? {
        [status?.deadline, seek?.deadline, volume?.deadline, shuffle?.deadline,
         repeatMode?.deadline, favorite?.deadline].compactMap(\.self).min()
    }

    /// Drop every intent, for example when a command fails.
    public mutating func removeAll() {
        self = PendingIntents()
    }

    private enum Outcome {
        case none, pending, confirmed, expired
    }

    private func resolve<V: Equatable & Sendable>(
        _ intent: inout Intent<V>?,
        reported: V?,
        at date: Date,
        matches: (V, V) -> Bool = { $0 == $1 },
        override: (V) -> Void
    ) -> Outcome {
        guard let pending = intent else { return .none }
        if let reported, matches(reported, pending.value) {
            intent = nil
            return .confirmed
        } else if date >= pending.deadline {
            intent = nil
            return .expired
        } else {
            override(pending.value)
            return .pending
        }
    }
}
