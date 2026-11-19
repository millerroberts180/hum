import Foundation
import HumCore

/// What Hum does with Music.app's songs beyond Now, with AppleScript: Play Now
/// on Echo's and the History window's songs, Favorite on any song, and the
/// AirPlay devices (DESIGN.md §1.3).
@MainActor
public final class MusicLibrary: LibraryProvider {
    public let sourceID = SourceID.musicApp
    public let displayName = MusicApp.displayName
    public let requiresAppAccess = true
    public var onChange: (@MainActor () -> Void)?

    public let capabilities: SourceCapabilities = [.playItems, .devices, .deviceSwitching, .saveItems]

    private let runScript: @MainActor (String) async throws(PlaybackError) -> ScriptValue

    public init(runner: AppleScriptRunner = .shared) {
        runScript = { script throws(PlaybackError) in try await runner.run(script) }
    }

    /// For tests: answers scripts without reaching Music.
    init(runScript: @escaping @MainActor (String) async throws(PlaybackError) -> ScriptValue) {
        self.runScript = runScript
    }

    // MARK: Playing

    public func play(_ request: PlayRequest) async throws(LibraryError) {
        switch request {
        case .track(let track, let context):
            let playlistID = context?.kind == .playlist ? context?.identifier : nil
            _ = try await run(MusicLibraryScripts.play(track: track.id.rawValue, inPlaylist: playlistID))
        }
    }

    // MARK: Saving

    public func setSaved(_ saved: Bool, track: LibraryTrack) async throws(LibraryError) {
        _ = try await run(MusicLibraryScripts.setFavorite(saved, track: track.id.rawValue))
    }

    public func isSaved(_ track: LibraryTrack) async -> Bool? {
        try? await run(MusicLibraryScripts.isFavorite(track: track.id.rawValue)).bool
    }

    // MARK: Devices

    public func devices() async throws(LibraryError) -> [PlaybackDevice] {
        MusicLibraryParsing.devices(try await run(MusicLibraryScripts.devices))
    }

    public func transfer(to device: PlaybackDevice) async throws(LibraryError) {
        _ = try await run(MusicLibraryScripts.selectDevice(device.id))
    }

    // MARK: Artwork

    public func artworkData(for artwork: LibraryArtwork) async -> Data? {
        let script: String
        if artwork.key.hasPrefix("music:track-art:") {
            script = MusicLibraryScripts.artwork(track: String(artwork.key.dropFirst("music:track-art:".count)))
        } else if artwork.key.hasPrefix("music:playlist-art:") {
            script = MusicLibraryScripts.artwork(playlist: String(artwork.key.dropFirst("music:playlist-art:".count)))
        } else {
            return nil
        }
        return try? await run(script).data
    }

    // MARK: Running scripts

    private func run(_ script: String) async throws(LibraryError) -> ScriptValue {
        let value: ScriptValue
        do {
            value = try await runScript(script)
        } catch {
            HumLog.library.error("Music library script failed: \(Self.logCode(error), privacy: .public)")
            throw LibraryError(error, app: displayName, source: sourceID)
        }
        if ScriptTemplate.isNotRunningMarker(value) { throw LibraryError(.notRunning, app: displayName, source: sourceID) }
        return value
    }

    /// The failure without the script's message, which can name songs.
    static func logCode(_ error: PlaybackError) -> String {
        switch error {
        case .scriptFailed(let code, _): "scriptFailed(\(code))"
        case .unsupported(let command): "unsupported(\(command))"
        default: String(describing: error)
        }
    }
}
