import CoreServices
import Foundation
import HumCore

/// Asks macOS whether Hum may send Apple Events to an app.
enum AutomationPermissionCheck {
    /// - Parameter ask: When `true` and the user hasn't decided yet, macOS shows its
    ///   consent prompt and this call waits for the answer. Pass `true` only in
    ///   response to something the user did.
    @concurrent
    static func determine(bundleIdentifier: String, ask: Bool) async -> AutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        guard let address = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(
            address,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            ask
        )
        return permission(for: status)
    }

    static func permission(for status: OSStatus) -> AutomationPermission {
        switch Int(status) {
        case Int(noErr): .granted
        case -1743: .denied
        case -1744: .notDetermined
        default: .unknown
        }
    }
}
