import Foundation
@testable import HumCore
import Testing

/// Settings and launch arguments that name surfaces and sections Hum no longer
/// has still load, and open on what's there now.
@MainActor
@Suite("What earlier versions left behind")
struct OlderSettingsTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("hum-tests-\(UUID().uuidString)", isDirectory: true)
    var file: URL { directory.appendingPathComponent("Settings.json") }

    /// A settings file from when Hum had the Play surface and its library section.
    static let playEraSettings = """
    {"schemaVersion": 1,
     "behavior": {"visibility": "summoned", "alwaysOnTop": false},
     "appearance": {"mode": "dark"},
     "playback": {"preferredSource": "spotify-app", "lastActiveSource": "music-app"},
     "library": {"playTab": "playlists"},
     "history": {"recordsListening": true},
     "window": {"lastSurface": "play"}}
    """

    @Test func playEraSettingsLoad() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(Self.playEraSettings.utf8).write(to: file)
        let store = SettingsStore(fileURL: file)
        #expect(store.quarantinedFile == nil)
        #expect(store.playback.preferredSource == .spotifyApp)
        #expect(store.playback.lastActiveSource == .musicApp)
        // The sections beside the old one keep what they said.
        #expect(store.behavior.visibility == .summoned)
        #expect(store.behavior.alwaysOnTop == false)
        #expect(store.appearance.mode == .dark)
        // Play is gone, so the player opens on Now.
        #expect(store.window.lastSurface == .now)
    }

    /// Saving again doesn't write the library section back, which went with Play.
    @Test func savingDropsTheLibrarySection() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(Self.playEraSettings.utf8).write(to: file)
        let store = SettingsStore(fileURL: file)
        store.appearance.alwaysShowControls = true
        store.flush()
        let saved = try String(contentsOf: file, encoding: .utf8)
        for key in ["\"library\"", "playTab"] {
            #expect(!saved.contains(key), "\(key) written back")
        }
        #expect(saved.contains("spotify-app"))
        #expect(SettingsStore(fileURL: file).playback.preferredSource == .spotifyApp)
    }

    @Test func sourcesReadBackAsThemselves() throws {
        for (stored, id) in [("spotify-app", SourceID.spotifyApp), ("music-app", .musicApp), ("demo", .demo), ("something-new", SourceID("something-new"))] {
            let decoded = try JSONDecoder().decode(SourceID.self, from: Data("\"\(stored)\"".utf8))
            #expect(decoded == id)
            #expect(try JSONEncoder().encode(id) == Data("\"\(stored)\"".utf8))
        }
    }

    /// A script that still asks for Find gets Now, and the rest of what it asked for.
    @Test func removedSurfacesOpenNow() {
        let options = LaunchOptions(arguments: ["Hum", "--demo-attribution", "Spotify", "--surface", "find"], environment: [:])
        #expect(options.demo)
        #expect(options.demoAttribution == "Spotify")
        #expect(options.surface == .now)
        let alone = LaunchOptions(arguments: ["Hum", "--surface", "play"], environment: [:])
        #expect(!alone.demo)
        #expect(alone.surface == .now)
    }
}
