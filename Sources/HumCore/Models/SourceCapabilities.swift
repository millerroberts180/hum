/// What a source can do. The UI hides any control whose capability is missing,
/// rather than showing a control that silently fails.
public struct SourceCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let playPause = SourceCapabilities(rawValue: 1 << 0)
    public static let skipNext = SourceCapabilities(rawValue: 1 << 1)
    public static let skipPrevious = SourceCapabilities(rawValue: 1 << 2)
    public static let seek = SourceCapabilities(rawValue: 1 << 3)
    public static let volume = SourceCapabilities(rawValue: 1 << 4)
    public static let shuffle = SourceCapabilities(rawValue: 1 << 5)
    /// Repeat the playlist, album, or queue.
    public static let repeatAll = SourceCapabilities(rawValue: 1 << 6)
    /// Repeat the current track.
    public static let repeatOne = SourceCapabilities(rawValue: 1 << 7)
    /// Repeat one is Hum's: the app's repeat is only on or off, so the store
    /// keeps it on and starts the song over as it ends (DESIGN.md §5.2). Comes
    /// with `.repeatAll` and `.repeatOne`; the source itself is only ever sent
    /// repeat off or all.
    public static let repeatOneByRestart = SourceCapabilities(rawValue: 1 << 19)
    public static let favorite = SourceCapabilities(rawValue: 1 << 8)
    public static let artwork = SourceCapabilities(rawValue: 1 << 9)
    /// The source can start its app when the user presses play.
    public static let launch = SourceCapabilities(rawValue: 1 << 10)
    /// Holding a skip button fast-forwards or rewinds.
    public static let scan = SourceCapabilities(rawValue: 1 << 11)
    /// Play Now, Play Next, Add to Queue, and Remove from Queue on a track.
    public static let queue = SourceCapabilities(rawValue: 1 << 12)
    /// Add to Playlist.
    public static let playlists = SourceCapabilities(rawValue: 1 << 13)
    /// Start Station.
    public static let radio = SourceCapabilities(rawValue: 1 << 15)
    /// Copy Link: the source can give a shareable web link for a track.
    public static let shareLink = SourceCapabilities(rawValue: 1 << 16)
    /// Show in Spotify / Show in Music: the source has an app to bring forward.
    public static let reveal = SourceCapabilities(rawValue: 1 << 17)

    // MARK: Songs and devices

    /// Play Now on a song, album, or playlist from a list, without the rest of the
    /// queue commands. `.queue` implies it.
    public static let playItems = SourceCapabilities(rawValue: 1 << 18)
    /// List the speakers and computers the source can play on.
    public static let devices = SourceCapabilities(rawValue: 1 << 24)
    /// Move playback to another device.
    public static let deviceSwitching = SourceCapabilities(rawValue: 1 << 25)
    /// Save or favorite any song in a list, not just the one playing.
    public static let saveItems = SourceCapabilities(rawValue: 1 << 26)

    public static let transport: SourceCapabilities = [.playPause, .skipNext, .skipPrevious]

    /// Whether Play Now works on items in lists.
    public var canPlayItems: Bool {
        !intersection([.playItems, .queue]).isEmpty
    }

    /// Whether the source accepts `command` at all.
    public func supports(_ command: PlaybackCommand) -> Bool {
        switch command {
        case .play, .pause, .togglePlayPause:
            contains(.playPause)
        case .next:
            contains(.skipNext)
        case .previous:
            contains(.skipPrevious)
        case .seek:
            contains(.seek)
        case .setVolume:
            contains(.volume)
        case .setShuffle:
            contains(.shuffle)
        case .setRepeat(let mode):
            switch mode {
            case .off: supportsRepeat
            case .all: contains(.repeatAll)
            case .one: contains(.repeatOne)
            }
        case .setFavorite:
            contains(.favorite)
        case .beginScan, .endScan:
            contains(.scan)
        }
    }

    public var supportsRepeat: Bool {
        !intersection([.repeatAll, .repeatOne]).isEmpty
    }

    /// The repeat modes a repeat button cycles through, in order.
    public var repeatCycle: [RepeatMode] {
        var modes: [RepeatMode] = [.off]
        if contains(.repeatAll) { modes.append(.all) }
        if contains(.repeatOne) { modes.append(.one) }
        return modes.count > 1 ? modes : []
    }

    /// The mode after `mode` in `repeatCycle`, wrapping around.
    public func nextRepeatMode(after mode: RepeatMode) -> RepeatMode? {
        let cycle = repeatCycle
        guard !cycle.isEmpty else { return nil }
        guard let index = cycle.firstIndex(of: mode) else { return cycle[0] }
        return cycle[(index + 1) % cycle.count]
    }
}
