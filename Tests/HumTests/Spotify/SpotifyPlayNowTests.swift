import Foundation
@testable import HumCore
@testable import HumSources
@testable import HumUI
import Testing

/// Spotify's app plays one song by its URI through the library store's
/// built-in one-song provider, and a song it doesn't know offers no Play Now
/// (DESIGN.md §1.3, §4.4).
@MainActor
@Suite("Play Now for Spotify")
struct SpotifyPlayNowTests {
    // MARK: The script

    @Test func playsASongByItsURI() throws {
        let script = try #require(SpotifyApp.playScript(forTrack: TrackID(SpotifyFixture.uri)))
        #expect(script == ScriptTemplate.guarded("com.spotify.client", timeout: 5, #"play track "spotify:track:4uLU6hMCjMI75M1A2tKUQC""#))
        #expect(script.contains(#"tell application id "com.spotify.client""#))
        #expect(SpotifyApp.canPlaySongs)
    }

    nonisolated static let notSpotifySongs = [
        "",
        "spotify:track:",
        "spotify:track:4uLU6hMCjMI75M1A2tKUQ",
        "spotify:track:4uLU6hMCjMI75M1A2tKUQCx",
        "spotify:album:4uLU6hMCjMI75M1A2tKUQC",
        "spotify:playlist:4uLU6hMCjMI75M1A2tKUQC",
        "spotify:local:Artist:Album:Song:200",
        "SPOTIFY:TRACK:4uLU6hMCjMI75M1A2tKUQC",
        " spotify:track:4uLU6hMCjMI75M1A2tKUQC",
        "spotify:track:4uLU6hMCjMI75M1A2tKUQC ",
        "spotify:track:4uLU6hMCjMI75M1A2tKU-C",
        "spotify:track:4uLU6hMCjMI75M1A2tKU_C",
        "spotify:track:4uLU6hMCjMI75M1A2tKU\"C",
        "spotify:track:4uLU6hMCjMI75M1A2tKUQ\"",
        "spotify:track:4uLU6hMCjMI75M1A2tKUQC\" & quit",
        "spotify:track:4uLU6hMCjMI75M1A2tKUQé",
        "spotify:track:4uLU6hMCjMI75M1A2tKUQ\n",
        "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC",
        "music:1234567890",
    ]

    /// Anything but a Spotify song's URI never becomes a script.
    @Test(arguments: notSpotifySongs)
    func anythingButASpotifySongHasNoScript(uri: String) {
        #expect(!SpotifyApp.isTrackURI(uri))
        #expect(SpotifyApp.playScript(forTrack: TrackID(uri)) == nil)
    }

    /// Music plays songs through its own library, not one at a time.
    @Test func onlySpotifyPlaysOneSongAtATime() {
        #expect(!MusicApp.canPlaySongs)
    }

    // MARK: The built-in provider

    @Test func spotifyGetsTheOneSongProvider() throws {
        let fixture = SpotifyFixture()
        let provider = try #require(fixture.library.provider)
        #expect(provider is SourceSongProvider)
        #expect(provider.sourceID == .spotifyApp)
        #expect(provider.displayName == "Spotify")
        #expect(provider.capabilities == [.playItems])
        #expect(provider.requiresAppAccess)
        #expect(fixture.library.sourceName == "Spotify")
    }

    /// A source that can't start songs one at a time gets no provider, so its
    /// songs have no Play Now.
    @Test func aSourceThatCantPlaySongsGetsNoProvider() {
        let fixture = SpotifyFixture()
        fixture.source.playableSong = nil
        let library = LibraryStore(nowPlaying: fixture.nowPlaying, providers: [], sleep: { _ in })
        #expect(library.provider == nil)
        #expect(!library.canPlay(.track(SpotifyFixture.song(), in: nil)))
    }

    @Test func aSpotifyTrackURIPlaysThroughTheProvider() async {
        let fixture = SpotifyFixture()
        let request = PlayRequest.track(SpotifyFixture.song(), in: nil)
        #expect(fixture.library.canPlay(request))
        #expect(fixture.library.playBlocker(for: request) == nil)
        fixture.library.play(request)
        await waitUntil { !fixture.source.playedSongs.isEmpty }
        #expect(fixture.source.playedSongs == [TrackID(SpotifyFixture.uri)])
        await drainMainActor()
        #expect(fixture.library.failure == nil)
    }

