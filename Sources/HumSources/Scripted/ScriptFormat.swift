import Foundation
import HumCore

/// Formats numbers for AppleScript source, independent of the user's locale.
enum ScriptFormat {
    static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(0, value.isFinite ? value : 0))
    }

    /// 0...1 to an integer 0...100.
    static func percent(_ value: Double) -> String {
        String(Int((min(1, max(0, value.isFinite ? value : 0)) * 100).rounded()))
    }
}
