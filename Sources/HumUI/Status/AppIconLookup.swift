import AppKit

/// A music app's icon the way macOS shows apps (DESIGN.md §3.5.7): the
/// installed app's own, read from its bundle through `NSWorkspace`, or the
/// system's generic application icon when the app isn't on this Mac.
///
/// Status and Settings › Sources show Music's and Spotify's icons this way, as
/// the system hands them over: never redrawn, recolored, cropped, badged, or
/// kept anywhere but in memory. The player, its menus, the menu-bar item and
/// the widgets never show them (§10).
@MainActor
struct AppIconLookup {
    /// Where the app with this bundle identifier is installed, or nil.
    var applicationURL: (String) -> URL?
    /// The icon Finder shows for the file at this path.
    var iconForFile: (String) -> NSImage
    /// The system's generic application icon.
    var genericIcon: () -> NSImage

    /// Launch Services and the workspace, as Finder asks them.
    static let workspace = AppIconLookup(
        applicationURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        iconForFile: { NSWorkspace.shared.icon(forFile: $0) },
        genericIcon: { NSWorkspace.shared.icon(for: .applicationBundle) }
    )

    /// The app's own icon from its bundle, or the generic application icon
    /// when it isn't installed.
    func icon(bundleIdentifier: String) -> NSImage {
        guard let url = applicationURL(bundleIdentifier) else { return genericIcon() }
        return iconForFile(url.path)
    }
}
