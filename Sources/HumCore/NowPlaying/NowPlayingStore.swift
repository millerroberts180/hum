import Foundation
import Observation

/// The single source of truth for what the player shows.
///
/// Owns every registered `PlaybackSource`, decides which one is active, layers
/// optimistic command state over what the source reports, runs the local position
/// clock, and loads artwork. Views read it from the environment; nothing in the UI
/// talks to a source directly.
@MainActor
@Observable
public final class NowPlayingStore {
    // MARK: Sources

    @ObservationIgnored public let sources: [any PlaybackSource]
    public private(set) var sourceStates: [SourceID: SourceState] = [:]
    public private(set) var activeSourceID: SourceID?

    /// A source the user chose explicitly, or `nil` to follow whatever is playing.
    public var preferredSourceID: SourceID? {
        didSet {
            guard preferredSourceID != oldValue else { return }
            reselect()
        }
    }

    /// The source that was active most recently. Persisted by the app so the player
    /// starts on the same source next launch.
    public private(set) var lastActiveSourceID: SourceID?

    // MARK: Displayed state

    /// What the player shows: the active source's report with in-flight commands
    /// applied. Read the position from `position(at:)`, not from here.
    public private(set) var snapshot: PlaybackSnapshot = .empty
    public private(set) var clock = PositionClock()
    public private(set) var artwork: ArtworkImage?
    /// The source `artwork` came from. It can lag `activeSourceID` for a moment:
    /// after a switch the old cover stays until the new one loads.
    public private(set) var artworkSourceID: SourceID?
    public private(set) var lastError: PlaybackError?
    /// The system Automation prompt is (or may be) on screen.
    public private(set) var isRequestingPermission = false
    /// The source's app is starting because the user pressed play.
    public private(set) var isLaunching = false
    /// Shown as a dismissible banner after the same command fails twice in a row.
    public private(set) var warning: PlaybackWarning?
    /// Which way the most recent track change went.
    public private(set) var trackChangeDirection: TrackChangeDirection = .forward

    // MARK: Private

    @ObservationIgnored private let artworkCache: ArtworkCache
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private var intents = PendingIntents()
    @ObservationIgnored private var failures = FailureStreak()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledExpiry: Date?
    /// The last Previous command, so the next track change can be called backward.
    @ObservationIgnored private var lastPreviousAt: Date?
    @ObservationIgnored private var tally = ListeningTally()
    @ObservationIgnored private var startedPlayingAt: [SourceID: Date] = [:]
    @ObservationIgnored private var observers: [UUID: @MainActor (NowPlayingEvent) -> Void] = [:]
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworkRequestKey: String?
    @ObservationIgnored private var pendingVolume: Double?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
    /// Hum's repeat one, for a source whose app repeats only on or off.
    @ObservationIgnored private var repeatOne = RepeatOneRestart()
    @ObservationIgnored private var scheduledRestart: RepeatOneRestart.Plan?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var rereadTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    /// Minimum spacing between volume commands while the user drags the slider.
    static let volumeSendInterval: Duration = .milliseconds(60)
    /// A track change this soon after Previous counts as going backward.
    static let previousDirectionWindow: TimeInterval = 3

    public init(
        sources: [any PlaybackSource],
        artworkCache: ArtworkCache = ArtworkCache(directory: nil),
        preferredSourceID: SourceID? = nil,
        lastActiveSourceID: SourceID? = nil,
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.sources = sources
        self.artworkCache = artworkCache
        self.preferredSourceID = preferredSourceID
        self.lastActiveSourceID = lastActiveSourceID
        self.now = now
        self.sleep = sleep
        for source in sources {
            sourceStates[source.id] = source.state
        }
    }

