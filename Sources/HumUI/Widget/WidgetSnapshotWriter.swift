import AppKit
import HumCore
import ImageIO
import UniformTypeIdentifiers
import WidgetKit

/// Keeps Hum's widgets current (DESIGN.md §7.3): writes a `WidgetSnapshot` and
/// the cover into the widget folder, then asks WidgetKit to reload.
///
/// It writes when the song, the play state, shuffle or repeat changes (and when
/// a song's cover arrives after it, or when the position jumps), at most once
/// every 2 s; changes inside that window fold into
/// one write that carries the latest state. Progress runs on in the widget by
/// itself, so nothing is written while nothing changes. As Hum quits it writes
/// the song paused, so the widgets show "Hum not running" honestly.
@MainActor public final class WidgetSnapshotWriter {
    /// The settings, for the player style and the accent mode. Without them the
    /// snapshot names no style and the widgets use the system accent.
    public var settings: SettingsStore?

    private let store: NowPlayingStore
    private let directory: URL
    private let now: @MainActor () -> Date
    private let sleep: @MainActor (Duration) async -> Void
    private let reload: @MainActor () -> Void

    private var throttle = WidgetReloadThrottle()
    private var lastSignature: Signature?
    /// The snapshot last handed to a write, to tell a jump in position from
    /// progress. It's kept as the write starts, not when it lands, so a jump
    /// that arrives while the write is still making a cover is written too.
    private var lastMade: WidgetSnapshot?
    /// The cover on disk, and the image it was made from.
    private var writtenCover: (image: ArtworkImage, file: String)?
    private var writing: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?
    private var isStarted = false
    private var isTerminating = false
    private var terminationObserver: (any NSObjectProtocol)?

    /// A cover is written at most this many pixels on its long side.
    static let coverPixels = 600
    /// A position this far from where the last snapshot says it should be is a
    /// seek, in Hum or in the music app, and the widgets' progress needs it.
    static let positionJumpTolerance: TimeInterval = 2

    /// - Parameter directory: Where to write; `nil` is `WidgetFiles.directory`,
    ///   the fixed folder the widget extension reads.
    public convenience init(store: NowPlayingStore, directory: URL? = nil) {
        self.init(store: store, directory: directory, now: { Date() })
    }

    init(
        store: NowPlayingStore,
        directory: URL?,
        now: @escaping @MainActor () -> Date,
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        reload: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.store = store
        self.directory = directory ?? WidgetFiles.directory
        self.now = now
        self.sleep = sleep
        self.reload = reload
    }

