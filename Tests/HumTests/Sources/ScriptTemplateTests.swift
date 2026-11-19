import Foundation
import HumCore
@testable import HumSources
import Testing

@Suite("Script guards")
struct ScriptTemplateTests {
    @Test func everyScriptChecksTheAppIsRunningFirst() {
        // Querying an app that isn't running would launch it. Every script Hum
        // sends must test first, and only `play` may start an app (through
        // NSWorkspace, not a script).
        let scripts = [SpotifyApp.stateScript, MusicApp.stateScript]
            + [PlaybackCommand.play, .pause, .next, .seek(to: 1), .setVolume(1)].compactMap(SpotifyApp.commandScript(for:))
            + [PlaybackCommand.play, .pause, .next, .seek(to: 1), .setFavorite(true)].compactMap(MusicApp.commandScript(for:))
        for script in scripts {
            let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
            #expect(lines.first?.hasPrefix("if application id \"") == true)
            #expect(lines.first?.hasSuffix("\" is running then") == true)
            #expect(script.contains("with timeout of"))
            #expect(script.contains("return \"\(ScriptTemplate.notRunningMarker)\""))
        }
    }

    @Test func guardedIndentsTheBody() {
        let script = ScriptTemplate.guarded("com.example.player", timeout: 2, "play\nreturn 1")
        #expect(script == """
            if application id "com.example.player" is running then
            \twith timeout of 2 seconds
            \t\ttell application id "com.example.player"
            \t\t\tplay
            \t\t\treturn 1
            \t\tend tell
            \tend timeout
            else
            \treturn "hum:not-running"
            end if
            """)
    }

    @Test func numbersIgnoreTheUserLocale() {
        #expect(ScriptFormat.seconds(12.5) == "12.50")
        #expect(ScriptFormat.seconds(-1) == "0.00")
        #expect(ScriptFormat.seconds(.infinity) == "0.00")
        #expect(ScriptFormat.percent(0.333) == "33")
        #expect(ScriptFormat.percent(2) == "100")
    }

    @Test func appleEventErrorsMapToPlaybackErrors() {
        #expect(PlaybackError(appleEventCode: -1743, message: "") == .permissionDenied)
        #expect(PlaybackError(appleEventCode: -1744, message: "") == .permissionNotDetermined)
        #expect(PlaybackError(appleEventCode: -1712, message: "") == .timedOut)
        #expect(PlaybackError(appleEventCode: -600, message: "") == .notRunning)
        #expect(PlaybackError(appleEventCode: -2700, message: "x") == .scriptFailed(code: -2700, message: "x"))
        #expect(AutomationPermissionCheck.permission(for: noErr) == .granted)
        #expect(AutomationPermissionCheck.permission(for: -1743) == .denied)
        #expect(AutomationPermissionCheck.permission(for: -1744) == .notDetermined)
    }

    @Test func readsAppleEventDescriptors() {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "playing"), at: 1)
        list.insert(NSAppleEventDescriptor(int32: 42), at: 2)
        list.insert(NSAppleEventDescriptor(boolean: true), at: 3)
        list.insert(NSAppleEventDescriptor(double: 1.5), at: 4)
        list.insert(NSAppleEventDescriptor.null(), at: 5)
        let value = ScriptValue(list)
        #expect(value == .list([.string("playing"), .int(42), .bool(true), .double(1.5), .null]))
    }

    @Test func notificationFieldsAreTolerant() {
        #expect(NotificationFields.double("12.5") == 12.5)
        #expect(NotificationFields.double(NSNumber(value: 3)) == 3)
        #expect(NotificationFields.int64(UInt64.max) == -1)
        #expect(NotificationFields.nonEmpty("  ") == nil)
        #expect(NotificationFields.string(NSNumber(value: 7)) == "7")
        #expect(PlaybackStatus(playerState: "Fast Forwarding") == .playing)
        #expect(PlaybackStatus(playerState: "kPSP") == nil)
    }
}
