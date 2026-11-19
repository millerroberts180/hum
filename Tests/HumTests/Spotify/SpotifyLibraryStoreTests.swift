import Foundation
@testable import HumCore
@testable import HumSources
@testable import HumUI
import Testing

/// Spotify's songs in Echo and the History window: the library follows Spotify
/// while it plays, Play Now starts one song, and the menus offer only what
/// Spotify's app can do (DESIGN.md §1.3, §4.4).
@MainActor
@Suite("Spotify in Echo and History")
struct SpotifyLibraryStoreTests {
    static func music(playing: Bool, at date: Date) -> FakeSource {
        FakeSource(
            id: .musicApp,
            displayName: "Music",
            appBundleIdentifier: MusicApp.bundleIdentifier,
            state: Fixtures.state(track: Fixtures.track("music-1"), status: playing ? .playing : .paused, at: date, capabilities: MusicApp.capabilities)
        )
    }

    // MARK: Following Spotify

    @Test func theLibraryFollowsSpotifyWhileItPlays() {
        let clock = TestClock()
        let fixture = SpotifyFixture(others: [Self.music(playing: false, at: clock.now)], otherProviders: [SourcedLibrary(.musicApp)])
        #expect(fixture.nowPlaying.activeSourceID == .spotifyApp)
        #expect(fixture.library.sourceID == .spotifyApp)
        #expect(fixture.library.provider is SourceSongProvider)
        #expect(fixture.library.sourceName == "Spotify")
        #expect(fixture.library.isServing(.spotifyApp))
        #expect(!fixture.library.isServing(.musicApp))
    }

    @Test func theLibraryFollowsSpotifyWhenItsTheChoice() {
        let clock = TestClock()
        let fixture = SpotifyFixture(
            playing: false,
            others: [Self.music(playing: false, at: clock.now)],
            otherProviders: [SourcedLibrary(.musicApp)],
            preferredSourceID: .spotifyApp
        )
        #expect(fixture.library.sourceID == .spotifyApp)
        #expect(fixture.library.provider is SourceSongProvider)
    }

    /// Music plays, so the library follows Music and its own provider.
    @Test func musicKeepsItsProvider() {
        let clock = TestClock()
        let fixture = SpotifyFixture(playing: false, others: [Self.music(playing: true, at: clock.now)], otherProviders: [SourcedLibrary(.musicApp)])
        #expect(fixture.library.sourceID == .musicApp)
        #expect(fixture.library.provider is SourcedLibrary)
    }

    /// Nothing asks macOS for Automation access until a song is played.
    @Test(arguments: [
        (SourceAvailability.running, AutomationPermission.granted),
        (.running, .denied),
        (.running, .notDetermined),
        (.running, .unknown),
        (.notRunning, .granted),
        (.notRunning, .notDetermined),
        (.notInstalled, .unknown),
    ])
    func followingSpotifyAsksNothing(availability: SourceAvailability, permission: AutomationPermission) async {
        let fixture = SpotifyFixture(availability: availability, permission: permission)
        _ = TrackMenu.song(SpotifyFixture.song(), library: fixture.library)
        _ = fixture.library.canPlay(.track(SpotifyFixture.song(), in: nil))
        await drainMainActor()
        #expect(fixture.source.permissionRequests == 0)
        #expect(fixture.source.playedSongs.isEmpty)
    }

    /// A failure belongs to the source it came from: once Music plays and the
    /// library follows it, Spotify's banner is gone. Its fix, taken before
    /// then, still opens Spotify, not Music.
    @Test func spotifysFailureGoesWhenMusicTakesOver() async throws {
        let clock = TestClock()
        let music = Self.music(playing: false, at: clock.now)
        let fixture = SpotifyFixture(playing: false, others: [music], otherProviders: [SourcedLibrary(.musicApp)])
        #expect(fixture.library.sourceID == .spotifyApp)
        fixture.source.failure = .notRunning
        fixture.library.play(.track(SpotifyFixture.song(), in: nil))
        await waitUntil { fixture.library.failure != nil }
        let fix = try #require(fixture.library.failure?.fix)
        #expect(fix == .openApp(.spotifyApp, name: "Spotify"))

        music.push(Fixtures.state(track: Fixtures.track("music-1"), status: .playing, at: clock.now, capabilities: MusicApp.capabilities))
        await waitUntil { fixture.library.sourceID == .musicApp }
        #expect(fixture.library.sourceID == .musicApp)
        #expect(fixture.library.failure == nil)
        #expect(LibraryFixes.appToOpen(fix, library: fixture.library) == SpotifyApp.bundleIdentifier)
        #expect(LibraryFixes.appToOpen(.openApp(.musicApp, name: "Music"), library: fixture.library) == MusicApp.bundleIdentifier)
    }

    // MARK: Menus

    /// A Spotify song in Echo or History: Play Now, then its links. Spotify
    /// can't favorite a song from a list, and Show in names no app (§10).
    @Test func aSpotifySongsMenuIsPlayNowAndItsLinks() {
        let fixture = SpotifyFixture()
        let menu = TrackMenu.song(SpotifyFixture.song(), library: fixture.library)
        #expect(menu.entries == [.action(.playNow), .separator, .action(.copyLink), .action(.reveal)])
        #expect(menu.title(for: .reveal) == "Show in App")
        #expect(menu.title(for: .copyLink) == "Copy Link")
        #expect(!menu.entries.contains { menu.title(for: $0) .contains("Spotify") })
    }

    /// A song Spotify doesn't know by its URI keeps only what Spotify can
    /// point at: no Play Now, and no links for an ID that isn't Spotify's.
    @Test func aSongThatIsntSpotifysHasNoPlayNow() {
        let fixture = SpotifyFixture()
        let menu = TrackMenu.song(LibraryTrack(id: TrackID("music:ABC"), title: "Elsewhere", artist: "Someone"), library: fixture.library)
        #expect(!menu.actions.contains(.playNow))
    }

    @Test func thePlayingSpotifySongsMenuIsItsLinks() throws {
        let fixture = SpotifyFixture()
        let menu = try #require(TrackMenu.current(fixture.nowPlaying))
        #expect(menu.entries == [.action(.copyLink), .action(.reveal)])
        withExtendedLifetime(fixture.library) {}
    }

    /// Rediscover plays a Spotify song from Spotify, and a song heard
    /// elsewhere offers nothing: there's no Find to send it to.
    @Test func rediscoverPlaysOrOffersNothing() {
        let fixture = SpotifyFixture()
        let library = fixture.library
        let heard = TopEntry(
            id: "a", title: "Undertow", subtitle: "Low Tide", plays: 4, listened: 800,
            sampleTrackID: TrackID(SpotifyFixture.uri), sampleSource: .spotifyApp
        )
        let track = { (entry: TopEntry) in
            RediscoverPlay.track(for: entry, activeSource: library.sourceID, canPlayItems: library.capabilities.canPlayItems)
        }
        #expect(track(heard) == LibraryTrack(id: TrackID(SpotifyFixture.uri), title: "Undertow", artist: "Low Tide"))
        var elsewhere = heard
        elsewhere.sampleSource = .musicApp
        #expect(track(elsewhere) == nil)
        #expect(RediscoverPlay.track(for: elsewhere, activeSource: .musicApp, canPlayItems: false) == nil)
        var imported = heard
        imported.sampleTrackID = TrackID("")
        #expect(track(imported) == nil)
    }
}

extension TrackMenu {
    /// The title of an entry, or "" for a separator.
    func title(for entry: Entry) -> String {
        if case .action(let action) = entry { title(for: action) } else { "" }
    }
}
