import CoreServices
import Foundation
import HumCore
@testable import HumSources
@testable import HumUI
import Testing

/// Status's Apps card: whether Hum may control each app, and the one button
/// that changes it (DESIGN.md §6.3).
@MainActor
@Suite("Status's apps")
struct AppAccessRowTests {
    static let date = Date(timeIntervalSinceReferenceDate: 0)

    static func state(_ availability: SourceAvailability, _ permission: AutomationPermission) -> SourceState {
        Fixtures.state(track: nil, status: .stopped, at: date, availability: availability, permission: permission)
    }

    nonisolated static let accesses: [(SourceAvailability, AutomationPermission, AppAccessRow.Access)] = [
        (.notInstalled, .unknown, .notInstalled),
        (.notInstalled, .granted, .notInstalled),
        (.running, .granted, .allowed),
        (.running, .notRequired, .allowed),
        (.running, .denied, .notAllowed),
        (.running, .notDetermined, .notAsked),
        (.running, .unknown, .notAsked),
        // A decision learned while the app ran outlives it.
        (.notRunning, .granted, .allowed),
        (.notRunning, .denied, .notAllowed),
        // A closed app can't be asked.
        (.notRunning, .unknown, .notOpen),
        (.notRunning, .notDetermined, .notOpen),
    ]

    @Test(arguments: accesses)
    func eachAppSaysWhatMacOSAllows(availability: SourceAvailability, permission: AutomationPermission, access: AppAccessRow.Access) {
        #expect(AppAccessRow.access(availability: availability, permission: permission) == access)
        let row = AppAccessRow.make(AppAccessRow.spotify, state: Self.state(availability, permission), isInstalled: true)
        #expect(row.access == access)
    }

    nonisolated static let presentations: [(AppAccessRow.Access, String, AppAccessRow.Glyph?, AppAccessRow.Action?, String?)] = [
        (.allowed, "Allowed", AppAccessRow.Glyph(symbol: "checkmark.circle.fill", tint: .secondaryLabel), nil, nil),
        (.notAllowed, "Not allowed", AppAccessRow.Glyph(symbol: "exclamationmark.triangle.fill", tint: .warning),
         .openSystemSettings, "Open System Settings…"),
        (.notAsked, "Not asked yet", AppAccessRow.Glyph(symbol: "questionmark.circle", tint: .tertiaryLabel), .allow, "Allow…"),
        (.notOpen, "Not open", nil, nil, nil),
        (.notInstalled, "Not installed", nil, nil, nil),
    ]

    @Test(arguments: presentations)
    func eachStateHasItsWordsGlyphAndButton(
        access: AppAccessRow.Access, text: String, glyph: AppAccessRow.Glyph?, action: AppAccessRow.Action?, title: String?
    ) {
        let row = AppAccessRow(app: AppAccessRow.music, access: access)
        #expect(row.statusText == text)
        #expect(row.glyph == glyph)
        #expect(row.action == action)
        #expect(row.actionTitle == title)
        #expect(row.isDimmed == (access == .notInstalled))
    }

    /// macOS answers procNotFound for an app that isn't running. That tells
    /// nothing about the permission, so the row is Not open, with nothing to
    /// click.
    @Test func procNotFoundMeansNotOpen() {
        let permission = AutomationPermissionCheck.permission(for: OSStatus(procNotFound))
        #expect(permission == .unknown)
        let row = AppAccessRow.make(AppAccessRow.music, state: Self.state(.notRunning, permission), isInstalled: true)
        #expect(row.access == .notOpen)
        #expect(row.statusText == "Not open")
        #expect(row.glyph == nil)
        #expect(row.action == nil)
        #expect(row.accessibilityLabel == "Music, not open")
    }

    @Test func macOSsAnswersBecomePermissions() {
        #expect(AutomationPermissionCheck.permission(for: noErr) == .granted)
        #expect(AutomationPermissionCheck.permission(for: OSStatus(errAEEventNotPermitted)) == .denied)
        #expect(AutomationPermissionCheck.permission(for: OSStatus(errAEEventWouldRequireUserConsent)) == .notDetermined)
        #expect(AutomationPermissionCheck.permission(for: OSStatus(procNotFound)) == .unknown)
    }

