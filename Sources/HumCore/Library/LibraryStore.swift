import Foundation
import Observation

/// What Hum does with songs beyond Now's controls, for whichever source is
/// active: Favorite on any song, with the HUD's confirmation; the devices the
/// source can play on; Play Now on Echo's and the History window's songs; and
/// the artwork for songs outside Now (DESIGN.md §1.3).
///
/// The store follows `NowPlayingStore`'s active source and asks that source's
/// `LibraryProvider`. Nothing polls: the devices are asked for when the picker
/// opens, and again when what plays changes, at most every 15 seconds.
@MainActor
@Observable
public final class LibraryStore {
    // MARK: Dependencies

    @ObservationIgnored public let nowPlaying: NowPlayingStore
    @ObservationIgnored private let providers: [SourceID: any LibraryProvider]
    @ObservationIgnored public let thumbnails: ThumbnailCache
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    // MARK: State

    public private(set) var sourceID: SourceID?
    /// What the active source's library can do right now.
    public private(set) var capabilities: SourceCapabilities = []
    /// Set when the library can't do anything until the user acts.
    public private(set) var unavailable: LibraryUnavailable?
    public private(set) var devices = DeviceList()

    /// The HUD's current message.
    public private(set) var notice: LibraryNotice?
    /// The last action that didn't work, until dismissed.
    public private(set) var failure: LibraryFailure?
    /// Repeats the request behind `failure`, when Try Again is offered.
    @ObservationIgnored private var retryFailed: (@MainActor () -> Void)?
    /// The device playback is moving to.
    public private(set) var transferringDeviceID: String?
    /// Songs known to be saved or not, from Now and from actions.
    public private(set) var savedTrackIDs: [TrackID: Bool] = [:]

    // MARK: Private

    @ObservationIgnored private var observation: NowPlayingObservation?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var deviceLoad: Task<Void, Never>?
    @ObservationIgnored private var lastGate: Gate?
    /// Thumbnails already drawn, so a row scrolled back into view shows its
    /// artwork on its first frame.
    @ObservationIgnored private var drawnThumbnails: [String: LibraryThumbnail] = [:]
    @ObservationIgnored private var drawnOrder: [String] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastDeviceCheck: DeviceCheck?

    private struct DeviceCheck: Equatable {
        var track: TrackID?
        var isPlaying: Bool
    }

    private struct Gate: Equatable {
        var availability: SourceAvailability
        var permission: AutomationPermission
    }

