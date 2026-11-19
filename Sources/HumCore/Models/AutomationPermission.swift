/// The macOS Automation (Apple Events) permission for one target app.
public enum AutomationPermission: String, Sendable, Codable {
    /// The source doesn't send Apple Events (the demo).
    case notRequired
    /// Not checked yet, usually because the target app isn't running.
    case unknown
    /// macOS hasn't asked the user yet. Hum asks only when the user acts.
    case notDetermined
    case granted
    /// The user turned it off. Only System Settings can turn it back on.
    case denied

    /// Whether Hum may send Apple Events right now without a prompt appearing.
    public var allowsControl: Bool {
        self == .granted || self == .notRequired
    }
}
