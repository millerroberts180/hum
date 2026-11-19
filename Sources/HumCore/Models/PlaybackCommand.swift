import Foundation

/// A request to change the player. Sources declare which ones they accept through
/// `SourceCapabilities`.
public enum PlaybackCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case next
    case previous
    /// Seconds from the start of the track.
    case seek(to: TimeInterval)
    /// 0...1.
    case setVolume(Double)
    case setShuffle(Bool)
    case setRepeat(RepeatMode)
    case setFavorite(Bool)
    /// Fast-forward (or rewind) through the track until `endScan`, as when a skip
    /// button is held.
    case beginScan(forward: Bool)
    /// Return to normal playback after `beginScan`.
    case endScan
}