    /// - Parameter providers: The sources' libraries. A source without one
    ///   that can start a song by its ID (`PlaybackSource.canPlaySongs`) gets
    ///   Play Now through the source itself.
    public init(
        nowPlaying: NowPlayingStore,
        providers: [any LibraryProvider],
        thumbnails: ThumbnailCache = ThumbnailCache(directory: nil),
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.nowPlaying = nowPlaying
        var byID = Dictionary(providers.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
        for source in nowPlaying.sources where byID[source.id] == nil && source.canPlaySongs {
            byID[source.id] = SourceSongProvider(source: source)
        }
        self.providers = byID
        self.thumbnails = thumbnails
        self.now = now
        self.sleep = sleep

        for provider in byID.values {
            provider.onChange = { [weak self, weak provider] in
                guard let self, let provider, provider.sourceID == self.sourceID else { return }
                self.providerDidChange()
            }
        }
        observation = nowPlaying.addObserver { [weak self] event in
            self?.handle(event)
        }
        Self.registry[ObjectIdentifier(nowPlaying)] = WeakStore(self)
        follow(preferredSource)
        observeNowPlaying()
    }

    // MARK: Association

    private struct WeakStore {
        weak var store: LibraryStore?
        init(_ store: LibraryStore) { self.store = store }
    }

    private static var registry: [ObjectIdentifier: WeakStore] = [:]

    /// The library that serves `nowPlaying`, for code that only has the player's
    /// store, such as the menu on Now.
    public static func attached(to nowPlaying: NowPlayingStore) -> LibraryStore? {
        registry[ObjectIdentifier(nowPlaying)]?.store
    }

    // MARK: Source

    public var provider: (any LibraryProvider)? {
        sourceID.flatMap { providers[$0] }
    }

    /// The source's name, for the places that may name the app: the History
    /// window and the Status page (DESIGN.md §10).
    public var sourceName: String {
        provider?.displayName ?? sourceID.flatMap { nowPlaying.source(for: $0)?.displayName } ?? ""
    }

    /// Where `artwork` came from: the art's own source, or for art that doesn't
    /// say (cached before Hum recorded it, or no art at all), the source this
    /// library follows.
    public func artworkSource(for artwork: LibraryArtwork?) -> SourceID? {
        artwork?.source ?? sourceID
    }

    private var preferredSource: SourceID? {
        let candidates = [nowPlaying.activeSourceID, nowPlaying.preferredSourceID, nowPlaying.lastActiveSourceID]
        if let id = candidates.compactMap({ $0 }).first(where: { providers[$0] != nil }) { return id }
        return nowPlaying.sources.map(\.id).first { providers[$0] != nil }
    }

    /// Whether this library is serving `id` right now.
    public func isServing(_ id: SourceID?) -> Bool {
        guard let id, let sourceID else { return false }
        return id == sourceID
    }

    private func follow(_ id: SourceID?) {
        guard id != sourceID else { return }
        HumLog.library.info("Library follows \(id?.rawValue ?? "no source", privacy: .public)")
        generation += 1
        deviceLoad?.cancel()
        deviceLoad = nil
        sourceID = id
        lastGate = nil
        // A failure and its fix belong to the source it came from.
        failure = nil
        retryFailed = nil
        devices = DeviceList()
        transferringDeviceID = nil
        savedTrackIDs = [:]
        lastDeviceCheck = nil
        providerDidChange()
    }

    private func providerDidChange() {
        capabilities = provider?.capabilities ?? []
        unavailable = provider?.unavailable
        lastGate = currentGate
        // The devices may be listed now, or no longer.
        if let reason = blocker(needing: .devices) {
            if devices.phase != .idle {
                deviceLoad?.cancel()
                devices = DeviceList(phase: .unavailable(reason))
            }
        } else if devices.unavailable != nil {
            devices.phase = .idle
        }
    }

    private var currentGate: Gate? {
        guard let sourceID, let state = nowPlaying.sourceStates[sourceID] else { return nil }
        return Gate(availability: state.availability, permission: state.permission)
    }

    /// Why a request needing `capability` can't be made now, or `nil` if it
    /// can. The words never name the app: the device picker, on the player,
    /// shows them (DESIGN.md §10).
    private func blocker(needing capability: SourceCapabilities) -> LibraryUnavailable? {
        guard let provider else {
            return LibraryUnavailable(title: "No Music App", message: "Open a music app to use this.")
        }
        if provider.requiresAppAccess, let gate = currentGate {
            switch gate.availability {
            case .notInstalled:
                return LibraryUnavailable(title: "Not Installed", message: "The music app isn’t installed.")
            case .notRunning:
                return LibraryUnavailable(
                    title: "Not Open",
                    message: "Open the music app to use this.",
                    fix: .openApp(provider.sourceID, name: provider.displayName)
                )
            case .running:
                break
            }
            switch gate.permission {
            case .denied:
                return LibraryUnavailable(
                    title: "No Access",
                    message: "Hum needs your permission to control your music app.",
                    fix: .openAutomationSettings
                )
            case .unknown, .notDetermined:
                return LibraryUnavailable(
                    title: "Allow Access",
                    message: "Hum needs your permission to control your music app.",
                    fix: .allowAutomation(app: provider.displayName)
                )
            case .granted, .notRequired:
                break
            }
        }
        if let reason = provider.unavailable { return reason }
        guard provider.capabilities.contains(capability) else {
            return LibraryUnavailable(title: "Not Available", message: "This music app can’t do that.")
        }
        return nil
    }

    private func handle(_ event: NowPlayingEvent) {
        switch event {
        case .sourceChanged:
            follow(preferredSource)
        case .trackChanged, .statusChanged, .seeked:
            break
        }
    }

    /// Watches what plays, to keep Save in step with Now, keep "Playing on …"
    /// current, and notice a source's state changing (opened, closed,
    /// permission granted).
    private func observeNowPlaying() {
        withObservationTracking {
            _ = nowPlaying.snapshot
            _ = nowPlaying.sourceStates
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.nowPlayingDidChange()
                self.observeNowPlaying()
            }
        }
    }

