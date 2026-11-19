import Foundation
import HumCore
@testable import HumSources
import Testing

@Suite("Spotify parsing")
struct SpotifyAppTests {
    let date = Date(timeIntervalSinceReferenceDate: 0)

    @Test func readsAPlaybackNotification() {
        let info: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Track ID": "spotify:track:abc",
            "Name": "Song",
            "Artist": "Band",
            "Album": "Record",
            "Duration": NSNumber(value: 215_000),
            "Playback Position": NSNumber(value: 42.5),
        ]
        let snapshot = SpotifyApp.parseNotification(info, at: date)
        #expect(snapshot.status == .playing)
        #expect(snapshot.track == Track(id: TrackID("spotify:track:abc"), title: "Song", artist: "Band", album: "Record", duration: 215))
        #expect(snapshot.position == 42.5)
        #expect(snapshot.timestamp == date)
        // Notifications don't carry these; nil means "unknown", not "off".
        #expect(snapshot.volume == nil)
        #expect(snapshot.shuffle == nil)
    }

    @Test func aNotificationWithoutATrackIsStopped() {
        let snapshot = SpotifyApp.parseNotification(["Player State": "Paused"], at: date)
        #expect(snapshot.track == nil)
        #expect(snapshot.status == .stopped)
    }

    @Test func toleratesOddValueTypes() {
        let info: [AnyHashable: Any] = ["Player State": "paused", "Track ID": "x", "Duration": "180000", "Playback Position": -3]
        let snapshot = SpotifyApp.parseNotification(info, at: date)
        #expect(snapshot.status == .paused)
        #expect(snapshot.track?.duration == 180)
        #expect(snapshot.position == 0)
    }

    @Test func durationsAreMillisecondsUnlessTooSmall() {
        #expect(SpotifyApp.seconds(fromDuration: 200_000) == 200)
        #expect(SpotifyApp.seconds(fromDuration: 200) == 200)
        #expect(SpotifyApp.seconds(fromDuration: 0) == nil)
        #expect(SpotifyApp.seconds(fromDuration: .nan) == nil)
    }

    @Test func readsTheStateQuery() throws {
        let value = ScriptValue.list([
            .string("playing"), .int(64), .bool(true), .bool(false),
            .string("spotify:track:abc"), .string("Song"), .string("Band"), .string("Record"),
            .int(215_000), .double(12.25), .string("https://example.com/cover.jpg"),
        ])
        let snapshot = try #require(SpotifyApp.parseState(value, at: date))
        #expect(snapshot.status == .playing)
        #expect(snapshot.volume == 0.64)
        #expect(snapshot.shuffle == true)
        #expect(snapshot.repeatMode == .off)
        #expect(snapshot.track?.duration == 215)
        #expect(snapshot.track?.artworkURL == URL(string: "https://example.com/cover.jpg"))
        #expect(snapshot.position == 12.25)
    }

    @Test func aStateWithoutATrackIsStopped() throws {
        let value = ScriptValue.list([.string("paused"), .int(50), .bool(false), .bool(true)])
        let snapshot = try #require(SpotifyApp.parseState(value, at: date))
        #expect(snapshot.track == nil)
        #expect(snapshot.status == .stopped)
        #expect(snapshot.repeatMode == .all)
    }

    @Test func theNotRunningMarkerIsNotAState() {
        #expect(SpotifyApp.parseState(.string(ScriptTemplate.notRunningMarker), at: date) == nil)
    }

    @Test func commandsMatchCapabilities() {
        for command in [PlaybackCommand.play, .pause, .togglePlayPause, .next, .previous, .seek(to: 3), .setVolume(0.5), .setShuffle(true), .setRepeat(.all), .setFavorite(true)] {
            let hasScript = SpotifyApp.commandScript(for: command) != nil
            #expect(hasScript == SpotifyApp.capabilities.supports(command), "\(command)")
        }
        // Repeat one is Hum's: offered, but the app is only ever sent repeat
        // all, and the store starts the song over (DESIGN.md §5.2).
        #expect(SpotifyApp.capabilities.supports(.setRepeat(.one)))
        #expect(SpotifyApp.capabilities.contains(.repeatOneByRestart))
        #expect(SpotifyApp.commandScript(for: .setRepeat(.one)) == nil)
        #expect(SpotifyApp.commandScript(for: .setRepeat(.all))?.contains("set repeating to true") == true)
        #expect(SpotifyApp.commandScript(for: .setVolume(0.555))?.contains("set sound volume to 56") == true)
        #expect(SpotifyApp.commandScript(for: .seek(to: 61.257))?.contains("set player position to 61.26") == true)
    }
}
