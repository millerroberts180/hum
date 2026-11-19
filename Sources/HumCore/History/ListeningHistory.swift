import Foundation
import Observation

/// Listening history for the app: records what plays, keeps Echo's insights
/// current, and carries out the privacy controls.
///
/// Lives on the main actor for the UI; every read and write goes through
/// `HistoryStore`, an actor, so disk work never runs here.
@MainActor
@Observable
public final class ListeningHistory {
    /// Insights for the current song and session.
    public private(set) var echo = EchoSnapshot.empty
    /// Whether `echo` has been read from the store yet. Until then it's empty
    /// because nothing has been read, not because nothing was saved.
    public private(set) var hasLoaded = false
    /// Bumped after every change to stored history, so views can reload.
    public private(set) var revision = 0
    /// The last listens removed, until undone or replaced by another removal.
    public private(set) var lastRemoved: [Listen] = []
    /// Why the history file couldn't be used, if it couldn't. History then lives
    /// in memory for this run.
    public private(set) var storageProblem: String?
    /// The last write or read that failed, in plain words.
    public private(set) var lastError: String?

    public var isCollecting: Bool { settings.history.isCollecting }

    @ObservationIgnored public let store: HistoryStore
    /// Shared with the player, for trail and list thumbnails.
    @ObservationIgnored public let artworkCache: ArtworkCache
    @ObservationIgnored public let calendar: Calendar
    @ObservationIgnored private let nowPlaying: NowPlayingStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let recorder = ListeningRecorder()
    @ObservationIgnored private var observation: NowPlayingObservation?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var writes: Task<Void, Never>?
    /// Finished listens queued for the store but not yet written, so quitting
    /// can write them directly.
    @ObservationIgnored private var unsaved: [Listen] = []
    @ObservationIgnored private var isStarted = false

    public init(
        store: HistoryStore,
        nowPlaying: NowPlayingStore,
        settings: SettingsStore,
        artworkCache: ArtworkCache,
        storageProblem: String? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.store = store
        self.nowPlaying = nowPlaying
        self.settings = settings
        self.artworkCache = artworkCache
        self.storageProblem = storageProblem
        self.calendar = calendar
        self.now = now
        recorder.onFinish = { [weak self] listen in self?.save(listen) }
        recorder.onCheckpoint = { [weak self] pending in self?.checkpoint(pending) }
    }

    // MARK: Lifecycle

