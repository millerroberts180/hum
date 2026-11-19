import Foundation
import HumCore
@testable import HumUI
import Testing

@Suite("Now status and empty states")
struct NowStatusTests {
    static func resolve(
        app: String? = "Music",
        availability: SourceAvailability = .running,
        permission: AutomationPermission = .granted,
        hasTrack: Bool = false,
        isLaunching: Bool = false
    ) -> NowStatus {
        NowStatus.resolve(appName: app, availability: availability, permission: permission, hasTrack: hasTrack, isLaunching: isLaunching)
    }

    @Test func statusFollowsTheSource() {
        #expect(Self.resolve(app: nil) == .noSources)
        #expect(Self.resolve(availability: .notInstalled) == .noSources)
        #expect(Self.resolve(availability: .notRunning) == .notRunning(app: "Music"))
        #expect(Self.resolve(availability: .notRunning, isLaunching: true) == .launching(app: "Music"))
        #expect(Self.resolve(hasTrack: true) == .ready)
        #expect(Self.resolve() == .nothingPlaying(app: "Music"))
        #expect(Self.resolve(permission: .notDetermined) == .permissionNeeded(app: "Music"))
        #expect(Self.resolve(permission: .denied) == .permissionDenied(app: "Music"))
        // A track is still worth showing when control was denied.
        #expect(Self.resolve(permission: .denied, hasTrack: true) == .ready)
    }

    @Test func eachEmptyStateHasOneAction() {
        let nothing = EmptyStateContent(.nothingPlaying(app: "Music"))
        #expect(nothing.title == "Nothing Playing")
        #expect(nothing.message == "Start music in your music app.")
        #expect(nothing.action == .play)

        let closed = EmptyStateContent(.notRunning(app: "Spotify"))
        #expect(closed.title == "Nothing Playing")
        #expect(closed.action == .play)

        let launching = EmptyStateContent(.launching(app: "Spotify"))
        #expect(launching.title == "Opening Your Music App…")
        #expect(launching.showsSpinner)
        #expect(launching.action == nil)

        let none = EmptyStateContent(.noSources)
        #expect(none.title == "Nothing Playing")
        #expect(none.message == "Start music in your music app.")
        #expect(none.action == nil)
        #expect(EmptyStateContent(.permissionNeeded(app: "Music")).action == .requestPermission)
        #expect(EmptyStateContent(.permissionDenied(app: "Music")).action == .openSettings)
        #expect(EmptyStateContent.Action.openSettings.title == "Open System Settings")
    }

    /// The player never names the music app, nor hints at a search it no
    /// longer has (DESIGN.md §6.2, §10).
    @Test func noEmptyStateNamesTheMusicApp() {
        let statuses: [NowStatus] = [
            .ready, .noSources, .notRunning(app: "Spotify"), .launching(app: "Spotify"),
            .permissionNeeded(app: "Spotify"), .permissionDenied(app: "Spotify"), .nothingPlaying(app: "Spotify"),
            .notRunning(app: "Music"), .permissionDenied(app: "Music"),
        ]
        for status in statuses {
            let content = EmptyStateContent(status)
            let words = [content.title, content.message ?? ""].joined(separator: " ")
            #expect(!words.contains("Spotify"), "\(status)")
            // "Your Music App" is any music app; "Music" alone is the app's name.
            let named = words.replacingOccurrences(of: "music app", with: "", options: .caseInsensitive)
            #expect(!named.contains("Music"), "\(status)")
            #expect(!words.contains("⌘K"), "\(status)")
        }
        #expect(PermissionGuide.bannerMessage == "Hum needs your permission to control your music app.")
    }
}
