import Foundation

/// Something that happened to playback, for features that react to changes rather
/// than render state (listening history, show-on-track-change).
public enum NowPlayingEvent: Equatable, Sendable {
    /// The track changed. `previous` played for `listened` seconds before the change,
    /// as far as Hum observed. Also sent with the same track as both when it
    /// starts over under Hum's repeat one (`RepeatOneRestart`), so History
    /// counts each time through as a play (DESIGN.md §5.2).
    case trackChanged(previous: Track?, current: Track?, source: SourceID, listened: TimeInterval)
    case statusChanged(PlaybackStatus, source: SourceID)
    case seeked(to: TimeInterval, source: SourceID)
    case sourceChanged(SourceID?)
}

/// Keeps an event observer registered. Call `cancel()` or let it deinitialize.
@MainActor
public final class NowPlayingObservation {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel?()
        onCancel = nil
    }

    isolated deinit {
        onCancel?()
    }
}
