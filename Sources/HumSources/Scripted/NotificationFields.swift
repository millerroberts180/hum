import Foundation
import HumCore

/// Tolerant readers for distributed-notification payloads, whose values arrive as
/// `NSNumber`, `NSString`, or Swift values depending on the sender.
enum NotificationFields {
    static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let double as Double: double
        case let int as Int: Double(int)
        case let int64 as Int64: Double(int64)
        case let string as String: Double(string)
        default: nil
        }
    }

    static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber: number.int64Value
        case let int64 as Int64: int64
        case let int as Int: Int64(int)
        case let uint64 as UInt64: Int64(bitPattern: uint64)
        case let string as String: Int64(string)
        default: nil
        }
    }

    static func nonEmpty(_ value: Any?) -> String? {
        guard let string = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }
        return string
    }
}

extension PlaybackStatus {
    /// Reads a player-state name such as "Playing" or "fast forwarding".
    init?(playerState: String?) {
        switch playerState?.lowercased() {
        case "playing", "fast forwarding", "rewinding": self = .playing
        case "paused": self = .paused
        case "stopped": self = .stopped
        default: return nil
        }
    }
}