    /// The list a song was chosen from doesn't follow it into Spotify.
    @Test func aSongFromAListStillPlaysAlone() async {
        let fixture = SpotifyFixture()
        let context = PlaybackContext(kind: .playlist, name: "Late Shift", identifier: "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")
        fixture.library.play(.track(SpotifyFixture.song(), in: context))
        await waitUntil { !fixture.source.playedSongs.isEmpty }
        #expect(fixture.source.playedSongs == [TrackID(SpotifyFixture.uri)])
    }

    /// A song that isn't Spotify's, such as one imported from elsewhere, has no
    /// Play Now, and if asked anyway nothing reaches Spotify.
    @Test(arguments: ["music:ABC", "spotify:album:4uLU6hMCjMI75M1A2tKUQC", ""])
    func aNonURISongOffersNoPlayNow(id: String) async {
        let fixture = SpotifyFixture()
        let song = LibraryTrack(id: TrackID(id), title: "Elsewhere", artist: "Someone")
        let request = PlayRequest.track(song, in: nil)
        #expect(!fixture.library.canPlay(request))
        #expect(fixture.library.playBlocker(for: request) == "Spotify can’t play this song.")
        #expect(!TrackMenu.song(song, library: fixture.library).actions.contains(.playNow))

        fixture.library.play(request)
        await waitUntil { fixture.library.failure != nil }
        #expect(fixture.library.failure?.message == "Spotify can’t play this song.")
        #expect(fixture.source.playedSongs.isEmpty)
    }

    // MARK: Gates

    /// What Spotify's app answers becomes what the History window says, which
    /// may name the app (DESIGN.md §10).
    @Test func whatSpotifySaysBecomesWhatHumSays() {
        func mapped(_ error: PlaybackError) -> LibraryError {
            LibraryError(error, app: "Spotify", source: .spotifyApp)
        }
        #expect(mapped(.notInstalled) == .unavailable(LibraryUnavailable(
            title: "Spotify Isn’t Installed", message: "Install Spotify, then try again."
        )))
        #expect(mapped(.notRunning) == .unavailable(LibraryUnavailable(
            title: "Spotify Isn’t Open", message: "Open Spotify, then try again.", fix: .openApp(.spotifyApp, name: "Spotify")
        )))
        #expect(mapped(.permissionDenied) == .unavailable(LibraryUnavailable(
            title: "No Access to Spotify",
            message: "Turn on Spotify for Hum in System Settings › Privacy & Security › Automation.",
            fix: .openAutomationSettings
        )))
        #expect(mapped(.permissionNotDetermined) == .unavailable(LibraryUnavailable(
            title: "Allow Access to Spotify",
            message: "Hum needs your permission to control Spotify.",
            fix: .allowAutomation(app: "Spotify")
        )))
        #expect(mapped(.timedOut) == .transient("Spotify took too long to answer."))
        #expect(mapped(.scriptFailed(code: -1728, message: "nope")) == .transient("Spotify couldn’t do that."))
        #expect(mapped(.unsupported(.play)) == .transient("Spotify couldn’t do that."))
        #expect(mapped(.launchFailed) == .transient("Spotify couldn’t do that."))
    }

    /// The gates still stand between Echo and Spotify: each refusal becomes
    /// the banner and its fix, and only a passing failure offers Try Again.
    @Test(arguments: [
        (PlaybackError.permissionDenied, "Turn on Spotify for Hum in System Settings › Privacy & Security › Automation.", LibraryUnavailable.Fix?.some(.openAutomationSettings), false),
        (.permissionNotDetermined, "Hum needs your permission to control Spotify.", .some(.allowAutomation(app: "Spotify")), false),
        (.notRunning, "Open Spotify, then try again.", .some(.openApp(.spotifyApp, name: "Spotify")), false),
        (.timedOut, "Spotify took too long to answer.", nil, true),
    ])
    func aRefusalReachesTheBanner(error: PlaybackError, message: String, fix: LibraryUnavailable.Fix?, canRetry: Bool) async throws {
        let fixture = SpotifyFixture()
        fixture.source.failure = error
        fixture.library.play(.track(SpotifyFixture.song(), in: nil))
        await waitUntil { fixture.library.failure != nil }
        let failure = try #require(fixture.library.failure)
        #expect(failure.message == message)
        #expect(failure.fix == fix)
        #expect(failure.canRetry == canRetry)
        #expect(fixture.source.playedSongs == [TrackID(SpotifyFixture.uri)])
    }
}
