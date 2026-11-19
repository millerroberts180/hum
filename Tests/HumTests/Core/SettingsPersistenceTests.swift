import Foundation
import HumCore
import Testing

@MainActor
@Suite("Settings persistence")
struct SettingsPersistenceTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("hum-tests-\(UUID().uuidString)", isDirectory: true)
    var file: URL { directory.appendingPathComponent("Settings.json") }

    @Test func roundTripsEverySection() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(fileURL: file)
        store.behavior.visibility = .summoned
        store.behavior.alwaysOnTop = false
        store.appearance.mode = .dark
        store.appearance.accent = .system
        store.shortcuts.togglePlayer = HotKeyChord(keyCode: 4, modifiers: [.control, .option], keyLabel: "H")
        store.playback.preferredSource = .musicApp
        store.playback.repeatOneNoteShown = true
        store.window.lastSurface = .echo
        store.window.placements["main"] = WindowPlacement(offsetX: 12, offsetY: 40, side: 300, surface: .status)
        store.flush()

        let reloaded = SettingsStore(fileURL: file)
        #expect(reloaded.settings == store.settings)
        #expect(reloaded.quarantinedFile == nil)
    }

    @Test func savesAfterAPauseWithoutAFlush() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let sleeper = ManualSleeper()
        let store = SettingsStore(fileURL: file, saveDelay: .milliseconds(400)) { try await sleeper.sleep($0) }
        store.appearance.alwaysShowControls = true
        #expect(store.hasPendingSave)
        await waitUntil { sleeper.waiting == 1 }
        #expect(sleeper.requested == [.milliseconds(400)])
        // Nothing is written until the pause is over.
        #expect(!SettingsStore(fileURL: file).appearance.alwaysShowControls)
        sleeper.elapse()
        await waitUntil { !store.hasPendingSave }
        #expect(!store.hasPendingSave)
        #expect(SettingsStore(fileURL: file).appearance.alwaysShowControls)
    }

    @Test func aMissingFileGivesDefaults() {
        let store = SettingsStore(fileURL: file)
        #expect(store.settings == HumSettings())
        #expect(store.shortcuts.togglePlayer == nil)
        #expect(store.behavior.visibility == .pinned)
        #expect(!store.playback.repeatOneNoteShown)
    }

    /// A file from before the note still loads its sources, and hasn't seen it.
    @Test func aFileFromBeforeTheRepeatOneNoteHasNotSeenIt() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"schemaVersion": 1, "playback": {"preferredSource": "spotify-app", "lastActiveSource": "spotify-app"}}
        """
        try Data(json.utf8).write(to: file)
        let store = SettingsStore(fileURL: file)
        #expect(store.playback.lastActiveSource == .spotifyApp)
        #expect(!store.playback.repeatOneNoteShown)
    }

    @Test func badFieldsFallBackOneByOne() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"schemaVersion": 1,
         "behavior": {"visibility": "sometimes", "alwaysOnTop": false},
         "appearance": {"mode": "dark", "accent": 7},
         "futureSection": {"anything": true}}
        """
        try Data(json.utf8).write(to: file)
        let store = SettingsStore(fileURL: file)
        #expect(store.behavior.visibility == .pinned)
        #expect(store.behavior.alwaysOnTop == false)
        #expect(store.appearance.mode == .dark)
        #expect(store.appearance.accent == AppearanceSettings().accent)
        #expect(store.quarantinedFile == nil)
    }

    @Test func theOldPulseSurfaceNameLoadsAsEcho() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"schemaVersion": 1, "window": {"lastSurface": "pulse"}}
        """
        try Data(json.utf8).write(to: file)
        #expect(SettingsStore(fileURL: file).window.lastSurface == .echo)
    }

    /// Glass, Data and Session were retired on 2026-11-08 (DESIGN.md §13.19).
    /// A file that still names one loads with everything else intact: Hum
    /// opens as Art Only, the style's looks and sizes are dropped, the Data
    /// card's choice is ignored, and none of it is written back.
    @Test(arguments: ["glass", "data", "session"])
    func aFileNamingARetiredStyleLoadsWithEverythingElseIntact(retired: String) throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var saved = HumSettings()
        saved.behavior.visibility = .summoned
        saved.appearance.mode = .dark
        saved.appearance.updateLook(for: .bigArt, in: .dark) { $0.opacity = 0.6 }
        saved.playback.preferredSource = .musicApp
        saved.history.isCollecting = false
        saved.window.lastSurface = .echo
        saved.window.setSize(PlayerSize(width: 320, height: 72), for: .title, on: "display-a")

        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        var appearance = try #require(json["appearance"] as? [String: Any])
        appearance["style"] = retired
        appearance["lastWindowStyle"] = retired
        var overrides = try #require(appearance["overrides"] as? [String: Any])
        overrides["\(retired).light"] = ["opacity": 0.5]
        overrides["\(retired).dark"] = ["cornerRadiusScale": 1.5]
        appearance["overrides"] = overrides
        json["appearance"] = appearance
        json["history"] = ["isCollecting": false, "dataStyleInsight": "rank"]
        var window = try #require(json["window"] as? [String: Any])
        var sizes = try #require(window["styleSizes"] as? [String: [String: Any]])
        sizes["display-a"]?[retired] = ["width": 380, "height": 380]
        window["styleSizes"] = sizes
        json["window"] = window
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        let store = SettingsStore(fileURL: file)
        #expect(store.quarantinedFile == nil)
        #expect(store.appearance.style == .artOnly)
        #expect(store.appearance.lastWindowStyle == .artOnly)
        #expect(store.appearance.overrides.keys.sorted() == ["bigArt.dark"])
        #expect(store.window.styleSizes == ["display-a": ["title": PlayerSize(width: 320, height: 72)]])
        #expect(store.history.isCollecting == false)
        #expect(store.settings == saved)

        store.behavior.alwaysOnTop.toggle()
        store.flush()
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(!written.contains("\"\(retired)\"") && !written.contains("\"\(retired)."))
        #expect(!written.contains("dataStyleInsight"))
    }

    @Test func anUnreadableFileIsMovedAsideNotLost() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        let store = SettingsStore(fileURL: file)
        #expect(store.settings == HumSettings())
        let quarantined = try #require(store.quarantinedFile)
        #expect(FileManager.default.fileExists(atPath: quarantined.path))
        #expect(try String(contentsOf: quarantined, encoding: .utf8) == "not json")
    }

    /// Find's global shortcut went with Find: one saved by an earlier version
    /// is read without harm, takes nothing with it, and isn't written again.
    @Test func aSavedFindShortcutIsReadHarmlesslyAndDropped() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let toggle = HotKeyChord(keyCode: 4, modifiers: [.control, .option], keyLabel: "H")
        var saved = HumSettings()
        saved.shortcuts.togglePlayer = toggle
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        var shortcuts = try #require(json["shortcuts"] as? [String: Any])
        shortcuts["openFind"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            HotKeyChord(keyCode: 3, modifiers: [.control, .option], keyLabel: "F")
        ))
        json["shortcuts"] = shortcuts
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        let store = SettingsStore(fileURL: file)
        #expect(store.quarantinedFile == nil)
        #expect(store.shortcuts.togglePlayer == toggle)
        #expect(store.settings == saved)

        store.behavior.alwaysOnTop.toggle()
        store.flush()
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(!written.contains("openFind"))
        #expect(SettingsStore(fileURL: file).shortcuts.togglePlayer == toggle)
    }
}
