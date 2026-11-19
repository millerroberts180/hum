import Foundation
import HumCore
@testable import HumSources
import Testing

@Suite("Music parsing")
struct MusicAppTests {
    let date = Date(timeIntervalSinceReferenceDate: 0)

    @Test func readsAPlayerInfoNotification() {
        let info: [AnyHashable: Any] = [
            "Player State": "Playing",
            "PersistentID": NSNumber(value: Int64(-6_221_381_120_919_042_217)),
            "Name": "Song",
            "Artist": "Band",
            "Album": "Record",
            "Total Time": NSNumber(value: 245_000),
        ]
        let snapshot = MusicApp.parseNotification(info, at: date)
        #expect(snapshot.status == .playing)
        #expect(snapshot.track?.title == "Song")
        #expect(snapshot.track?.duration == 245)
        #expect(snapshot.position == nil)
    }

    @Test func notificationAndScriptIdentifiersAgree() {
        // The notification sends a signed 64-bit number; the script returns hex.
        #expect(MusicApp.hexIdentifier(-6_221_381_120_919_042_217) == "A9A936D5334C8757")
        #expect(MusicApp.hexIdentifier(255) == "00000000000000FF")
        let value = ScriptValue.list([
            .string("playing"), .int(40), .bool(false), .string("one"),
            .string("a9a93a4a8f3f1d57"), .string("Song"), .string("Band"), .string("Record"),
            .double(245.3), .double(3), .bool(true),
        ])
        let snapshot = MusicApp.parseState(value, at: date)
        #expect(snapshot?.track?.id == TrackID("A9A93A4A8F3F1D57"))
        #expect(snapshot?.repeatMode == .one)
        #expect(snapshot?.isFavorite == true)
        #expect(snapshot?.volume == 0.4)
    }

    @Test func aStoppedNotificationHasNoTrack() {
        let snapshot = MusicApp.parseNotification(["Player State": "Stopped", "Name": "Song"], at: date)
        #expect(snapshot.track == nil)
        #expect(snapshot.status == .stopped)
    }

    @Test func missingValuesAreUnknown() {
        let value = ScriptValue.list([
            .string("paused"), .int(40), .bool(false), .string("off"),
            .string("ABC"), .string("Stream"), .string(""), .string(""),
            .null, .double(3), .null,
        ])
        let snapshot = MusicApp.parseState(value, at: date)
        #expect(snapshot?.track?.duration == nil)
        #expect(snapshot?.isFavorite == nil)
        #expect(snapshot?.status == .paused)
    }

    @Test func everyCapabilityHasAScript() {
        for command in [PlaybackCommand.play, .pause, .togglePlayPause, .next, .previous, .seek(to: 3), .setVolume(0.5), .setShuffle(true), .setRepeat(.all), .setRepeat(.one), .setFavorite(true)] {
            #expect(MusicApp.commandScript(for: command) != nil, "\(command)")
            #expect(MusicApp.capabilities.supports(command), "\(command)")
        }
    }
}
