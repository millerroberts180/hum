import Foundation

/// What Play does for a song in Rediscover.
///
/// A listen remembers the source it was heard on and that source's own ID for
/// the song, so when that source is the active one and can play songs from a
/// list, the song plays. Otherwise there's nothing to hand the source, and
/// there's no button at all, never one that does nothing (DESIGN.md §6.5).
public enum RediscoverPlay {
    /// The song to play for `entry`, or `nil` when it can't play now.
    ///
    /// - Parameters:
    ///   - activeSource: The source the library is following now.
    ///   - canPlayItems: Whether that source can play a song from a list now.
    public static func track(for entry: TopEntry, activeSource: SourceID?, canPlayItems: Bool) -> LibraryTrack? {
        guard canPlayItems, entry.sampleSource == activeSource, !entry.sampleTrackID.rawValue.isEmpty else { return nil }
        return LibraryTrack(id: entry.sampleTrackID, title: entry.title, artist: entry.subtitle)
    }
}
