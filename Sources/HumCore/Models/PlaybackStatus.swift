/// Transport state as the user understands it.
public enum PlaybackStatus: String, Sendable, Codable, CaseIterable {
    case playing
    case paused
    case stopped

    public var isPlaying: Bool { self == .playing }
}
