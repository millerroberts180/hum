/// Why a command or refresh didn't work.
public enum PlaybackError: Error, Equatable, Sendable {
    case notInstalled
    case notRunning
    /// macOS hasn't asked the user for Automation permission yet.
    case permissionNotDetermined
    /// The user turned off Automation for this app.
    case permissionDenied
    case unsupported(PlaybackCommand)
    /// The app didn't answer in time.
    case timedOut
    case launchFailed
    /// An Apple Event failed for another reason.
    case scriptFailed(code: Int, message: String)
}

extension PlaybackError {
    /// Failures that may go away on their own (a slow or busy app), as opposed to
    /// ones with their own explanation (permission, not installed).
    public var isTransient: Bool {
        switch self {
        case .timedOut, .scriptFailed: true
        default: false
        }
    }
}

extension PlaybackCommand {
    /// The command without its argument, for telling repeated failures apart.
    public var kind: String {
        switch self {
        case .play, .pause, .togglePlayPause: "playPause"
        case .next: "next"
        case .previous: "previous"
        case .seek: "seek"
        case .setVolume: "volume"
        case .setShuffle: "shuffle"
        case .setRepeat: "repeat"
        case .setFavorite: "favorite"
        case .beginScan, .endScan: "scan"
        }
    }
}
