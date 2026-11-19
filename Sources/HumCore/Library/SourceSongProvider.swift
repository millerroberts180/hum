import Foundation

/// Play Now for a source that can start a song by its ID but has nothing else
/// to offer, as Spotify's app can (DESIGN.md §1.3): Echo's and the History
/// window's songs play through the source itself.
@MainActor
final class SourceSongProvider: LibraryProvider {
    private let source: any PlaybackSource

    init(source: any PlaybackSource) {
        self.source = source
    }

    var sourceID: SourceID { source.id }
    var displayName: String { source.displayName }
    var requiresAppAccess: Bool { true }
    let capabilities: SourceCapabilities = [.playItems]
    var onChange: (@MainActor () -> Void)?

    /// Only songs the app knows by their ID can start: a song imported from
    /// elsewhere has no Play Now.
    func playBlocker(for request: PlayRequest) -> String? {
        guard case .track(let track, _) = request else { return nil }
        return source.canPlaySong(track.id) ? nil : "\(displayName) can’t play this song."
    }

    func play(_ request: PlayRequest) async throws(LibraryError) {
        guard case .track(let track, _) = request else { return }
        if let reason = playBlocker(for: request) { throw .failed(reason) }
        do {
            try await source.playSong(track.id)
        } catch let error as PlaybackError {
            throw LibraryError(error, app: displayName, source: sourceID)
        } catch {
            throw .transient("\(displayName) couldn’t do that.")
        }
    }
}
