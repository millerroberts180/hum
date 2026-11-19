import Foundation
import HumCore

/// A fake player for demos, screenshots, and tests.
///
/// Behaves like a well-mannered real source (a little latency, every capability)
/// but never talks to another app. While paused it does no work at all; while
/// playing it keeps a single task that wakes when the current track should end.
@MainActor
public final class DemoSource: PlaybackSource {
    public let id = SourceID.demo
    public let displayName = "Demo"
    public let appBundleIdentifier: String? = nil

    public private(set) var state: SourceState {
        didSet {
            if state != oldValue { onStateChange?(state) }
        }
    }

    public var onStateChange: (@MainActor (SourceState) -> Void)?

    /// Where the current track is playing from, reported in every snapshot.
    public private(set) var context: PlaybackContext?
    /// Supplies artwork for tracks that aren't in the starting playlist.
    /// Consulted before the built-in covers.
    public var artworkOverride: (@MainActor (Track) async -> Data?)?

    public static let capabilities: SourceCapabilities = [
        .playPause, .skipNext, .skipPrevious, .seek, .volume, .shuffle, .repeatAll, .repeatOne, .favorite, .artwork, .scan,
        // The demo library: Play Now from Echo, Favorite on any song, and devices.
        .playItems, .devices, .deviceSwitching, .saveItems,
    ]

    /// What the demo can do while it shows what a Spotify listener sees
    /// (DESIGN.md §1.3): playback with repeat off, all and one, and playing one
    /// song from History, with no Save, devices, queue, playlists, or browsing.
    /// Its repeat one is its own, as Music's is; only the real Spotify needs
    /// Hum's (`.repeatOneByRestart`).
    public static let spotifyCapabilities: SourceCapabilities = [
        .playPause, .skipNext, .skipPrevious, .seek, .volume, .shuffle, .repeatAll, .repeatOne, .artwork, .scan,
        .playItems,
    ]

    /// `capabilities`, or `spotifyCapabilities` while the demo follows Spotify.
    private let offered: SourceCapabilities
    /// Spotify's app doesn't say what a song plays from, so while the demo
    /// follows it, it names no album or playlist either (§6.5).
    private let namesContext: Bool

    /// How fast a held skip button moves through the track.
    static let scanRate = 4.0
    /// How often the position is published while scanning.
    static let scanPublishInterval: Duration = .milliseconds(250)

    private var playlist: [DemoTrack]
    private let latency: Duration
    private let now: @MainActor () -> Date
    private var index: Int
    private var anchorPosition: TimeInterval
    private var anchorDate: Date
    private var status: PlaybackStatus
    private var volume = 0.62
    private var shuffle = false
    private var repeatMode = RepeatMode.off
    private var favorites: Set<TrackID>
    private var trackEndTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    /// Playback speed: 1, or ±`scanRate` while a skip button is held.
    private var rate = 1.0
    private var isStarted = false

    /// - Parameters:
    ///   - startsPlaying: Begin playing rather than paused.
    ///   - followsSpotify: Show what a Spotify listener sees, for
    ///     `--demo-attribution Spotify`.
    ///   - startPosition: Where the first track starts, in seconds.
    ///   - latency: Simulated round trip for each command.
    public init(
        playlist: [DemoTrack] = DemoPlaylist.tracks,
        startsPlaying: Bool = false,
        followsSpotify: Bool = false,
        startPosition: TimeInterval = 47,
        latency: Duration = .milliseconds(60),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        precondition(!playlist.isEmpty, "The demo needs at least one track.")
        self.playlist = playlist
        offered = followsSpotify ? Self.spotifyCapabilities : Self.capabilities
        namesContext = !followsSpotify
        self.latency = latency
        self.now = now
        index = 0
        anchorPosition = startPosition
        anchorDate = now()
        status = startsPlaying ? .playing : .paused
        favorites = [playlist[0].track.id]
        state = SourceState(availability: .running, permission: .notRequired, capabilities: offered)
        state = makeState()
    }

    public func start() {
        HumLog.sources.info("Demo source started")
        isStarted = true
        publish()
    }

    public func stop() {
        isStarted = false
        trackEndTask?.cancel()
        trackEndTask = nil
        scanTask?.cancel()
        scanTask = nil
    }

    public func refresh() {
        publish()
    }

    public func requestAutomationPermission() async {}

    public func perform(_ command: PlaybackCommand) async throws {
        try? await Task.sleep(for: latency)
        let date = now()
        switch command {
        case .play:
            setPlaying(true, at: date)
        case .pause:
            setPlaying(false, at: date)
        case .togglePlayPause:
            setPlaying(!status.isPlaying, at: date)
        case .next:
            advance(by: 1, at: date, automatic: false)
        case .previous:
            if position(at: date) > 3 {
                seek(to: 0, at: date)
            } else {
                advance(by: -1, at: date, automatic: false)
            }
        case .seek(let target):
            seek(to: target, at: date)
        case .setVolume(let value):
            volume = min(1, max(0, value))
        case .setShuffle(let enabled):
            shuffle = enabled
        case .setRepeat(let mode):
            repeatMode = mode
        case .setFavorite(let favorite):
            let id = playlist[index].track.id
            if favorite { favorites.insert(id) } else { favorites.remove(id) }
        case .beginScan(let forward):
            setRate(forward ? Self.scanRate : -Self.scanRate, at: date)
        case .endScan:
            setRate(1, at: date)
        }
        publish()
    }

