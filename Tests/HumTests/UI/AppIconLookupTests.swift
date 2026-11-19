import AppKit
import HumCore
@testable import HumUI
import Testing

/// Status and Settings › Sources show each music app's own icon, Spotify's as
/// well as Music's, read from the installed app's bundle; the generic
/// application icon stands in only when the app isn't installed (DESIGN.md
/// §3.5.7, §13.22). The lookup is injected, so these never depend on what this
/// Mac has installed.
@MainActor
@Suite("Music app icons")
struct AppIconLookupTests {
    /// A lookup over a made-up Mac: `installed` maps bundle identifiers to
    /// where the app is, and every icon is a distinct image to compare by
    /// identity.
    @MainActor
    final class FakeMac {
        var installed: [String: URL]
        /// The paths icons were read from, in order.
        private(set) var iconPaths: [String] = []
        /// One image per path, so each icon can be told apart.
        private var icons: [String: NSImage] = [:]
        let generic = NSImage(size: CGSize(width: 1, height: 1))

        init(installed: [String: URL] = [:]) {
            self.installed = installed
        }

        func icon(atPath path: String) -> NSImage {
            if let icon = icons[path] { return icon }
            let icon = NSImage(size: CGSize(width: 2, height: 2))
            icons[path] = icon
            return icon
        }

        var lookup: AppIconLookup {
            AppIconLookup(
                applicationURL: { [unowned self] in installed[$0] },
                iconForFile: { [unowned self] path in
                    iconPaths.append(path)
                    return icon(atPath: path)
                },
                genericIcon: { [unowned self] in generic }
            )
        }
    }

    static let spotifyPath = "/Applications/Spotify.app"
    static let musicPath = "/System/Applications/Music.app"

    static func fakeMac(spotify: Bool, music: Bool = true) -> FakeMac {
        var installed: [String: URL] = [:]
        if spotify { installed[AppAccessRow.spotify.bundleIdentifier] = URL(fileURLWithPath: spotifyPath) }
        if music { installed[AppAccessRow.music.bundleIdentifier] = URL(fileURLWithPath: musicPath) }
        return FakeMac(installed: installed)
    }

    // MARK: The lookup

    @Test func anInstalledAppsIconComesFromItsBundle() {
        let mac = Self.fakeMac(spotify: true)
        let icon = mac.lookup.icon(bundleIdentifier: "com.spotify.client")
        #expect(mac.iconPaths == [Self.spotifyPath])
        #expect(icon === mac.icon(atPath: Self.spotifyPath))
        #expect(icon !== mac.generic)
    }

    @Test func anAppThatIsntInstalledTakesTheGenericIcon() {
        let mac = Self.fakeMac(spotify: false)
        let icon = mac.lookup.icon(bundleIdentifier: "com.spotify.client")
        #expect(icon === mac.generic)
        // Nothing is read from a bundle that isn't there.
        #expect(mac.iconPaths.isEmpty)
    }

    // MARK: Status

    /// The Connected to card and the Apps rows both draw `.app`, which reads
    /// Spotify's bundle when it's installed.
    @Test func statusShowsSpotifysOwnIconWhenItsInstalled() throws {
        let mac = Self.fakeMac(spotify: true)
        let connection = StatusConnection.make(
            sourceID: .spotifyApp,
            displayName: "Spotify",
            state: Fixtures.state(at: AppAccessRowTests.date),
            isAutomatic: false
        )
        let icon = try #require(connection.icon)
        #expect(icon == .app(bundleIdentifier: "com.spotify.client"))
        #expect(AppIcon.image(for: icon, lookup: mac.lookup) === mac.icon(atPath: Self.spotifyPath))
        #expect(mac.iconPaths == [Self.spotifyPath])
    }

    @Test func statusShowsTheGenericIconWhenSpotifyIsntInstalled() {
        let mac = Self.fakeMac(spotify: false)
        let image = AppIcon.image(for: .app(bundleIdentifier: AppAccessRow.spotify.bundleIdentifier), lookup: mac.lookup)
        #expect(image === mac.generic)
        #expect(mac.iconPaths.isEmpty)
    }

    /// Music keeps its own icon, and the generic case stays generic.
    @Test func statusShowsMusicsIconAndTheGenericOne() {
        let mac = Self.fakeMac(spotify: false)
        #expect(AppIcon.image(for: .app(bundleIdentifier: "com.apple.Music"), lookup: mac.lookup) === mac.icon(atPath: Self.musicPath))
        #expect(AppIcon.image(for: .generic, lookup: mac.lookup) === mac.generic)
    }

    // MARK: Settings › Sources

    @Test func sourcesTilesShowEachAppsOwnIcon() {
        let mac = Self.fakeMac(spotify: true)
        #expect(SourceApps.icon(for: .spotify, lookup: mac.lookup) === mac.icon(atPath: Self.spotifyPath))
        #expect(SourceApps.icon(for: .music, lookup: mac.lookup) === mac.icon(atPath: Self.musicPath))
        #expect(mac.iconPaths == [Self.spotifyPath, Self.musicPath])
    }

    @Test func sourcesTilesShowTheGenericIconForAnAppThatIsntInstalled() {
        let mac = Self.fakeMac(spotify: false, music: false)
        #expect(SourceApps.icon(for: .spotify, lookup: mac.lookup) === mac.generic)
        #expect(SourceApps.icon(for: .music, lookup: mac.lookup) === mac.generic)
        #expect(mac.iconPaths.isEmpty)
    }
}
