import Foundation
import HumCore

/// A scripted stand-in for a real player: tests push states into it and read back
/// the commands it received.
@MainActor
final class FakeSource: PlaybackSource {
    let id: SourceID
    let displayName: String
    /// The app it stands in for, which Open Spotify and Show in look for.
    let appBundleIdentifier: String?
    var onStateChange: (@MainActor (SourceState) -> Void)?

    private(set) var state: SourceState
    private(set) var performed: [PlaybackCommand] = []
    private(set) var permissionRequests = 0
    private(set) var isStarted = false
    var failure: PlaybackError?
    /// State to adopt after a successful command, as a real source would report it.
    var stateAfterCommand: ((PlaybackCommand, SourceState) -> SourceState)?
    var artworkData: Data?
    /// Copy Link's and Show in's links for a song, as the app it stands in for
    /// makes them. None by default.
    var links: (share: (Track) -> URL?, reveal: (Track) -> URL?)?
    /// Which songs it can start one at a time, as Spotify's app starts a track
    /// URI. None by default.
    var playableSong: ((TrackID) -> Bool)?
    private(set) var playedSongs: [TrackID] = []
    private(set) var permissionRefreshes = 0

    init(id: SourceID = SourceID("fake"), displayName: String = "Fake", appBundleIdentifier: String? = nil, state: SourceState) {
        self.id = id
        self.displayName = displayName
        self.appBundleIdentifier = appBundleIdentifier
        self.state = state
    }

    func push(_ newState: SourceState) {
        state = newState
        onStateChange?(newState)
    }

    func start() { isStarted = true }
    func stop() { isStarted = false }
    func refresh() {}

    func perform(_ command: PlaybackCommand) async throws {
        performed.append(command)
        if let failure { throw failure }
        if let stateAfterCommand {
            push(stateAfterCommand(command, state))
        }
    }

    func requestAutomationPermission() async {
        permissionRequests += 1
    }

    func artwork(for track: Track) async -> Data? { artworkData }

    func shareLink(for track: Track) -> URL? { links?.share(track) }
    func revealURL(for track: Track) -> URL? { links?.reveal(track) }

    var canPlaySongs: Bool { playableSong != nil }
    func canPlaySong(_ id: TrackID) -> Bool { playableSong?(id) ?? false }

    func playSong(_ id: TrackID) async throws {
        playedSongs.append(id)
        if let failure { throw failure }
    }

    func refreshAutomationPermission() async {
        permissionRefreshes += 1
    }

    /// Takes `permission`, as a real source does once macOS answers.
    func setPermission(_ permission: AutomationPermission) {
        var next = state
        next.permission = permission
        push(next)
    }
}

/// A clock tests move by hand.
@MainActor
final class TestClock {
    var now: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 1_000_000)) {
        now = start
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

enum Fixtures {
    static let everything: SourceCapabilities = [
        .playPause, .skipNext, .skipPrevious, .seek, .volume, .shuffle, .repeatAll, .repeatOne, .favorite, .artwork,
    ]

    static func track(_ id: String = "t1", duration: TimeInterval? = 200) -> Track {
        Track(id: TrackID(id), title: "Title \(id)", artist: "Artist", album: "Album", duration: duration)
    }

    static func state(
        track: Track? = Fixtures.track(),
        status: PlaybackStatus = .playing,
        position: TimeInterval? = 10,
        at date: Date,
        availability: SourceAvailability = .running,
        permission: AutomationPermission = .notRequired,
        capabilities: SourceCapabilities = Fixtures.everything,
        volume: Double? = 0.5
    ) -> SourceState {
        SourceState(
            availability: availability,
            permission: permission,
            capabilities: capabilities,
            snapshot: PlaybackSnapshot(track: track, status: status, position: position, timestamp: date, volume: volume)
        )
    }
}