    private func nowPlayingDidChange() {
        if currentGate != lastGate { providerDidChange() }
        guard isServing(nowPlaying.activeSourceID) else { return }
        let snapshot = nowPlaying.snapshot
        followFavorite(of: snapshot)
        followDevice(of: snapshot)
    }

    /// Keeps the rows' Save in step with Save on Now.
    private func followFavorite(of snapshot: PlaybackSnapshot) {
        guard let track = snapshot.track, let favorite = snapshot.isFavorite else { return }
        if savedTrackIDs[track.id] != favorite {
            savedTrackIDs[track.id] = favorite
        }
    }

    /// Keeps "Playing on …" current. Playback most often moves when what
    /// plays changes, so the devices are asked again then, at most every
    /// 15 seconds.
    private func followDevice(of snapshot: PlaybackSnapshot) {
        guard showsDeviceStatus else { return }
        let check = DeviceCheck(track: snapshot.track?.id, isPlaying: snapshot.status.isPlaying)
        guard check != lastDeviceCheck else { return }
        lastDeviceCheck = check
        if devices.isStale(at: now(), maxAge: Self.deviceStatusMaxAge) { loadDevices() }
    }

    static let deviceStatusMaxAge: TimeInterval = 15

    // MARK: Playing

    /// Why Play Now can't start `request`, or `nil` when it can. Menus hide
    /// Play Now for a song with a reason, such as one Spotify doesn't know by
    /// its ID (DESIGN.md §4.4).
    public func playBlocker(for request: PlayRequest) -> String? {
        provider?.playBlocker(for: request)
    }

    /// Whether Play Now starts `request`.
    public func canPlay(_ request: PlayRequest) -> Bool {
        capabilities.canPlayItems && playBlocker(for: request) == nil
    }

    public func play(_ request: PlayRequest) {
        perform { provider throws(LibraryError) in
            try await provider.play(request)
        } then: {}
    }

    // MARK: Saving

    /// Saves or unsaves a song in a list. The song playing on Now goes through
    /// the source instead, whose Save button shows the result.
    public func setSaved(_ saved: Bool, track: LibraryTrack, announce: Bool = true) {
        let source = sourceID
        let previous = savedTrackIDs[track.id]
        savedTrackIDs[track.id] = saved
        perform { provider throws(LibraryError) in
            try await provider.setSaved(saved, track: track)
        } then: { [weak self] in
            if announce { self?.post(LibraryNotice(saved ? .saved : .unsaved, source: source)) }
        } failed: { [weak self] in
            self?.savedTrackIDs[track.id] = previous
        }
    }

    public func isSaved(_ track: LibraryTrack) -> Bool {
        savedTrackIDs[track.id] ?? false
    }

    // MARK: Devices

    public func loadDevices() {
        if let reason = blocker(needing: .devices) {
            devices = DeviceList(phase: .unavailable(reason))
            return
        }
        guard let provider else { return }
        deviceLoad?.cancel()
        devices.phase = .loading
        let generation = generation
        deviceLoad = Task { [weak self] in
            let result: Result<[PlaybackDevice], LibraryError>
            do throws(LibraryError) {
                result = .success(try await provider.devices())
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.deviceLoad = nil
            switch result {
            case .success(let value):
                self.devices = DeviceList(value: value, phase: .loaded, loadedAt: self.now())
            case .failure(.unavailable(let reason)):
                HumLog.library.info("Devices unavailable: \(reason.title, privacy: .public)")
                self.devices = DeviceList(phase: .unavailable(reason))
            case .failure(.cancelled):
                self.devices.phase = self.devices.value == nil ? .idle : .loaded
            case .failure(.failed(let message)), .failure(.transient(let message)):
                HumLog.library.error("Couldn't list devices: \(message, privacy: .private)")
                self.devices.phase = .failed(message)
            }
        }
    }

    /// Where the music is when it isn't this Mac, for `DeviceStatusRow` under
    /// the transport: "Playing on Kitchen", or "Connecting to Kitchen…" while a
    /// move is under way. `nil` while this Mac plays, before the devices have
    /// loaded, and for Music, whose AirPlay devices have their own picker.
    public var deviceStatus: DeviceStatus? {
        guard showsDeviceStatus else { return nil }
        return DeviceStatus.resolve(devices: devices.value ?? [], connectingTo: transferringDeviceID)
    }

    private var showsDeviceStatus: Bool {
        sourceID != .musicApp && capabilities.contains(.devices) && (nowPlaying.activeSourceID.map(isServing) ?? true)
    }

    public func transfer(to device: PlaybackDevice) {
        guard !device.isActive else { return }
        transferringDeviceID = device.id
        perform { provider throws(LibraryError) in
            try await provider.transfer(to: device)
        } then: { [weak self] in
            self?.transferringDeviceID = nil
            self?.loadDevices()
        } failed: { [weak self] in
            self?.transferringDeviceID = nil
        }
    }

    // MARK: Feedback

    /// Shows `notice` in the HUD. It goes away after 1.2 s, plus time to fade.
    public func post(_ notice: LibraryNotice) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task { [weak self, sleep] in
            try? await sleep(.milliseconds(1_400))
            guard !Task.isCancelled, self?.notice?.id == notice.id else { return }
            self?.notice = nil
        }
    }

