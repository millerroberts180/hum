import AppKit
import Foundation
import HumCore

/// A `PlaybackSource` for any app described by a `ScriptableMusicApp`.
///
/// State arrives three ways, cheapest first:
/// 1. **Distributed notifications** the app posts on every track or play-state change.
///    These need no permission, so track names appear even before Automation is
///    granted.
/// 2. **A state query** (one Apple Event round trip) after a notification that left
///    gaps, after a command, or when the player appears. Only with permission.
/// 3. **A poll**, as `PollPolicy` decides: every second while the app is in
///    front, where shuffle and repeat change unannounced, and otherwise rarely,
///    only while playing. Leaving the app reads it once more.
///
/// What Hum sets is held against the app's next replies for a moment
/// (`SetterHold`), since Spotify takes a new value a little after it answers.
///
/// Nothing here runs while the app is quit, and nothing ever launches the app
/// except `perform(.play)` or `perform(.togglePlayPause)`.
@MainActor
public final class ScriptedAppSource<App: ScriptableMusicApp>: PlaybackSource {
    public let id: SourceID = App.sourceID
    public var displayName: String { App.displayName }
    public var appBundleIdentifier: String? { App.bundleIdentifier }

    public private(set) var state: SourceState {
        didSet {
            if state != oldValue { onStateChange?(state) }
        }
    }

    public var onStateChange: (@MainActor (SourceState) -> Void)?
    public private(set) var pollPolicy = PollPolicy()

