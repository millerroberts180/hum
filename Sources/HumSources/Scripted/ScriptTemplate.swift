import HumCore
/// Builds AppleScript that is safe to run at any time.
///
/// Every script first checks that the app is running, so Hum can never launch a
/// music app by querying it, and bounds the wait for a reply.
enum ScriptTemplate {
    /// Returned in place of a result when the target app isn't running.
    static let notRunningMarker = "hum:not-running"

    static func guarded(_ bundleIdentifier: String, timeout: Int = 3, _ body: String) -> String {
        """
        if application id "\(bundleIdentifier)" is running then
        \twith timeout of \(timeout) seconds
        \t\ttell application id "\(bundleIdentifier)"
        \(indent(body, levels: 3))
        \t\tend tell
        \tend timeout
        else
        \treturn "\(notRunningMarker)"
        end if
        """
    }

    static func isNotRunningMarker(_ value: ScriptValue) -> Bool {
        value == .string(notRunningMarker)
    }

    private static func indent(_ body: String, levels: Int) -> String {
        let prefix = String(repeating: "\t", count: levels)
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }
}
