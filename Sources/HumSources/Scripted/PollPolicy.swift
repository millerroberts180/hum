import Foundation
import HumCore

/// Decides when to ask a scripted app for its state.
///
/// Notifications carry most changes, so polling is a safety net, not the main
/// channel. It never runs before Automation is granted. While the app is in
/// front, where shuffle, repeat and volume change without a notification, it
/// runs every `frontmostInterval`, playing or not. Otherwise it never runs while
/// paused or stopped, and while notifications have been reliable it runs only
/// rarely: once shortly after the current track should end, or every
/// `driftInterval` to pick up changes that aren't announced. If a poll ever
/// finds a change that no notification announced, notifications are distrusted
/// and polling tightens until the next notification arrives.
public struct PollPolicy: Equatable, Sendable {
    public static let driftInterval: TimeInterval = 20
    public static let untrustedInterval: TimeInterval = 4
    /// How long after the expected end of a track to check for the next one.
    public static let endOfTrackSlack: TimeInterval = 1.5
    public static let minimumInterval: TimeInterval = 1
    /// While the app is frontmost, so a change made in it shows in Hum within
    /// about a second (§13.34).
    public static let frontmostInterval: TimeInterval = 1

    public private(set) var notificationsTrusted = true

    public init() {}

    /// Seconds until the next poll, or `nil` for no poll.
    public func interval(isPlaying: Bool, isAppFrontmost: Bool = false, canQuery: Bool, remaining: TimeInterval?) -> TimeInterval? {
        guard canQuery else { return nil }
        if isAppFrontmost { return Self.frontmostInterval }
        guard isPlaying else { return nil }
        guard notificationsTrusted else { return Self.untrustedInterval }
        let untilEnd = remaining.map { $0 + Self.endOfTrackSlack } ?? Self.driftInterval
        return max(Self.minimumInterval, min(Self.driftInterval, untilEnd))
    }

    /// A poll found a track or play state that no notification had reported.
    public mutating func pollFoundUnannouncedChange() {
        notificationsTrusted = false
    }

    public mutating func notificationReceived() {
        notificationsTrusted = true
    }

    /// Whether `polled` differs from `known` in a way a notification should have announced.
    public static func isUnannouncedChange(polled: PlaybackSnapshot, known: PlaybackSnapshot) -> Bool {
        polled.track?.id != known.track?.id || polled.status != known.status
    }
}