    private let runner: AppleScriptRunner
    private let workspace: NSWorkspace
    private let urlSession: URLSession
    private var appURL: URL?
    private var notificationObserver: DistributedNotificationObserver?
    private var workspaceObservers: [any NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var queryAgain = false
    private var pendingQuery: Task<Void, Never>?
    private var isStarted = false
    private var isAppFrontmost = false
    private var setterHold = SetterHold()

    public init(
        runner: AppleScriptRunner = .shared,
        workspace: NSWorkspace = .shared,
        urlSession: URLSession = .shared
    ) {
        self.runner = runner
        self.workspace = workspace
        self.urlSession = urlSession
        state = SourceState(availability: .notInstalled, permission: .unknown, capabilities: App.capabilities)
    }

    // MARK: Lifecycle

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        appURL = workspace.urlForApplication(withBundleIdentifier: App.bundleIdentifier)
        notificationObserver = DistributedNotificationObserver(
            name: App.playbackNotification,
            parse: { App.parseNotification($0, at: Date()) },
            deliver: { [weak self] snapshot in self?.handleNotification(snapshot) }
        )

        let center = workspace.notificationCenter
        let bundleIdentifier = App.bundleIdentifier
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard Self.bundleIdentifier(in: note) == bundleIdentifier else { return }
                MainActor.assumeIsolated { self?.appDidLaunch() }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard Self.bundleIdentifier(in: note) == bundleIdentifier else { return }
                MainActor.assumeIsolated { self?.appDidTerminate() }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard Self.bundleIdentifier(in: note) == bundleIdentifier else { return }
                MainActor.assumeIsolated { self?.appDidChangeFront(true) }
            },
            center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard Self.bundleIdentifier(in: note) == bundleIdentifier else { return }
                MainActor.assumeIsolated { self?.appDidChangeFront(false) }
            },
        ]
        isAppFrontmost = workspace.frontmostApplication?.bundleIdentifier == bundleIdentifier

        if appURL == nil {
            state.availability = .notInstalled
        } else if isAppRunning {
            appDidLaunch()
        } else {
            state.availability = .notRunning
        }
        HumLog.sources.info("\(App.displayName, privacy: .public) source started: \(String(describing: self.state.availability), privacy: .public)")
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        notificationObserver?.invalidate()
        notificationObserver = nil
        for observer in workspaceObservers {
            workspace.notificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
        pollTask?.cancel()
        queryTask?.cancel()
        pendingQuery?.cancel()
    }

    public func refresh() {
        query(fromPoll: false)
    }

    // MARK: Commands

    public func perform(_ command: PlaybackCommand) async throws {
        guard state.availability.isInstalled else { throw PlaybackError.notInstalled }

        guard state.availability.isRunning else {
            switch command {
            case .play, .togglePlayPause:
                try await launchAndPlay()
                return
            default:
                throw PlaybackError.notRunning
            }
        }

        if state.permission != .granted {
            await requestAutomationPermission()
            switch state.permission {
            case .granted: break
            case .denied: throw PlaybackError.permissionDenied
            default: throw PlaybackError.permissionNotDetermined
            }
        }

        guard App.capabilities.supports(command), let script = App.commandScript(for: command) else {
            throw PlaybackError.unsupported(command)
        }

        let result: ScriptValue
        do throws(PlaybackError) {
            result = try await runner.run(script)
        } catch {
            note(error)
            throw error
        }
        if ScriptTemplate.isNotRunningMarker(result) {
            appDidTerminate()
            throw PlaybackError.notRunning
        }

        setterHold.record(command, track: state.snapshot.track?.id, at: Date())
        applyConfirmed(command)
        switch command {
        case .play, .pause, .togglePlayPause, .next, .previous:
            // The app usually posts a notification; query anyway in case it doesn't.
            scheduleQuery(after: .milliseconds(350))
        case .beginScan, .endScan:
            scheduleQuery(after: .milliseconds(350))
        case .seek, .setVolume, .setShuffle, .setRepeat, .setFavorite:
            break
        }
    }

    public func requestAutomationPermission() async {
        guard state.availability.isRunning, state.permission != .granted else { return }
        let permission = await AutomationPermissionCheck.determine(bundleIdentifier: App.bundleIdentifier, ask: true)
        guard isStarted else { return }
        state.permission = permission
        if permission == .granted {
            query(fromPoll: false)
        }
    }

    public func shareLink(for track: Track) -> URL? {
        App.shareLink(for: track)
    }

    public func revealURL(for track: Track) -> URL? {
        App.revealURL(for: track)
    }

    // MARK: Playing one song

    public var canPlaySongs: Bool { App.canPlaySongs }

    public func canPlaySong(_ id: TrackID) -> Bool {
        App.playScript(forTrack: id) != nil
    }

    /// Starts one song in the app, for Play Now on Echo's and the History
    /// window's songs. The app must be open: unlike play on Now, this never
    /// launches it.
    public func playSong(_ id: TrackID) async throws {
        guard state.availability.isInstalled else { throw PlaybackError.notInstalled }
        guard state.availability.isRunning else { throw PlaybackError.notRunning }
        guard let script = App.playScript(forTrack: id) else { throw PlaybackError.unsupported(.play) }

        if state.permission != .granted {
            await requestAutomationPermission()
            switch state.permission {
            case .granted: break
            case .denied: throw PlaybackError.permissionDenied
            default: throw PlaybackError.permissionNotDetermined
            }
        }

        let result: ScriptValue
        do throws(PlaybackError) {
            result = try await runner.run(script)
        } catch {
            note(error)
            throw error
        }
        if ScriptTemplate.isNotRunningMarker(result) {
            appDidTerminate()
            throw PlaybackError.notRunning
        }
        // The app posts a notification for the new song; query anyway in case
        // it doesn't.
        scheduleQuery(after: .milliseconds(350))
    }

    // MARK: Permission

    public func refreshAutomationPermission() async {
        guard isStarted, state.availability.isRunning else { return }
        let permission = await AutomationPermissionCheck.determine(bundleIdentifier: App.bundleIdentifier, ask: false)
        // An app that doesn't answer tells nothing; keep what we know.
        guard isStarted, state.availability.isRunning, permission != .unknown, permission != state.permission else { return }
        HumLog.sources.info("\(App.displayName, privacy: .public) Automation now: \(String(describing: permission), privacy: .public)")
        state.permission = permission
        if permission == .granted { query(fromPoll: false) }
    }

    public func artwork(for track: Track) async -> Data? {
        guard state.availability.isRunning, state.permission == .granted,
              state.snapshot.track?.id == track.id else { return nil }
        switch App.artwork {
        case .rawData(let script):
            return (try? await runner.run(script, cache: true))?.data
        case .remoteURL(let script):
            var url = track.artworkURL ?? state.snapshot.track?.artworkURL
            if url == nil, let value = try? await runner.run(script, cache: true), let string = value.string {
                url = URL(string: string)
            }
            guard let url, url.scheme == "https" else { return nil }
            guard let (data, response) = try? await urlSession.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { return nil }
            return data
        }
    }

    // MARK: App lifecycle

    private var isAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: App.bundleIdentifier).isEmpty
    }

    private nonisolated static func bundleIdentifier(in notification: Notification) -> String? {
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    private func appDidLaunch() {
        guard isStarted else { return }
        if appURL == nil {
            appURL = workspace.urlForApplication(withBundleIdentifier: App.bundleIdentifier)
        }
        HumLog.sources.info("\(App.displayName, privacy: .public) is running")
        state.availability = .running
        Task { await checkPermissionQuietly() }
    }

    /// The app came to the front or left it. In front, shuffle, repeat and
    /// volume can change in it without a notification, so the poll quickens;
    /// leaving reads it once more, for the last change made there.
    private func appDidChangeFront(_ isFrontmost: Bool) {
        guard isStarted, isFrontmost != isAppFrontmost else { return }
        isAppFrontmost = isFrontmost
        if isFrontmost {
            reschedulePoll()
        } else {
            query(fromPoll: false)
        }
    }

    private func appDidTerminate() {
        guard isStarted else { return }
        HumLog.sources.info("\(App.displayName, privacy: .public) quit")
        pollTask?.cancel()
        queryTask?.cancel()
        pendingQuery?.cancel()
        isAppFrontmost = false
        setterHold = SetterHold()
        // The permission decision outlives the app, so keep what we learned.
        state = SourceState(
            availability: appURL == nil ? .notInstalled : .notRunning,
            permission: state.permission == .denied || state.permission == .granted ? state.permission : .unknown,
            capabilities: App.capabilities
        )
    }

    /// Learns the permission without prompting. A freshly launched app may not
    /// answer at first, so this retries briefly.
    private func checkPermissionQuietly() async {
        for attempt in 0..<4 {
            let permission = await AutomationPermissionCheck.determine(bundleIdentifier: App.bundleIdentifier, ask: false)
            guard isStarted, state.availability.isRunning else { return }
            if permission != .unknown || attempt == 3 {
                HumLog.sources.info("\(App.displayName, privacy: .public) Automation: \(String(describing: permission), privacy: .public)")
                state.permission = permission
                if permission == .granted { query(fromPoll: false) }
                return
            }
            try? await Task.sleep(for: .milliseconds(750))
        }
    }

    private func launchAndPlay() async throws {
        guard let appURL else { throw PlaybackError.notInstalled }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let launched: Bool = await withCheckedContinuation { continuation in
            workspace.openApplication(at: appURL, configuration: configuration) { application, error in
                continuation.resume(returning: application != nil && error == nil)
            }
        }
        guard launched else {
            HumLog.sources.error("\(App.displayName, privacy: .public) didn't launch")
            throw PlaybackError.launchFailed
        }
        state.availability = .running

        // Wait for the app to start answering Apple Events.
        var permission = AutomationPermission.unknown
        for _ in 0..<16 {
            permission = await AutomationPermissionCheck.determine(bundleIdentifier: App.bundleIdentifier, ask: false)
            if permission != .unknown { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        state.permission = permission
        if permission == .notDetermined {
            // The user pressed play, so this is the moment to ask.
            await requestAutomationPermission()
        }
        switch state.permission {
        case .granted: break
        case .denied: throw PlaybackError.permissionDenied
        default: throw PlaybackError.permissionNotDetermined
        }

        guard let play = App.commandScript(for: .play) else { return }
        for attempt in 0..<6 {
            do {
                if try await !ScriptTemplate.isNotRunningMarker(runner.run(play)) { break }
            } catch {
                if attempt == 5 { throw error }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        query(fromPoll: false)
    }

    // MARK: State

    private func handleNotification(_ snapshot: PlaybackSnapshot) {
        guard isStarted else { return }
        pollPolicy.notificationReceived()
        if !state.availability.isRunning {
            state.availability = .running
            Task { await checkPermissionQuietly() }
        }

        let previous = state.snapshot
        var merged = snapshot.filling(from: previous)
        if merged.position == nil, merged.track?.id == previous.track?.id, let known = previous.position {
            // Carry the interpolated position across a notification that omits it.
            let elapsed = previous.status.isPlaying ? max(0, snapshot.timestamp.timeIntervalSince(previous.timestamp)) : 0
            merged.position = known + elapsed
        }
        state.snapshot = merged

        if state.permission == .granted, snapshot.track?.id != previous.track?.id || snapshot.position == nil {
            scheduleQuery(after: .milliseconds(120))
        } else {
            reschedulePoll()
        }
    }

    private func scheduleQuery(after delay: Duration) {
        pendingQuery?.cancel()
        pendingQuery = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.query(fromPoll: false)
        }
    }

    private func query(fromPoll: Bool) {
        guard isStarted, state.availability.isRunning, state.permission == .granted else { return }
        guard queryTask == nil else {
            queryAgain = true
            return
        }
        queryTask = Task { [weak self, runner] in
            let start = Date()
            let outcome: Result<ScriptValue, PlaybackError>
            do throws(PlaybackError) {
                outcome = .success(try await runner.run(App.stateScript, cache: true))
            } catch {
                outcome = .failure(error)
            }
            let sampledAt = start.addingTimeInterval(Date().timeIntervalSince(start) / 2)
            guard let self else { return }
            self.queryTask = nil
            switch outcome {
            case .success(let value): self.handleQueryResult(value, sampledAt: sampledAt, fromPoll: fromPoll)
            case .failure(let error): self.note(error)
            }
            if self.queryAgain {
                self.queryAgain = false
                self.query(fromPoll: false)
            }
        }
    }

    private func handleQueryResult(_ value: ScriptValue, sampledAt date: Date, fromPoll: Bool) {
        guard isStarted else { return }
        if ScriptTemplate.isNotRunningMarker(value) {
            appDidTerminate()
            return
        }
        guard let parsed = App.parseState(value, at: date) else { return }
        let snapshot = setterHold.apply(to: parsed)
        if fromPoll, PollPolicy.isUnannouncedChange(polled: snapshot, known: state.snapshot) {
            pollPolicy.pollFoundUnannouncedChange()
        }
        state.snapshot = snapshot.filling(from: state.snapshot)
        reschedulePoll()
    }

    private func reschedulePoll() {
        pollTask?.cancel()
        pollTask = nil
        let snapshot = state.snapshot
        let remaining: TimeInterval? = {
            guard let duration = snapshot.track?.duration, let position = snapshot.position else { return nil }
            let elapsed = snapshot.status.isPlaying ? max(0, Date().timeIntervalSince(snapshot.timestamp)) : 0
            return max(0, duration - position - elapsed)
        }()
        guard let interval = pollPolicy.interval(
            isPlaying: state.availability.isRunning && snapshot.status.isPlaying,
            isAppFrontmost: isAppFrontmost && state.availability.isRunning,
            canQuery: state.permission == .granted,
            remaining: remaining
        ) else { return }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.query(fromPoll: true)
        }
    }

    /// Updates local state after the app accepted a command.
    private func applyConfirmed(_ command: PlaybackCommand) {
        var snapshot = state.snapshot
        let now = Date()
        switch command {
        case .play:
            snapshot.status = .playing
        case .pause:
            snapshot.status = .paused
        case .togglePlayPause:
            snapshot.status = snapshot.status.isPlaying ? .paused : .playing
        case .seek(let position):
            snapshot.position = position
            snapshot.timestamp = now
        case .setVolume(let volume):
            snapshot.volume = volume
        case .setShuffle(let shuffle):
            snapshot.shuffle = shuffle
        case .setRepeat(let mode):
            snapshot.repeatMode = mode
        case .setFavorite(let favorite):
            snapshot.isFavorite = favorite
        case .next, .previous, .beginScan, .endScan:
            return
        }
        if case .seek = command {} else if snapshot.status != state.snapshot.status, let position = state.snapshot.position {
            let elapsed = state.snapshot.status.isPlaying ? max(0, now.timeIntervalSince(state.snapshot.timestamp)) : 0
            snapshot.position = position + elapsed
            snapshot.timestamp = now
        }
        state.snapshot = snapshot
        reschedulePoll()
    }

    private func note(_ error: PlaybackError) {
        switch error {
        case .permissionDenied: state.permission = .denied
        case .permissionNotDetermined: state.permission = .notDetermined
        case .notRunning: appDidTerminate()
        default: break
        }
    }
}
