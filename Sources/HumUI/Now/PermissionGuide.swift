import AppKit
import HumCore

/// Plain-language copy and actions for Automation permission.
nonisolated enum PermissionGuide {
    /// Privacy & Security › Automation in System Settings.
    static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    @MainActor
    static func openAutomationSettings() {
        NSWorkspace.shared.open(automationSettingsURL)
    }

    // The player never names the music app (DESIGN.md §10); the Status page
    // does, with the copy below that takes one.

    /// The player's banner (§5.8).
    static let bannerMessage = "Hum needs your permission to control your music app."
    /// Now's empty states, Title Case (§3.3).
    static let playerNeededTitle = "Let Hum Control Your Music App"
    static let playerNeededMessage =
        "macOS will ask once. Hum reads what’s playing and sends play, pause, skip, and volume to your music app. Nothing else."
    static let playerDeniedTitle = "Hum Needs Your Permission"
    static let playerDeniedMessage =
        "Turn on your music app for Hum in System Settings › Privacy & Security › Automation."

    // Titles are Title Case, as empty-state titles are; the banner's is a
    // sentence (DESIGN.md §3.3).
    static func neededTitle(app: String) -> String { "Let Hum Control \(app)" }
    static func neededMessage(app: String) -> String {
        "macOS will ask once. Hum reads what’s playing and sends play, pause, skip, and volume to \(app). Nothing else."
    }

    static func deniedTitle(app: String) -> String { "Hum Can’t Control \(app)" }
    static func deniedBannerTitle(app: String) -> String { "Hum can’t control \(app)" }
    static func deniedMessage(app: String) -> String {
        "Turn on \(app) for Hum in System Settings › Privacy & Security › Automation."
    }
}