    public func artwork(for track: Track) async -> Data? {
        if let artworkOverride, let data = await artworkOverride(track) { return data }
        guard let cover = playlist.first(where: { $0.track.id == track.id })?.cover else { return nil }
        return await DemoArtwork.pngData(for: cover)
    }

    // MARK: Playback model

    private var currentTrack: Track { playlist[index].track }
    private var duration: TimeInterval { currentTrack.duration ?? 180 }

    private func position(at date: Date) -> TimeInterval {
        let elapsed = status.isPlaying ? max(0, date.timeIntervalSince(anchorDate)) : 0
        return min(duration, max(0, anchorPosition + elapsed * rate))
    }

    /// Change speed, keeping the position. While scanning, the position is
    /// published a few times a second, since the store's clock runs at normal speed.
    private func setRate(_ newRate: Double, at date: Date) {
        anchorPosition = position(at: date)
        anchorDate = date
        rate = newRate
        scanTask?.cancel()
        scanTask = nil
        guard newRate != 1 else { return }
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.scanPublishInterval)
                guard !Task.isCancelled, let self else { return }
                self.publish()
            }
        }
    }

    private func setPlaying(_ playing: Bool, at date: Date) {
        anchorPosition = position(at: date)
        anchorDate = date
        status = playing ? .playing : .paused
        if !playing, rate != 1 { setRate(1, at: date) }
    }

    private func seek(to target: TimeInterval, at date: Date) {
        anchorPosition = min(duration, max(0, target))
        anchorDate = date
    }

    private func advance(by step: Int, at date: Date, automatic: Bool) {
        if automatic, repeatMode == .one {
            seek(to: 0, at: date)
            return
        }
        var next: Int
        if shuffle, playlist.count > 1, step > 0 {
            next = index
            var generator = SystemRandomNumberGenerator()
            while next == index { next = Int.random(in: playlist.indices, using: &generator) }
        } else {
            next = index + step
        }
        if next >= playlist.count {
            if automatic, repeatMode == .off {
                // End of the playlist: stop at the top, like a real player.
                index = 0
                anchorPosition = 0
                anchorDate = date
                status = .paused
                return
            }
            next = 0
        } else if next < 0 {
            next = playlist.count - 1
        }
        index = next
        anchorPosition = 0
        anchorDate = date
        if rate < 0 { setRate(1, at: date) }
    }

    private func makeState() -> SourceState {
        let date = now()
        var track = currentTrack
        track.duration = duration
        let snapshot = PlaybackSnapshot(
            track: track,
            status: status,
            position: position(at: date),
            timestamp: date,
            volume: volume,
            shuffle: shuffle,
            repeatMode: repeatMode,
            isFavorite: favorites.contains(track.id),
            context: context
        )
        return SourceState(availability: .running, permission: .notRequired, capabilities: offered, snapshot: snapshot)
    }

    private func publish() {
        state = makeState()
        scheduleTrackEnd()
    }

    private func scheduleTrackEnd() {
        trackEndTask?.cancel()
        trackEndTask = nil
        guard isStarted, status.isPlaying, rate > 0 else { return }
        let remaining = max(0.05, (duration - position(at: now())) / rate)
        trackEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            self.advance(by: 1, at: self.now(), automatic: true)
            self.publish()
        }
    }
}

// MARK: Library

extension DemoSource {
    /// Everything in play order: what played, the current track, and what's next.
    public var playOrder: [DemoTrack] { playlist }
    /// The position of the current track in `playOrder`.
    public var currentIndex: Int { index }
    public var favoriteIDs: Set<TrackID> { favorites }

    /// Starts playing `tracks` at `start`, from `context`.
    public func play(_ tracks: [DemoTrack], startingAt start: Int, context: PlaybackContext?) async {
        guard !tracks.isEmpty else { return }
        try? await Task.sleep(for: latency)
        let date = now()
        playlist = tracks
        index = min(max(start, 0), tracks.count - 1)
        self.context = namesContext ? context : nil
        anchorPosition = 0
        anchorDate = date
        if rate != 1 { setRate(1, at: date) }
        status = .playing
        publish()
    }

    /// Keeps everything up to and including the current track and replaces what
    /// follows it.
    public func replaceUpcoming(with tracks: [DemoTrack]) {
        playlist = Array(playlist[...index]) + tracks
        publish()
    }

    public func setContext(_ context: PlaybackContext?) {
        self.context = namesContext ? context : nil
        publish()
    }

    /// Favorites any track, not just the current one.
    public func setFavorite(_ favorite: Bool, for id: TrackID) {
        if favorite { favorites.insert(id) } else { favorites.remove(id) }
        publish()
    }
}
