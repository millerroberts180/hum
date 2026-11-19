import Foundation

/// Paces widget reloads: at most one every `interval` (DESIGN.md §7.3).
///
/// The first change after a quiet spell reloads at once. Changes inside the
/// interval are folded into one reload at its end, which carries the latest
/// state, so the last change always lands. Nothing happens while nothing
/// changes: there is no timer.
public struct WidgetReloadThrottle: Equatable, Sendable {
    public static let defaultInterval: TimeInterval = 2

    public let interval: TimeInterval
    public private(set) var lastReload: Date?
    /// When the folded reload is due, if one is waiting.
    public private(set) var pendingAt: Date?

    public enum Decision: Equatable, Sendable {
        /// Reload now.
        case reloadNow
        /// Reload at this time; schedule a wake-up for it.
        case reload(at: Date)
        /// A reload is already waiting and will carry this change.
        case alreadyPending
    }

    public init(interval: TimeInterval = defaultInterval) {
        self.interval = interval
    }

    /// Something the widgets show changed at `date`.
    public mutating func change(at date: Date) -> Decision {
        if pendingAt != nil { return .alreadyPending }
        guard let lastReload, date.timeIntervalSince(lastReload) < interval else {
            self.lastReload = date
            return .reloadNow
        }
        let due = lastReload.addingTimeInterval(interval)
        pendingAt = due
        return .reload(at: due)
    }

    /// The waiting reload ran at `date`.
    public mutating func didReload(at date: Date) {
        pendingAt = nil
        lastReload = date
    }

    /// Reload now regardless, as Hum quits. Clears any waiting reload.
    public mutating func flush(at date: Date) {
        didReload(at: date)
    }
}
