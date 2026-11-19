import Foundation
import HumCore

/// Track times for display and for VoiceOver.
nonisolated enum TimeFormatting {
    /// "3:07", or "1:02:45" past an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Time left, with a true minus sign: "−1:23".
    static func remaining(_ seconds: TimeInterval) -> String {
        "\u{2212}" + clock(seconds)
    }

    /// Shown for a time that isn't known yet: while a song loads, or for a stream.
    static let unknown = "--:--"

    /// The seek bar's leading label: the time played.
    static func elapsed(_ position: TimeInterval, duration: TimeInterval) -> String {
        duration > 0 ? clock(position) : unknown
    }

    /// The seek bar's trailing label: what's left, or the song's length.
    static func trailing(_ position: TimeInterval, duration: TimeInterval, showing mode: BehaviorSettings.TrailingTime) -> String {
        guard duration > 0 else { return unknown }
        return switch mode {
        case .remaining: remaining(max(0, duration - position))
        case .total: clock(duration)
        }
    }

    /// "1 minute 2 seconds", for VoiceOver. No commas, so "1 minute 2 seconds of
    /// 3 minutes 40 seconds" reads as one phrase.
    static func spoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append(unit(hours, "hour")) }
        if minutes > 0 { parts.append(unit(minutes, "minute")) }
        if secs > 0 || parts.isEmpty { parts.append(unit(secs, "second")) }
        return parts.joined(separator: " ")
    }

    /// The seek bar's spoken value: "1 minute 2 seconds of 3 minutes 40 seconds",
    /// or only the position while the song's length isn't known.
    static func spokenPosition(_ position: TimeInterval, of duration: TimeInterval) -> String {
        duration > 0 ? "\(spoken(position)) of \(spoken(duration))" : spoken(position)
    }

    private static func unit(_ value: Int, _ name: String) -> String {
        "\(value) \(name)\(value == 1 ? "" : "s")"
    }
}