    /// VoiceOver reads a row as one element, its button as an action.
    @Test func voiceOverReadsTheAppAndItsState() {
        #expect(AppAccessRow(app: AppAccessRow.spotify, access: .notAllowed).accessibilityLabel == "Spotify, not allowed")
        #expect(AppAccessRow(app: AppAccessRow.music, access: .notOpen).accessibilityLabel == "Music, not open")
        #expect(AppAccessRow(app: AppAccessRow.music, access: .notAsked).accessibilityLabel == "Music, not asked yet")
    }

    @Test func musicComesFirstThenSpotify() {
        #expect(AppAccessRow.apps.map(\.id) == [.musicApp, .spotifyApp])
        #expect(AppAccessRow.apps.map(\.bundleIdentifier) == ["com.apple.Music", "com.spotify.client"])
    }

    /// An app Hum has no source for can only be installed or not.
    @Test func anAppWithoutASourceIsNotOpenOrNotInstalled() {
        #expect(AppAccessRow.make(AppAccessRow.spotify, state: nil, isInstalled: true).access == .notOpen)
        #expect(AppAccessRow.make(AppAccessRow.spotify, state: nil, isInstalled: false).access == .notInstalled)
    }

    // MARK: The rows a store shows

    @Test func eachSourceReportsItsOwnState() {
        let music = FakeSource(id: .musicApp, displayName: "Music", state: Self.state(.running, .granted))
        let spotify = FakeSource(id: .spotifyApp, displayName: "Spotify", state: Self.state(.notRunning, .unknown))
        let store = NowPlayingStore(sources: [music, spotify])
        let rows = AppAccessRow.rows(in: store, installed: [], demoAutomation: .denied, demoAllowed: [.spotifyApp])
        #expect(rows.map(\.access) == [.allowed, .notOpen])
    }

    @Test func aChangedPermissionShowsOnTheRow() {
        let spotify = FakeSource(id: .spotifyApp, displayName: "Spotify", state: Self.state(.running, .notDetermined))
        let store = NowPlayingStore(sources: [spotify])
        store.start()
        defer { store.stop() }
        #expect(AppAccessRow.rows(in: store, installed: [.spotifyApp], demoAutomation: nil, demoAllowed: [])[1].access == .notAsked)
        spotify.setPermission(.denied)
        #expect(AppAccessRow.rows(in: store, installed: [.spotifyApp], demoAutomation: nil, demoAllowed: [])[1].access == .notAllowed)
    }

    /// The demo shows the apps as installed on this Mac, each with
    /// `--demo-automation`'s permission, and Allowed without it.
    @Test(arguments: [
        (AutomationPermission?.some(.denied), AppAccessRow.Access.notAllowed),
        (.some(.notDetermined), .notAsked),
        (.some(.granted), .allowed),
        (nil, .allowed),
    ])
    func theDemoShowsTheChosenPermission(demoAutomation: AutomationPermission?, access: AppAccessRow.Access) {
        let store = Self.demoStore()
        let rows = AppAccessRow.rows(in: store, installed: [.musicApp], demoAutomation: demoAutomation, demoAllowed: [])
        #expect(rows.map(\.app) == AppAccessRow.apps)
        #expect(rows.map(\.access) == [access, .notInstalled])
    }

    /// Allow… in the demo allows that app without asking macOS.
    @Test func theDemosAllowAllowsOnlyThatApp() {
        let store = Self.demoStore()
        let rows = AppAccessRow.rows(
            in: store, installed: [.musicApp, .spotifyApp], demoAutomation: .notDetermined, demoAllowed: [.spotifyApp]
        )
        #expect(rows.map(\.access) == [.notAsked, .allowed])
    }

    // MARK: Refreshing

    /// Status asks each app's source what macOS says, and never prompts.
    @Test func refreshingAsksEachAppsSourceWithoutPrompting() async {
        let music = FakeSource(id: .musicApp, displayName: "Music", state: Self.state(.running, .unknown))
        let spotify = FakeSource(id: .spotifyApp, displayName: "Spotify", state: Self.state(.notRunning, .unknown))
        let other = FakeSource(state: Self.state(.running, .unknown))
        let store = NowPlayingStore(sources: [music, spotify, other])
        await AppAccessRow.refreshPermissions(in: store)
        #expect(music.permissionRefreshes == 1)
        #expect(spotify.permissionRefreshes == 1)
        #expect(other.permissionRefreshes == 0)
        #expect(music.permissionRequests + spotify.permissionRequests == 0)
    }