    /// Recover a listen interrupted by a crash, then follow playback.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        if let storageProblem {
            HumLog.history.error("History file unusable, keeping history in memory: \(storageProblem, privacy: .public)")
        }
        enqueue { store in
            if try await store.recoverPending() != nil {
                HumLog.history.notice("Recovered a listen interrupted by the last quit")
            }
        }
        observation = nowPlaying.addObserver { [weak self] event in
            self?.handle(event)
        }
        if isCollecting {
            recorder.begin(with: nowPlaying.snapshot, source: nowPlaying.activeSourceID, at: now())
        }
        observeSnapshot()
        refresh()
    }

    /// Finish the listen in progress and wait (briefly) for it to be written.
    /// Called as Hum quits.
    public func stop() {
        guard isStarted else { return }
        isStarted = false
        observation?.cancel()
        observation = nil
        refreshTask?.cancel()
        var flush = unsaved
        if isCollecting, let listen = recorder.finishForStop(at: now()) { flush.append(listen) }
        let store = store
        let done = DispatchSemaphore(value: 0)
        // Straight to the store rather than behind the queued writes: those resume
        // on the main actor, which this wait holds. Inserts skip listens already
        // stored, so a queued write that lands too keeps one copy.
        Task.detached {
            for listen in flush { _ = try? await store.insertIfNew(listen) }
            try? await store.savePending(nil)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    public func systemWillSleep() {
        recorder.systemWillSleep(at: now())
    }

    public func systemDidWake() {
        recorder.systemDidWake(isPlaying: nowPlaying.isPlaying, at: now())
    }

    // MARK: Privacy

    /// Pause or resume collection. Pausing drops the listen in progress; nothing
    /// heard while paused is ever written.
    public func setCollecting(_ collecting: Bool) {
        guard collecting != isCollecting else { return }
        settings.history.isCollecting = collecting
        HumLog.history.notice("Collection \(collecting ? "resumed" : "paused", privacy: .public)")
        if collecting {
            recorder.begin(with: nowPlaying.snapshot, source: nowPlaying.activeSourceID, at: now())
        } else {
            recorder.discard()
        }
        refresh()
    }

    /// Remove listens. They can be put back with `undoRemove()`.
    public func remove(_ listens: [Listen]) {
        let ids = listens.map(\.id)
        enqueue { [weak self] store in
            let removed = try await store.delete(ids: ids)
            self?.lastRemoved = removed
        }
    }

    public func undoRemove() {
        restore(lastRemoved)
    }

    /// Put removed listens back, as an undo does.
    public func restore(_ listens: [Listen]) {
        guard !listens.isEmpty else { return }
        if Set(lastRemoved.map(\.id)) == Set(listens.map(\.id)) {
            lastRemoved = []
        }
        enqueue { store in
            try await store.restore(listens)
        }
    }

    /// Forget the undo for the last removal.
    public func clearUndo() {
        lastRemoved = []
    }

    /// Erase every listen and start tracking over.
    public func eraseAll() {
        lastRemoved = []
        unsaved = []
        let pending = recorder.current != nil
        enqueue { store in
            try await store.eraseAll()
            HumLog.history.notice("Erased all listening history")
        }
        if pending, isCollecting {
            // Start the listen in progress over too, so nothing from before the
            // erase survives.
            recorder.begin(with: nowPlaying.snapshot, source: nowPlaying.activeSourceID, at: now())
        }
    }

    /// Replace everything with `listens` and give their songs covers. For the
    /// demo's synthetic history only; the real history is never replaced.
    public func replaceAll(with listens: [Listen], artwork: @escaping @Sendable (Listen) async -> Data?) {
        lastRemoved = []
        unsaved = []
        let cache = artworkCache
        enqueue { store in
            try await store.eraseAll()
            try await store.insert(contentsOf: listens)
            await Self.cache(Self.coverOrder(listens), in: cache, artwork: artwork)
        }
    }

    /// Give the songs heard most recently the covers the cache is missing, for
    /// history kept from an earlier run. The demo's covers live in memory only,
    /// so without this a relaunch shows its trail and lists blank.
    public func fillArtwork(recent limit: Int = 20, artwork: @escaping @Sendable (Listen) async -> Data?) {
        let cache = artworkCache
        let since = now().addingTimeInterval(-7 * 86_400)
        enqueue { store in
            let recent = try await store.listens(from: since)
            await Self.cache(Self.coverOrder(recent, limit: limit), in: cache, artwork: artwork)
        }
    }

    /// One listen for each cover, most recently heard last, so a cache that
    /// keeps only so many in memory keeps the newest. `limit` keeps only the
    /// newest that many.
    nonisolated static func coverOrder(_ listens: [Listen], limit: Int? = nil) -> [Listen] {
        var seen: Set<String> = []
        var newestFirst: [Listen] = []
        for listen in listens.sorted(by: { $0.startedAt < $1.startedAt }).reversed()
        where seen.insert(listen.artworkKey).inserted {
            if let limit, newestFirst.count >= limit { break }
            newestFirst.append(listen)
        }
        return newestFirst.reversed()
    }

    private nonisolated static func cache(
        _ listens: [Listen],
        in cache: ArtworkCache,
        artwork: @Sendable (Listen) async -> Data?
    ) async {
        for listen in listens {
            guard await cache.image(forKey: listen.artworkKey) == nil,
                  let data = await artwork(listen)
            else { continue }
            await cache.insert(data, forKey: listen.artworkKey)
        }
    }

    /// Write every listen to `url`. Returns how many were written.
    public func export(_ format: HistoryExportFormat, to url: URL) async throws -> Int {
        await writes?.value
        return try await store.export(format, to: url)
    }

    // MARK: Import

    /// Bring in listening history from Spotify's data download: the files or
    /// folders in `urls`. They're read off the main actor; listens already in
    /// history are left out.
    public func importHistory(from urls: [URL]) async throws -> HistoryImport.Summary {
        let batch: HistoryImport.Batch
        do {
            batch = try await HistoryImport.read(urls)
        } catch {
            // The message can name the user's files, so it stays private.
            HumLog.history.error("Import couldn't read the chosen files: \(String(describing: error), privacy: .private)")
            throw error
        }
        let store = store
        let previous = writes
        let write = Task { () async throws -> HistoryImport.Summary in
            await previous?.value
            return try await store.importListens(batch)
        }
        writes = Task { [weak self] in
            _ = try? await write.value
            self?.revision += 1
            self?.refresh()
        }
        do {
            let summary = try await write.value
            HumLog.history.notice(
                "Imported \(summary.added, privacy: .public) listens from \(summary.files, privacy: .public) files; \(summary.duplicates, privacy: .public) duplicates, \(summary.skipped, privacy: .public) skipped"
            )
            return summary
        } catch {
            HumLog.history.error("Import couldn't be saved: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
            throw error
        }
    }

    /// Remove every imported listen. Tracked listens stay.
    public func removeImported() {
        lastRemoved.removeAll { $0.origin == .imported }
        enqueue { store in
            let removed = try await store.removeImported()
            HumLog.history.notice("Removed \(removed, privacy: .public) imported listens")
        }
    }

    // MARK: Echo

    /// Recompute Echo's insights for what's playing now.
    public func refresh() {
        refreshTask?.cancel()
        let store = store
        let track = nowPlaying.track
        let inProgress = isCollecting ? recorder.provisional(at: now()) : nil
        let date = now()
        let calendar = calendar
        let previous = writes
        refreshTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                let snapshot = try await store.echo(track: track, inProgress: inProgress, now: date, calendar: calendar)
                guard !Task.isCancelled, let self else { return }
                if snapshot != self.echo { self.echo = snapshot }
                if !self.hasLoaded { self.hasLoaded = true }
            } catch {
                HumLog.history.error("The History page couldn't refresh: \(String(describing: error), privacy: .public)")
                self?.lastError = String(describing: error)
            }
        }
    }

    /// Wait for queued writes and the latest refresh. For tests.
    public func settle() async {
        await writes?.value
        await refreshTask?.value
    }

    // MARK: Recording

    private func handle(_ event: NowPlayingEvent) {
        guard isCollecting else { return }
        recorder.handle(event, snapshot: nowPlaying.snapshot, at: now())
        if case .trackChanged = event {
            refresh()
        }
    }

    private func observeSnapshot() {
        withObservationTracking {
            _ = nowPlaying.snapshot
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                if self.isCollecting { self.recorder.noteSnapshot(self.nowPlaying.snapshot) }
                self.observeSnapshot()
            }
        }
    }

    private func save(_ listen: Listen) {
        unsaved.append(listen)
        enqueue { [weak self] store in
            try await store.insertIfNew(listen)
            self?.unsaved.removeAll { $0 == listen }
        }
    }

    private func checkpoint(_ pending: PendingListen?) {
        let store = store
        let previous = writes
        writes = Task {
            await previous?.value
            try? await store.savePending(pending)
        }
    }

    /// Run a write after the ones before it, then reload.
    private func enqueue(_ write: @escaping @MainActor (HistoryStore) async throws -> Void) {
        let store = store
        let previous = writes
        writes = Task { [weak self] in
            await previous?.value
            do {
                try await write(store)
            } catch {
                HumLog.history.error("History write failed: \(String(describing: error), privacy: .public)")
                self?.lastError = String(describing: error)
            }
            self?.revision += 1
            self?.refresh()
        }
    }
}
