import HumCore
import SwiftUI

/// The right-click menu for a row in Top or Rediscover (DESIGN.md §4.4).
///
/// A song heard on a source the library is serving gets the shared track menu:
/// Play Now, Favorite, Copy Link and Show in App, each where the source can.
/// Anything else has no menu.
struct HistoryEntryMenu: View {
    var entry: TopEntry
    var dimension: TopDimension = .songs
    var library: LibraryStore?

    var body: some View {
        if let library, dimension == .songs, let track = sampleTrack(library),
           case let menu = TrackMenu.song(track, library: library), !menu.isEmpty {
            TrackMenuItems(menu: menu) { TrackMenuPerformer.perform($0, track: track, library: library) }
        }
    }

    /// The listen this row borrows its artwork from, as a song the library can
    /// act on. `nil` when it was heard somewhere the library isn't serving.
    private func sampleTrack(_ library: LibraryStore) -> LibraryTrack? {
        guard library.isServing(entry.sampleSource), !entry.sampleTrackID.rawValue.isEmpty else { return nil }
        return LibraryTrack(id: entry.sampleTrackID, title: entry.title, artist: entry.subtitle)
    }
}

/// The right-click menu for an album on the session trail (DESIGN.md §4.4):
/// Show in App, for an album heard on a source the library is serving that
/// can show its first song.
struct TrailStopMenu: View {
    var stop: TrailStop
    var library: LibraryStore?

    var body: some View {
        if let library, let track = Self.track(for: stop, library: library),
           case let row = TrackMenu.song(track, library: library), row.actions.contains(.reveal) {
            Button(row.title(for: .reveal)) { TrackMenuPerformer.perform(.reveal, track: track, library: library) }
        }
    }

    /// The first song heard from the album, as one the library can act on.
    /// `nil` when it was heard somewhere the library isn't serving.
    static func track(for stop: TrailStop, library: LibraryStore) -> LibraryTrack? {
        guard library.isServing(stop.source), !stop.trackID.rawValue.isEmpty else { return nil }
        return LibraryTrack(id: stop.trackID, title: stop.title, artist: stop.artist, album: stop.album)
    }
}

/// The right-click menu for a listen in History or a day on the Calendar
/// (DESIGN.md §4.4). A song heard on a source the library is serving gets the
/// shared track menu; anything else has none.
struct ListenMenu: View {
    var listen: Listen
    var library: LibraryStore?

    var body: some View {
        if let library, let track = Self.track(for: listen, library: library),
           case let menu = TrackMenu.song(track, library: library), !menu.isEmpty {
            TrackMenuItems(menu: menu) { TrackMenuPerformer.perform($0, track: track, library: library) }
        }
    }

    /// The song heard, as one the library can act on. `nil` when it was heard
    /// somewhere the library isn't serving.
    static func track(for listen: Listen, library: LibraryStore) -> LibraryTrack? {
        guard library.isServing(listen.source), !listen.trackID.rawValue.isEmpty else { return nil }
        return LibraryTrack(id: listen.trackID, title: listen.title, artist: listen.artist, album: listen.album, duration: listen.duration)
    }
}
