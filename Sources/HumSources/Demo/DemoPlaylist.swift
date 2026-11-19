import Foundation
import HumCore

/// One fictional track and the recipe for its cover.
public struct DemoTrack: Sendable, Equatable {
    public var track: Track
    public var cover: DemoCover

    public init(track: Track, cover: DemoCover) {
        self.track = track
        self.cover = cover
    }
}

/// The demo's playlist. Every name is invented for Hum. One song is marked
/// explicit, so the badge has something to show.
public enum DemoPlaylist {
    public static let tracks: [DemoTrack] = [
        make("low-tide-radio", "Low Tide Radio", "Marlow Fields", "Coastline Hours", 214, .tide),
        make("lantern-arithmetic", "Lantern Arithmetic", "The Quiet Hours", "Small Fires", 187, .lanterns),
        make("switchback-hymn", "Switchback Hymn", "Juniper & Vale", "Altitude Notes", 243, .ridges),
        make("glasshouse-weather", "Glasshouse Weather", "Ines Calder", "Conservatory", 199, .glasshouse),
        make("neon-ledger", "Neon Ledger", "Okafor Trio", "After Close", 226, .ledger, explicit: true),
        make("monochrome-letters", "Monochrome Letters", "Hollis Weather", "Ash & Paper", 171, .rings),
    ]

    /// The singles the demo history adds (`DemoHistory.extraTracks(for:)`),
    /// which aren't on the playlist.
    static let singles: [TrackID: DemoCover] = [
        TrackID("demo:northbound"): .floes,
        TrackID("demo:paper-boats"): .folded,
    ]

    /// The cover for a song the demo plays or its history lists: the song's
    /// own, its album's for a song added only for the history, or a single's.
    public static func cover(for id: TrackID, album: String) -> DemoCover? {
        tracks.first { $0.track.id == id }?.cover
            ?? tracks.first { !album.isEmpty && $0.track.album == album }?.cover
            ?? singles[id]
    }

    private static func make(
        _ id: String,
        _ title: String,
        _ artist: String,
        _ album: String,
        _ duration: TimeInterval,
        _ cover: DemoCover,
        explicit: Bool = false
    ) -> DemoTrack {
        DemoTrack(
            track: Track(
                id: TrackID("demo:" + id),
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                isExplicit: explicit
            ),
            cover: cover
        )
    }
}