    // MARK: Lifecycle

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        for source in sources {
            let id = source.id
            source.onStateChange = { [weak self] state in
                self?.sourceDidChange(id, to: state)
            }
            source.start()
            sourceStates[id] = source.state
        }
        reselect(force: true)
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        for source in sources {
            source.onStateChange = nil
            source.stop()
        }
        artworkTask?.cancel()
        volumeTask?.cancel()
        expiryTask?.cancel()
        expiryTask = nil
        scheduledExpiry = nil
        repeatOne.turnOff()
        cancelRestart()
    }

    /// Ask the active source for fresh state, for example when the player appears.
    public func refresh() {
        activeSource?.refresh()
    }

    // MARK: Reading

    public var activeSource: (any PlaybackSource)? {
        guard let activeSourceID else { return nil }
        return source(for: activeSourceID)
    }

    public func source(for id: SourceID) -> (any PlaybackSource)? {
        sources.first { $0.id == id }
    }

    public var activeState: SourceState? {
        activeSourceID.flatMap { sourceStates[$0] }
    }

    /// The source whose rules the cover on screen is drawn under (DESIGN §3.6.1):
    /// the one `artwork` came from, or the active source while there's no cover.
    /// The source travels with the artwork, so a Spotify cover still showing
    /// after a switch to Music keeps Spotify's treatment until Music's arrives.
    public var displayedArtworkSource: SourceID? {
        artwork == nil ? activeSourceID : artworkSourceID
    }

    /// What the user can do right now. Controls not in this set should be hidden.
    public var capabilities: SourceCapabilities {
        activeState?.effectiveCapabilities ?? []
    }

    public var availability: SourceAvailability {
        activeState?.availability ?? .notInstalled
    }

    public var permission: AutomationPermission {
        activeState?.permission ?? .unknown
    }

    public var track: Track? { snapshot.track }
    public var isPlaying: Bool { snapshot.status.isPlaying }

    public func position(at date: Date) -> TimeInterval {
        clock.position(at: date)
    }

    public func progress(at date: Date) -> Double? {
        clock.progress(at: date)
    }

    // MARK: Commands

    /// Run a command without waiting for it, for buttons and key presses.
    public func send(_ command: PlaybackCommand) {
        if case .setVolume(let value) = command {
            setVolume(value)
            return
        }
        Task { await perform(command) }
    }

    /// Run a command. The display updates immediately and is corrected if the source
    /// disagrees or the command fails.
    public func perform(_ command: PlaybackCommand) async {
        await run(command)
    }

    /// `perform`, saying whether the source carried the command out.
    @discardableResult
    private func run(_ command: PlaybackCommand) async -> Bool {
        guard let source = activeSource, let state = activeState else { return false }

        if state.availability == .notRunning {
            await launchAndPlay(source, command: command, state: state)
            return false
        }

        if state.permission == .notDetermined {
            await requestPermission()
            guard activeSourceID == source.id, activeState?.permission.allowsControl == true else { return false }
        }

        guard capabilities.supports(command) else {
            lastError = .unsupported(command)
            return false
        }

        let date = now()
        if command == .previous { lastPreviousAt = date }
        // What the source is sent: under Hum's repeat one its app's repeat
        // stays on, and the store starts the song over (DESIGN.md §5.2).
        var sent = command
        switch command {
        case .next, .previous:
            repeatOne.lastSkipAt = date
        case .setRepeat(let mode) where capabilities.contains(.repeatOneByRestart):
            sent = .setRepeat(repeatOne.choose(mode, for: source.id))
        default:
            break
        }
        intents.record(sent, current: snapshot, at: date)
        refreshDisplayed(at: date)
        if case .seek(let target) = command {
            clock.rebase(position: target, at: date, isAdvancing: snapshot.status.isPlaying)
            emit(.seeked(to: target, source: source.id))
        }

        do {
            try await source.perform(sent)
            lastError = nil
            return true
        } catch {
            intents.removeAll()
            if command == .setRepeat(.one) { repeatOne.turnOff() }
            let failure = (error as? PlaybackError) ?? .scriptFailed(code: 0, message: error.localizedDescription)
            lastError = failure
            if failure.isTransient {
                noteFailure("command:\(command.kind)", source: source)
            }
            if activeSourceID == source.id {
                sourceStates[source.id] = source.state
                refreshDisplayed(at: now())
            }
            return false
        }
    }

    /// Change the volume, coalescing rapid changes from a dragging slider so the
    /// source sees at most one command per `volumeSendInterval`.
    public func setVolume(_ value: Double) {
        guard capabilities.contains(.volume) else { return }
        let volume = min(1, max(0, value))
        let date = now()
        intents.record(.setVolume(volume), current: snapshot, at: date)
        refreshDisplayed(at: date)
        pendingVolume = volume
        guard volumeTask == nil else { return }
        volumeTask = Task { [weak self] in
            while let self, let next = self.pendingVolume {
                self.pendingVolume = nil
                try? await self.activeSource?.perform(.setVolume(next))
                try? await Task.sleep(for: Self.volumeSendInterval)
            }
            self?.volumeTask = nil
        }
    }

    /// Ask macOS for Automation permission for the active source. Shows the system
    /// prompt if the user hasn't been asked yet.
    public func requestPermission() async {
        guard let source = activeSource, !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        await source.requestAutomationPermission()
        sourceStates[source.id] = source.state
        if source.id == activeSourceID {
            refreshDisplayed(at: now())
        }
    }

    public func clearError() {
        lastError = nil
    }

    public func dismissWarning() {
        warning = nil
        failures.succeed()
    }

    private func noteFailure(_ kind: String, source: any PlaybackSource) {
        if failures.fail(kind) {
            warning = PlaybackWarning(message: "\(source.displayName) isn’t responding.")
        }
    }

    // MARK: Events

    /// Register for playback events. Keep the returned observation alive for as long
    /// as you want events.
    public func addObserver(_ handler: @escaping @MainActor (NowPlayingEvent) -> Void) -> NowPlayingObservation {
        let id = UUID()
        observers[id] = handler
        return NowPlayingObservation { [weak self] in
            self?.observers[id] = nil
        }
    }

    // MARK: State handling

    private func sourceDidChange(_ id: SourceID, to state: SourceState) {
        let wasPlaying = sourceStates[id]?.isPlaying ?? false
        sourceStates[id] = state
        if state.isPlaying, !wasPlaying {
            startedPlayingAt[id] = now()
        }
        reselect()
        if id == activeSourceID {
            answerReread(with: state.snapshot)
            refreshDisplayed(at: now())
        }
    }

    private func reselect(force: Bool = false) {
        let candidates = sources.map { source in
            SourceSelector.Candidate(
                id: source.id,
                state: sourceStates[source.id] ?? source.state,
                startedPlayingAt: startedPlayingAt[source.id]
            )
        }
        let selected = SourceSelector.select(
            from: candidates,
            current: activeSourceID,
            preferred: preferredSourceID,
            lastActive: lastActiveSourceID
        )
        guard force || selected != activeSourceID else { return }
        let changed = selected != activeSourceID
        activeSourceID = selected
        if let selected, sourceStates[selected]?.availability.isRunning == true {
            lastActiveSourceID = selected
        }
        intents.removeAll()
        pendingVolume = nil
        if changed {
            failures.succeed()
            warning = nil
        }
        refreshDisplayed(at: now())
        if changed {
            emit(.sourceChanged(selected))
        }
    }

    private func refreshDisplayed(at date: Date) {
        guard let id = activeSourceID, let state = sourceStates[id] else {
            repeatOne.turnOff()
            apply(.empty, reportedAdvancing: false, sourceID: nil, at: date)
            scheduleRestart(at: date)
            return
        }
        let reported = state.availability.isRunning ? state.snapshot : PlaybackSnapshot.empty
        let resolution = intents.resolve(reported, at: date)
        apply(
            withRepeatOne(resolution.snapshot, source: id, isRunning: state.availability.isRunning),
            reportedAdvancing: reported.status.isPlaying && reported.track != nil,
            sourceID: id,
            at: date
        )
        scheduleRestart(at: date)

        // Transport state the source never confirmed has just reverted. Once is
        // noise; the same thing twice in a row gets a warning.
        let unconfirmed = resolution.expired.subtracting([.volume, .seek])
        if let field = unconfirmed.first, let source = source(for: id) {
            noteFailure("unconfirmed:\(field)", source: source)
        } else if !resolution.confirmed.isEmpty {
            failures.succeed()
            warning = nil
        }
        scheduleIntentExpiry()
    }

    /// Wake up when the next optimistic intent runs out, so an unconfirmed
    /// command reverts on time even if the source never reports again.
    private func scheduleIntentExpiry() {
        let deadline = intents.nextDeadline
        guard deadline != scheduledExpiry else { return }
        expiryTask?.cancel()
        expiryTask = nil
        scheduledExpiry = deadline
        guard let deadline else { return }
        let delay = max(0, deadline.timeIntervalSince(now()))
        let sleep = sleep
        expiryTask = Task { [weak self] in
            await sleep(.seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.expiryTask = nil
            self.scheduledExpiry = nil
            self.refreshDisplayed(at: self.now())
        }
    }

    /// Show `shown`, the report with in-flight intents applied.
    /// `reportedAdvancing` is whether the source was playing when it reported:
    /// its position runs on that way up to `date`, and only from `date` does
    /// the clock take `shown`'s state. So a pause between reports holds where
    /// the song got to, and a play from paused starts where the source paused.
    private func apply(_ shown: PlaybackSnapshot, reportedAdvancing: Bool, sourceID: SourceID?, at date: Date) {
        let previous = snapshot
        let trackChanged = shown.track?.id != previous.track?.id
        let advancing = shown.status.isPlaying && shown.track != nil
        let position = shown.position.map {
            projected($0, from: shown.timestamp, to: date, advancing: reportedAdvancing)
        }

        if trackChanged {
            let wentBack = lastPreviousAt.map { date.timeIntervalSince($0) <= Self.previousDirectionWindow } ?? false
            trackChangeDirection = wentBack ? .backward : .forward
            lastPreviousAt = nil
            if let sourceID, previous.status.isPlaying, repeatOne.ranOut(
                previous: previous.track?.id,
                remaining: clock.remaining(at: date),
                next: shown.track?.id,
                source: sourceID,
                at: date
            ) {
                goBackForRepeatOne()
            }
            repeatOne.songChanged()
            clock = PositionClock(position: position ?? 0, at: date, isAdvancing: advancing, duration: shown.track?.duration)
        } else {
            var next = clock
            next.duration = shown.track?.duration
            if let position {
                next.reconcile(reported: position, at: date, isAdvancing: advancing)
            } else {
                next.setAdvancing(advancing, at: date)
            }
            if next != clock { clock = next }
        }

        if shown != previous {
            snapshot = shown
        }

        if let listened = tally.update(track: shown.track?.id, isPlaying: advancing, at: date),
           let sourceID {
            emit(.trackChanged(previous: previous.track, current: shown.track, source: sourceID, listened: listened))
        } else if trackChanged, let sourceID, previous.track == nil {
            emit(.trackChanged(previous: nil, current: shown.track, source: sourceID, listened: 0))
        }
        if shown.status != previous.status, let sourceID {
            emit(.statusChanged(shown.status, source: sourceID))
        }

        updateArtwork(for: shown.track, sourceID: sourceID)
    }

    private func projected(_ position: TimeInterval, from timestamp: Date, to date: Date, advancing: Bool) -> TimeInterval {
        guard advancing else { return position }
        return position + max(0, date.timeIntervalSince(timestamp))
    }

    // MARK: Repeat one

    /// `shown` with Hum's repeat one in place of the app's repeat all, while
    /// One is on (DESIGN.md §5.2). One ends when the app's repeat goes off
    /// (turned off in the app, or a command it never confirmed), when the app
    /// quits, and when another source takes over.
    private func withRepeatOne(_ shown: PlaybackSnapshot, source: SourceID, isRunning: Bool) -> PlaybackSnapshot {
        guard repeatOne.sourceID != nil else { return shown }
        guard repeatOne.isOn(for: source), isRunning, shown.repeatMode != .off else {
            repeatOne.turnOff()
            return shown
        }
        var shown = shown
        if shown.repeatMode == .all { shown.repeatMode = .one }
        return shown
    }

    /// Plans the restart from the clock, on every state update: `lead` before
    /// the end, while the song plays. A pause, a new song, a seek past that
    /// moment, or One ending cancels it.
    private func scheduleRestart(at date: Date) {
        let plan = repeatOne.plan(track: snapshot.track?.id, isPlaying: snapshot.status.isPlaying, clock: clock, at: date)
        if let plan, plan.isSame(as: scheduledRestart) { return }
        if plan == nil, scheduledRestart == nil, restartTask == nil { return }
        restartTask?.cancel()
        restartTask = nil
        scheduledRestart = plan
        guard let plan else { return }
        let delay = max(0, plan.at.timeIntervalSince(date))
        let sleep = sleep
        restartTask = Task { [weak self] in
            await sleep(.seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.restartTask = nil
            self.scheduledRestart = nil
            self.beginReread(plan.track)
        }
    }

    private func cancelRestart() {
        restartTask?.cancel()
        restartTask = nil
        scheduledRestart = nil
        rereadTask?.cancel()
        rereadTask = nil
    }

    /// `lead` before the end: ask the source where it really is. Its answer
    /// (`answerReread`) starts the song over; with no answer within
    /// `rereadTimeout`, the store's clock decides.
    private func beginReread(_ track: TrackID) {
        guard let source = activeSource, repeatOne.isOn(for: source.id), repeatOne.reread == nil,
              snapshot.track?.id == track, snapshot.status.isPlaying else { return }
        repeatOne.reread = RepeatOneRestart.Reread(track: track, requestedAt: now())
        rereadTask?.cancel()
        let sleep = sleep
        rereadTask = Task { [weak self] in
            await sleep(.seconds(RepeatOneRestart.rereadTimeout))
            guard !Task.isCancelled, let self else { return }
            self.rereadTask = nil
            self.rereadTimedOut(track)
        }
        // A source may answer at once, so the timeout is set first.
        source.refresh()
    }

    /// A report that answers the re-read: if the song is still playing and
    /// near its end, it starts over. Otherwise the report's own position plans
    /// the restart again.
    private func answerReread(with report: PlaybackSnapshot) {
        guard let reread = repeatOne.reread, report.timestamp >= reread.requestedAt else { return }
        repeatOne.reread = nil
        rereadTask?.cancel()
        rereadTask = nil
        guard RepeatOneRestart.shouldRestart(reread.track, after: report, at: now()) else { return }
        Task { [weak self] in await self?.restart(reread.track) }
    }

    private func rereadTimedOut(_ track: TrackID) {
        guard repeatOne.reread?.track == track else { return }
        repeatOne.reread = nil
        guard snapshot.track?.id == track, snapshot.status.isPlaying,
              let remaining = clock.remaining(at: now()), remaining <= RepeatOneRestart.endWindow else { return }
        Task { [weak self] in await self?.restart(track) }
    }

    /// Starts `track` over from 0, and tells History it's a new play.
    private func restart(_ track: TrackID) async {
        guard let sourceID = activeSourceID, repeatOne.isOn(for: sourceID),
              snapshot.track?.id == track, snapshot.status.isPlaying else { return }
        // The seek sets the clock back to 0, so the store notes the song's old
        // end first: the app can still play on to the next song (§13.34).
        let date = now()
        repeatOne.willRestart(track, remaining: clock.remaining(at: date), at: date)
        guard await run(.seek(to: 0)), activeSourceID == sourceID,
              let current = snapshot.track, current.id == track else { return }
        HumLog.sources.debug("Repeat one: started the song over")
        emit(.trackChanged(previous: current, current: current, source: sourceID, listened: tally.restart(at: now())))
    }

    /// The song ran out before it could start over: go back to it with
    /// Previous Track, once. The Previous counts as Hum's skip, so the change
    /// it makes never sends another.
    private func goBackForRepeatOne() {
        repeatOne.lastSkipAt = now()
        HumLog.sources.info("Repeat one: the song ended, going back to it")
        Task { [weak self] in await self?.run(.previous) }
    }

    // MARK: Artwork

    private func updateArtwork(for track: Track?, sourceID: SourceID?) {
        guard let track, let sourceID, let source = source(for: sourceID) else {
            artworkTask?.cancel()
            artworkRequestKey = nil
            if artwork != nil { artwork = nil }
            if artworkSourceID != nil { artworkSourceID = nil }
            return
        }
        let key = track.artworkKey(source: sourceID)
        guard artwork?.key != key, artworkRequestKey != key else { return }
        artworkTask?.cancel()
        artworkRequestKey = key
        let cache = artworkCache
        artworkTask = Task { [weak self] in
            var image = await cache.image(forKey: key)
            if image == nil, let data = await source.artwork(for: track) {
                image = await cache.insert(data, forKey: key)
            }
            guard !Task.isCancelled, let self, self.artworkRequestKey == key else { return }
            self.artwork = image
            self.artworkSourceID = image == nil ? nil : sourceID
            if image == nil {
                // Try again on a later state change (for example once permission is
                // granted), but not on every report in between.
                self.artworkRequestKey = self.sourceStates[sourceID]?.permission.allowsControl == true ? key : nil
            }
        }
    }

    // MARK: Launching

    private func launchAndPlay(_ source: any PlaybackSource, command: PlaybackCommand, state: SourceState) async {
        switch command {
        case .play, .togglePlayPause:
            break
        default:
            lastError = .notRunning
            return
        }
        guard state.capabilities.contains(.launch), !isLaunching else { return }
        isLaunching = true
        defer { isLaunching = false }
        do {
            try await source.perform(.play)
            lastError = nil
        } catch {
            lastError = (error as? PlaybackError) ?? .launchFailed
        }
        sourceStates[source.id] = source.state
        reselect()
        refreshDisplayed(at: now())
    }

    private func emit(_ event: NowPlayingEvent) {
        for handler in observers.values {
            handler(event)
        }
    }
}