    @Test func theDemoAsksNothing() async {
        let music = FakeSource(id: .musicApp, displayName: "Music", state: Self.state(.running, .unknown))
        let demo = FakeSource(id: .demo, displayName: "Demo", state: Self.state(.running, .notRequired))
        let store = NowPlayingStore(sources: [demo, music])
        await AppAccessRow.refreshPermissions(in: store)
        #expect(music.permissionRefreshes == 0)
        #expect(music.permissionRequests == 0)
    }

    static func demoStore() -> NowPlayingStore {
        NowPlayingStore(sources: [DemoSource(startsPlaying: false, startPosition: 0, latency: .zero)], preferredSourceID: .demo)
    }
}

/// Status's Connected to card: the app Hum follows and what it's doing
/// (DESIGN.md §6.3).
@MainActor
@Suite("Status's connection")
struct StatusConnectionTests {
    static let date = Date(timeIntervalSinceReferenceDate: 0)

    @Test func musicShowsItsOwnIcon() {
        let connection = StatusConnection.make(
            sourceID: .musicApp, displayName: "Music", state: Fixtures.state(at: Self.date), isAutomatic: false
        )
        #expect(connection == StatusConnection(
            icon: .app(bundleIdentifier: "com.apple.Music"), name: "Music", status: "Playing", caption: nil
        ))
    }

    /// Spotify shows its own icon, as Music does (§3.5.7, §13.22).
    @Test func spotifyShowsItsOwnIcon() {
        let connection = StatusConnection.make(
            sourceID: .spotifyApp, displayName: "Spotify", state: Fixtures.state(status: .paused, at: Self.date), isAutomatic: true
        )
        #expect(connection == StatusConnection(
            icon: .app(bundleIdentifier: "com.spotify.client"), name: "Spotify", status: "Paused", caption: "Chosen automatically"
        ))
    }

    @Test func theDemoIsHumsOwn() {
        let connection = StatusConnection.make(
            sourceID: .demo, displayName: "Hum Demo", state: Fixtures.state(at: Self.date), isAutomatic: false
        )
        #expect(connection.icon == .hum)
        #expect(connection.name == "Demo")
    }

    @Test(arguments: [
        (SourceAvailability.running, PlaybackStatus.playing, true, "Playing"),
        (.running, .paused, true, "Paused"),
        (.running, .stopped, true, "Paused"),
        (.running, .stopped, false, "Open, nothing playing"),
        (.running, .paused, false, "Open, nothing playing"),
        (.notRunning, .stopped, false, "Not open"),
        (.notRunning, .paused, true, "Not open"),
        (.notInstalled, .stopped, false, "Not installed"),
    ])
    func theStatusLineSaysWhatTheAppIsDoing(availability: SourceAvailability, status: PlaybackStatus, hasTrack: Bool, line: String) {
        let state = Fixtures.state(
            track: hasTrack ? Fixtures.track() : nil, status: status, at: Self.date, availability: availability
        )
        #expect(StatusConnection.status(state) == line)
    }

    @Test func theCaptionShowsOnlyWhenAutomatic() {
        let state = Fixtures.state(at: Self.date)
        #expect(StatusConnection.make(sourceID: .musicApp, displayName: nil, state: state, isAutomatic: true).caption == "Chosen automatically")
        #expect(StatusConnection.make(sourceID: .musicApp, displayName: nil, state: state, isAutomatic: false).caption == nil)
    }

    @Test func withNoAppItSaysSo() {
        #expect(StatusConnection.noApp == StatusConnection(
            icon: nil, name: "No Music App", status: "Install Music or Spotify, or open one of them.", caption: nil
        ))
        #expect(StatusConnection.make(sourceID: nil, displayName: nil, state: nil, isAutomatic: true) == .noApp)
        let gone = Fixtures.state(track: nil, status: .stopped, at: Self.date, availability: .notInstalled)
        #expect(StatusConnection.make(sourceID: .spotifyApp, displayName: "Spotify", state: gone, isAutomatic: true) == .noApp)
    }

    /// A source Status doesn't know by name keeps its own name.
    @Test func anotherSourceKeepsItsName() {
        let connection = StatusConnection.make(
            sourceID: SourceID("fake"), displayName: "Fake", state: Fixtures.state(at: Self.date), isAutomatic: false
        )
        #expect(connection.icon == .generic)
        #expect(connection.name == "Fake")
    }
}
