import HumCore

/// What a widget's `hum://` link does to playback (DESIGN.md §7.3).
nonisolated enum URLActions {
    /// The command for `action`, given what the source can do and its current
    /// shuffle and repeat, or `nil` when the source can't do it. Shuffle
    /// turns the other way; repeat steps off → all → one, skipping a mode the
    /// source doesn't have. Show isn't a command.
    static func command(
        for action: HumURLAction,
        capabilities: SourceCapabilities,
        shuffle: Bool,
        repeatMode: RepeatMode
    ) -> PlaybackCommand? {
        let command: PlaybackCommand? = switch action {
        case .playPause: .togglePlayPause
        case .next: .next
        case .previous: .previous
        case .shuffle: .setShuffle(!shuffle)
        case .repeat: capabilities.nextRepeatMode(after: repeatMode).map(PlaybackCommand.setRepeat)
        case .show: nil
        }
        guard let command, capabilities.supports(command) else { return nil }
        return command
    }
}
