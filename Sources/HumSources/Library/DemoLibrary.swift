import Foundation
import HumCore

/// The demo's library: Play Now on Echo's and the History window's songs,
/// Favorite on any song, and invented devices to play on, all local.
///
/// It answers after a short delay, as if over the network, so the HUD and
/// "Connecting to …" can be seen. It drives `DemoSource`: Play Now starts the
/// song in the demo's playlist, Evening Mix.
///
/// With `--demo-attribution Spotify` it does what Spotify's app lets other
/// apps do (DESIGN.md §1.3): play one song, and nothing more.
@MainActor
public final class DemoLibrary: LibraryProvider {
    public let sourceID = SourceID.demo
    public let displayName = "Demo"
    public var onChange: (@MainActor () -> Void)?

    private let source: DemoSource
    private let latency: Duration
    private let transferLatency: Duration
    private var devices: [PlaybackDevice]
    /// The attribution names Spotify, so the demo follows Spotify's column
    /// of DESIGN.md §1.3.
    private let followsSpotify: Bool

    /// The playlist the demo plays from.
    static let playlist = PlaybackContext(kind: .playlist, name: "Evening Mix", identifier: "demo-playlist:evening")

    /// - Parameters:
    ///   - playingOn: The device the demo starts playing on, by name, such as
    ///     "kitchen" or "living-room". This Mac when `nil` or unknown.
    ///   - attribution: The service the demo names, from `--demo-attribution`.
    ///   - listLatency: How long a request takes, as if over the network.
    ///   - transferLatency: How long moving to another device takes, long
    ///     enough to see "Connecting to …".
    public init(
        source: DemoSource,
        playingOn device: String? = nil,
        attribution: String? = nil,
        listLatency: Duration = .milliseconds(260),
        transferLatency: Duration = .milliseconds(700)
    ) {
        self.source = source
        followsSpotify = DemoAttribution.namesSpotify(attribution)
        latency = listLatency
        self.transferLatency = transferLatency
        devices = [
            // This Mac, listed by the computer's name.
            PlaybackDevice(id: "demo-device:mac", name: "Studio MacBook Pro", kind: .computer, isActive: true, isThisMac: true),
            PlaybackDevice(id: "demo-device:kitchen", name: "Kitchen", kind: .speaker, isActive: false),
            PlaybackDevice(id: "demo-device:living-room", name: "Living Room TV", kind: .tv, isActive: false),
            PlaybackDevice(id: "demo-device:phone", name: "Phone", kind: .phone, isActive: false),
            PlaybackDevice(id: "demo-device:headphones", name: "Headphones", kind: .headphones, isActive: false),
        ]
        if let device, let start = devices.firstIndex(where: { $0.id == "demo-device:\(device.lowercased())" }) {
            for index in devices.indices { devices[index].isActive = index == start }
        }
        source.setContext(Self.playlist)
    }

    public var capabilities: SourceCapabilities {
        // Spotify's app lets other apps play one song, and nothing more.
        followsSpotify ? [.playItems] : [.playItems, .devices, .deviceSwitching, .saveItems]
    }

    // MARK: Playing

    public func play(_ request: PlayRequest) async throws(LibraryError) {
        guard case .track(let track, _) = request else { return }
        let order = source.playOrder
        guard let start = order.firstIndex(where: { $0.track.id == track.id }) else {
            throw .failed("That song isn’t in the demo.")
        }
        await source.play(order, startingAt: start, context: Self.playlist)
    }

    // MARK: Saving

    public func setSaved(_ saved: Bool, track: LibraryTrack) async throws(LibraryError) {
        guard !followsSpotify else { throw .failed("This music app can’t save songs.") }
        try await respond(after: latency / 3)
        source.setFavorite(saved, for: track.id)
    }

    public func isSaved(_ track: LibraryTrack) async -> Bool? {
        followsSpotify ? nil : source.favoriteIDs.contains(track.id)
    }

    // MARK: Devices

    public func devices() async throws(LibraryError) -> [PlaybackDevice] {
        try await respond(after: latency)
        return devices
    }

    public func transfer(to device: PlaybackDevice) async throws(LibraryError) {
        try await respond(after: transferLatency)
        for index in devices.indices {
            devices[index].isActive = devices[index].id == device.id
        }
    }

    // MARK: Artwork

    public func artworkData(for artwork: LibraryArtwork) async -> Data? {
        guard let cover = Self.cover(forKey: artwork.key) else { return nil }
        return await DemoArtwork.pngData(for: cover, side: 400)
    }

    /// The drawn cover a demo song's artwork key names.
    nonisolated static func cover(forKey key: String) -> DemoCover? {
        let prefix = "demo-cover:"
        guard key.hasPrefix(prefix) else { return nil }
        return DemoCover(rawValue: String(key.dropFirst(prefix.count)))
    }

    /// The drawn cover a song shares with its album, so its rows show the
    /// same one as Now.
    nonisolated static func cover(of track: LibraryTrack) -> DemoCover? {
        track.artwork.flatMap { cover(forKey: $0.key) }
    }

    /// Waits like a network request would.
    private func respond(after latency: Duration) async throws(LibraryError) {
        do {
            try await Task.sleep(for: latency)
        } catch {
            throw .cancelled
        }
    }
}
