import Foundation
import HumCore
@testable import HumSources
import Testing

/// What Hum reads from and sends to Music beyond Now's controls: its AirPlay
/// devices, the playlist a song plays from, and Play Now (DESIGN.md §1.3).
@Suite("Music library parsing")
struct MusicLibraryParsingTests {
    @Test func devicesReadTheirKinds() {
        let value: ScriptValue = .list([
            .list([.string("d1"), .string("d2"), .string("d3")]),
            .list([.string("Computer"), .string("Kitchen"), .string("Living Room")]),
            .list([.string("computer"), .string("HomePod"), .string("Apple TV")]),
            .list([.bool(true), .bool(false), .bool(false)]),
            .list([.bool(true), .bool(true), .bool(false)]),
        ])
        let devices = MusicLibraryParsing.devices(value)
        #expect(devices.map(\.kind) == [.computer, .speaker, .tv])
        #expect(devices.map(\.isActive) == [true, false, false])
        #expect(devices.map(\.isRestricted) == [false, false, true])
    }

    @Test func contextsFollowThePlaylistsClass() {
        #expect(MusicLibraryParsing.context(name: "Library", identifier: "L1", className: "library playlist")
            == PlaybackContext(kind: .library, name: "Library"))
        #expect(MusicLibraryParsing.context(name: "Radio", identifier: "r", className: "radio tuner playlist")?.kind == .radio)
        #expect(MusicLibraryParsing.context(name: "", identifier: "x", className: "user playlist") == nil)
    }

    @Test func stateScriptReportsTheCurrentPlaylist() {
        let value = ScriptValue.list([
            .string("playing"), .int(40), .bool(false), .string("off"),
            .string("a9a93a4a8f3f1d57"), .string("Song"), .string("Band"), .string("Record"),
            .double(245.3), .double(3), .bool(false),
            .string("Evening"), .string("abc123"), .string("user playlist"),
        ])
        let snapshot = MusicApp.parseState(value, at: Date(timeIntervalSinceReferenceDate: 0))
        #expect(snapshot?.context == PlaybackContext(kind: .playlist, name: "Evening", identifier: "ABC123"))
    }

    @Test func scriptsEscapeWhatTheyAreGiven() {
        #expect(MusicLibraryScripts.literal(#"say "hi" \ bye"#) == #""say \"hi\" \\ bye""#)
        #expect(MusicLibraryScripts.play(track: #"a"b"#, inPlaylist: nil).contains(#""a\"b""#))
    }

    /// Play Now starts the song in the playlist it was heard in, when there is
    /// one, so what follows is that playlist.
    @Test func playNowStartsTheSongInItsPlaylist() {
        #expect(MusicLibraryScripts.play(track: "A1B2", inPlaylist: nil) == ScriptTemplate.guarded(
            "com.apple.Music", timeout: 10,
            #"play (first track of library playlist 1 whose persistent ID is "A1B2")"#
        ))
        #expect(MusicLibraryScripts.play(track: "A1B2", inPlaylist: "P9") == ScriptTemplate.guarded(
            "com.apple.Music", timeout: 10,
            #"play (first track of (first playlist whose persistent ID is "P9") whose persistent ID is "A1B2")"#
        ))
    }

    @MainActor
    @Test func libraryErrorsExplainTheFix() {
        func mapped(_ error: PlaybackError) -> LibraryError {
            LibraryError(error, app: "Music", source: .musicApp)
        }
        guard case .unavailable(let notRunning) = mapped(.notRunning) else { Issue.record("Expected unavailable"); return }
        #expect(notRunning.fix == .openApp(.musicApp, name: "Music"))
        guard case .unavailable(let denied) = mapped(.permissionDenied) else { Issue.record("Expected unavailable"); return }
        #expect(denied.fix == .openAutomationSettings)
        #expect(mapped(.timedOut) == .transient("Music took too long to answer."))
    }
}
