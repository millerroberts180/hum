/// Repeat setting. Not every source supports every mode; see `SourceCapabilities`.
public enum RepeatMode: String, Sendable, Codable, CaseIterable {
    case off
    /// Repeat the playlist, album, or queue.
    case all
    /// Repeat the current track.
    case one
}