    public func dismissFailure() {
        failure = nil
        retryFailed = nil
    }

    /// Try Again: dismisses the failure and repeats the request that failed,
    /// when it may work this time.
    public func retryFailure() {
        guard failure?.canRetry == true, let retry = retryFailed else { return }
        dismissFailure()
        retry()
    }

    private func perform(
        _ work: @escaping @MainActor (any LibraryProvider) async throws(LibraryError) -> Void,
        then success: @escaping @MainActor () -> Void,
        failed: (@MainActor () -> Void)? = nil
    ) {
        guard let provider else { return }
        let generation = generation
        Task { [weak self] in
            do throws(LibraryError) {
                try await work(provider)
                guard let self, self.generation == generation else { return }
                success()
            } catch {
                guard let self, self.generation == generation else { return }
                failed?()
                self.retryFailed = nil
                switch error {
                case .cancelled:
                    break
                case .unavailable(let reason):
                    HumLog.library.info("Library action unavailable: \(reason.title, privacy: .public)")
                    self.failure = LibraryFailure(message: reason.message, fix: reason.fix)
                    self.providerDidChange()
                case .failed(let message):
                    HumLog.library.error("Library action failed: \(message, privacy: .private)")
                    self.failure = LibraryFailure(message: message)
                case .transient(let message):
                    HumLog.library.error("Library action failed for now: \(message, privacy: .private)")
                    self.failure = LibraryFailure(message: message, canRetry: true)
                    self.retryFailed = { [weak self] in self?.perform(work, then: success, failed: failed) }
                }
            }
        }
    }

    // MARK: Thumbnails

    /// The artwork for a row, at about `pixelSide` pixels.
    public func thumbnail(for artwork: LibraryArtwork, pixelSide: Int) async -> LibraryThumbnail? {
        let source = sourceID
        let size = ThumbnailCache.Size.fitting(pixelSide: pixelSide)
        let thumbnail = await thumbnails.thumbnail(for: artwork, size: size) { @MainActor [weak self] in
            guard let self, let source, let provider = self.providers[source] else { return nil }
            return await provider.artworkData(for: artwork)
        }
        if let thumbnail {
            let key = Self.drawnKey(artwork, size)
            if drawnThumbnails.updateValue(thumbnail, forKey: key) == nil { drawnOrder.append(key) }
            if drawnOrder.count > 160 { drawnThumbnails[drawnOrder.removeFirst()] = nil }
        }
        return thumbnail
    }

    /// A thumbnail this session has already loaded, without waiting.
    public func drawnThumbnail(for artwork: LibraryArtwork, pixelSide: Int) -> LibraryThumbnail? {
        drawnThumbnails[Self.drawnKey(artwork, .fitting(pixelSide: pixelSide))]
    }

    private static func drawnKey(_ artwork: LibraryArtwork, _ size: ThumbnailCache.Size) -> String {
        "\(size.rawValue):\(artwork.key)"
    }
}