    /// Write the current state now and follow changes from here on.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        observeChanges { [weak self] in
            self?.check()
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeForQuit() }
        }
    }

    // MARK: Changes

    /// What the widgets show that's worth a reload when it changes.
    struct Signature: Equatable {
        var song: WidgetSnapshot.Song?
        var isPlaying: Bool
        var shuffle: Bool?
        var repeatMode: RepeatMode?
        var actions: Set<HumURLAction>
        var cover: ObjectIdentifier?
    }

    private var signature: Signature {
        Signature(
            song: song,
            isPlaying: store.isPlaying,
            shuffle: store.snapshot.shuffle,
            repeatMode: store.snapshot.repeatMode,
            actions: actions,
            cover: artwork.map(ObjectIdentifier.init)
        )
    }

    /// Reads everything the snapshot depends on, so the observation follows it.
    private func check() {
        let current = signature
        let jumped = positionJumped()
        guard isStarted, current != lastSignature || jumped else { return }
        lastSignature = current
        changed()
    }

    private func positionJumped() -> Bool {
        guard let lastMade, lastMade.song != nil, store.track != nil else { return false }
        let date = now()
        let expected: TimeInterval = switch lastMade.playback(at: date) {
        case .playing(let start, _, _): date.timeIntervalSince(start)
        case .paused(let position, _): position
        case .nothingPlaying: 0
        }
        return abs(store.position(at: date) - expected) > Self.positionJumpTolerance
    }

    private func changed() {
        switch throttle.change(at: now()) {
        case .reloadNow:
            write()
        case .reload(let due):
            let delay = max(0, due.timeIntervalSince(now()))
            pendingTask = Task { [weak self] in
                await self?.sleep(.milliseconds(Int((delay * 1000).rounded(.up))))
                guard let self, !Task.isCancelled, !self.isTerminating else { return }
                self.throttle.didReload(at: self.now())
                self.write()
            }
        case .alreadyPending:
            break
        }
    }

    // MARK: Writing

    /// Write the snapshot (making the cover off the main actor when it's new),
    /// then reload. Writes run one after another, in order.
    @discardableResult
    func write() -> Task<Void, Never> {
        let snapshot = makeSnapshot(at: now(), paused: false)
        lastMade = snapshot
        let artwork = self.artwork
        let newCover = artwork.flatMap { $0 === writtenCover?.image ? nil : $0 }
        let previous = writing
        let task = Task { [weak self] in
            await previous?.value
            var png: Data?
            if let newCover {
                png = await Self.png(newCover.cgImage, maxPixels: Self.coverPixels)
            }
            guard let self, !self.isTerminating else { return }
            self.save(snapshot, artwork: artwork, png: png)
            self.reload()
        }
        writing = task
        return task
    }

    /// Wait for the writes started so far.
    func settle() async {
        await writing?.value
    }

    /// Write synchronously as Hum quits: the song paused where it is, with the
    /// cover already on disk.
    func writeForQuit() {
        guard isStarted, !isTerminating else { return }
        pendingTask?.cancel()
        isTerminating = true
        throttle.flush(at: now())
        save(makeSnapshot(at: now(), paused: true), artwork: artwork, png: nil)
        reload()
    }

    /// Write `snapshot` with the cover of `artwork`: `png` when it's newly
    /// encoded, the file already on disk when it was made from the same image,
    /// and none otherwise, so a song never shows another song's cover.
    private func save(_ snapshot: WidgetSnapshot, artwork: ArtworkImage?, png: Data?) {
        var snapshot = snapshot
        let reused = artwork != nil && png == nil && artwork === writtenCover?.image
        snapshot.coverFile = reused ? writtenCover?.file : nil
        do {
            let written = try WidgetFiles.write(snapshot, cover: artwork == nil ? nil : png, to: directory)
            if let artwork, let file = written.coverFile {
                writtenCover = (artwork, file)
            } else {
                writtenCover = nil
            }
        } catch {
            HumLog.app.error("Couldn’t write the widget snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: The snapshot

    func makeSnapshot(at date: Date, paused: Bool) -> WidgetSnapshot {
        guard let song else { return WidgetSnapshot(song: nil, positionDate: date, actions: actions, style: settings?.appearance.style) }
        let palette = artwork?.palette
        return WidgetSnapshot(
            song: song,
            isPlaying: store.isPlaying && !paused,
            position: store.position(at: date),
            positionDate: date,
            shuffle: store.snapshot.shuffle,
            repeatMode: store.snapshot.repeatMode,
            actions: actions,
            style: settings?.appearance.style,
            accent: accent(palette: palette),
            palette: palette
        )
    }

    /// The cover, when it's the current song's: after a song change the store
    /// keeps the last song's cover until the new one loads.
    private var artwork: ArtworkImage? {
        guard let artwork = store.artwork, let track = store.track, let source = store.artworkSourceID,
            artwork.key == track.artworkKey(source: source)
        else { return nil }
        return artwork
    }

    private var song: WidgetSnapshot.Song? {
        store.track.map { WidgetSnapshot.Song(title: $0.title, artist: $0.artist, album: $0.album, duration: $0.duration) }
    }

    /// The transport the source can do, as the player's transport shows it.
    private var actions: Set<HumURLAction> {
        let capabilities = store.capabilities
        var actions: Set<HumURLAction> = [.show]
        if capabilities.contains(.playPause) { actions.insert(.playPause) }
        if capabilities.contains(.skipNext) { actions.insert(.next) }
        if capabilities.contains(.skipPrevious) { actions.insert(.previous) }
        if capabilities.contains(.shuffle) { actions.insert(.shuffle) }
        if !capabilities.repeatCycle.isEmpty { actions.insert(.repeat) }
        return actions
    }

    /// The accent for active toggles over the cover's context, or `nil` for the
    /// system accent, which the widget resolves itself.
    private func accent(palette: ArtworkPalette?) -> PaletteColor? {
        guard let settings else { return nil }
        let mode = settings.appearance.accent
        guard mode != .system else { return nil }
        let preferred = mode == .album ? palette?.accent : settings.appearance.customAccent
        return preferred.flatMap { AccentResolver.adjust($0, on: .dark, ratio: AccentResolver.glyphContrast) }
    }

    // MARK: Images

    /// `image` scaled to fit `maxPixels` and encoded as PNG.
    @concurrent nonisolated static func png(_ image: CGImage, maxPixels: Int) async -> Data? {
        let scale = min(1, CGFloat(maxPixels) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
