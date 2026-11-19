import AppKit
import HumCore
import HumUI

/// About Hum and Hum Help, for the app menu.
enum AppCommands {
    /// About Hum: Settings, on the Hum pane, with Hum's icon, version, and
    /// what it is. It replaces the standard About panel (DESIGN.md §8,
    /// §13.26), so Hum stays a menu-bar app while it's open.
    static func showAbout(openSettings: (SettingsPane?) -> Void) {
        openSettings(.about)
    }

    /// What Hum Help does: open the "Using Hum" guide bundled in `bundle` in
    /// the default browser. Nil when the bundle has none, so Hum Help is
    /// disabled instead of doing nothing; only a build run outside the app
    /// bundle (`swift run`) lacks it.
    static func showHelp(in bundle: Bundle = .main) -> (() -> Void)? {
        guard let url = helpPage(in: bundle) else {
            HumLog.app.notice("The help page isn't in the app bundle, so Hum Help is disabled")
            return nil
        }
        return { NSWorkspace.shared.open(url) }
    }

    /// `Contents/Resources/Help/index.html`, copied there by build-app.sh.
    static func helpPage(in bundle: Bundle) -> URL? {
        bundle.url(forResource: "index", withExtension: "html", subdirectory: "Help")
    }
}
