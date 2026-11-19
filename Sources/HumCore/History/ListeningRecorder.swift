import Foundation

/// Follows playback events and turns them into listens.
///
/// Keeps its own count of time heard, so paused time and sleep never count even
/// if the store's own tally runs on through a sleep. Pure state plus callbacks;
/// `ListeningHistory` owns it and does the storage.
@MainActor
final class ListeningRecorder {
    /// The listen being heard right now.
    struct Current: Equatable {
        var track: Track
        var source: SourceID
        var context: PlaybackContext?
        var startedAt: Date
        var accumulated: TimeInterval = 0
        var runningSince: Date?
        var lastPlayedAt: Date

        func listened(at date: Date) -> TimeInterval {
            accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
        }
    }

    private(set) var current: Current?
    /// Called with each finished listen worth keeping.
    var onFinish: (Listen) -> Void = { _ in }
    /// Called with the listen in progress whenever it should be checkpointed, and
    /// with `nil` when there's nothing to keep.
    var onCheckpoint: (PendingListen?) -> Void = { _ in }

    private var isAsleep = false

    /// Begin following `snapshot`'s track, if one is there.
    func begin(with snapshot: PlaybackSnapshot, source: SourceID?, at date: Date) {
        current = nil
        guard let track = snapshot.track, let source else { return }
        let playing = snapshot.status.isPlaying && !isAsleep
        current = Current(
            track: track,
            source: source,
            context: snapshot.context,
            startedAt: date,
            runningSince: playing ? date : nil,
            lastPlayedAt: date
        )
    }

    /// React to a store event. `snapshot` is the store's state after the event.
    func handle(_ event: NowPlayingEvent, snapshot: PlaybackSnapshot, at date: Date) {
        switch event {
        case .trackChanged(_, let next, let source, let listened):
            finish(exit: next == nil ? .stopped : .changedTrack, storeListened: listened, at: date)
            if next != nil {
                begin(with: snapshot, source: source, at: date)
            }
        case .statusChanged(let status, _):
            setPlaying(status.isPlaying, at: date)
        case .seeked, .sourceChanged:
            break
        }
    }

    /// Note the latest snapshot: picks up a context or duration that arrives after
    /// the track itself.
    func noteSnapshot(_ snapshot: PlaybackSnapshot) {
        guard var listen = current, snapshot.track?.id == listen.track.id else { return }
        if let context = snapshot.context { listen.context = context }
        if listen.track.duration == nil, let duration = snapshot.track?.duration { listen.track.duration = duration }
        if listen != current { current = listen }
    }

    func setPlaying(_ playing: Bool, at date: Date) {
        guard var listen = current else { return }
        if playing, !isAsleep {
            guard listen.runningSince == nil else { return }
            // Paused before it ever played: start counting from now.
            if listen.accumulated == 0 { listen.startedAt = date }
            listen.runningSince = date
            listen.lastPlayedAt = date
            current = listen
        } else if let since = listen.runningSince {
            listen.accumulated += max(0, date.timeIntervalSince(since))
            listen.runningSince = nil
            listen.lastPlayedAt = date
            current = listen
            onCheckpoint(pending(at: date))
        }
    }

    func systemWillSleep(at date: Date) {
        setPlaying(false, at: date)
        isAsleep = true
    }

    func systemDidWake(isPlaying: Bool, at date: Date) {
        isAsleep = false
        if isPlaying { setPlaying(true, at: date) }
    }

    /// Finish the listen in progress (Hum is quitting or collection stopped).
    /// Returns it rather than calling `onFinish`, so the caller can store it
    /// before the process ends.
    func finishForStop(at date: Date) -> Listen? {
        defer { current = nil }
        return makeListen(exit: .stopped, storeListened: nil, at: date)
    }

    /// Drop the listen in progress without keeping it.
    func discard() {
        current = nil
        onCheckpoint(nil)
    }

    /// The listen in progress as it stands, for the session trail.
    func provisional(at date: Date) -> Listen? {
        guard let listen = current else { return nil }
        let heard = listen.listened(at: date)
        return Listen(
            trackID: listen.track.id,
            title: listen.track.title,
            artist: listen.track.artist,
            album: listen.track.album,
            source: listen.source,
            context: listen.context,
            startedAt: listen.startedAt,
            endedAt: date,
            listened: heard,
            duration: listen.track.duration,
            ending: .partial,
            counts: PlayRules.counts(listened: heard, duration: listen.track.duration)
        )
    }

    func pending(at date: Date) -> PendingListen? {
        guard let listen = current else { return nil }
        return PendingListen(
            track: listen.track,
            source: listen.source,
            context: listen.context,
            startedAt: listen.startedAt,
            lastPlayedAt: listen.runningSince == nil ? listen.lastPlayedAt : date,
            listened: listen.listened(at: date)
        )
    }

    private func finish(exit: PlayRules.Exit, storeListened: TimeInterval?, at date: Date) {
        let listen = makeListen(exit: exit, storeListened: storeListened, at: date)
        current = nil
        onCheckpoint(nil)
        if let listen { onFinish(listen) }
    }

    private func makeListen(exit: PlayRules.Exit, storeListened: TimeInterval?, at date: Date) -> Listen? {
        guard let listen = current else { return nil }
        let wasPlaying = listen.runningSince != nil
        var pending = pending(at: date)
        // Trust the smaller count: the store's can include a sleep this one skipped.
        if let storeListened, var heard = pending?.listened {
            heard = min(heard, max(0, storeListened))
            pending?.listened = heard
        }
        return pending?.finished(exit: exit, wasPlaying: wasPlaying)
    }
}
