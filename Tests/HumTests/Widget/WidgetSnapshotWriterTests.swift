import CoreGraphics
import Foundation
@testable import HumCore
@testable import HumUI
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Stands in for `Task.sleep`: holds each sleeper until the test wakes it, or,
/// when `immediate`, moves the clock on and returns at once.
@MainActor
final class WidgetTestSleeper {
    private(set) var requests: [Duration] = []
    var immediate = false
    private let clock: TestClock
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(clock: TestClock) {
        self.clock = clock
    }

    func sleep(_ duration: Duration) async {
        requests.append(duration)
        if immediate {
            clock.advance(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func wake() {
        let sleepers = waiting
        waiting = []
        for sleeper in sleepers { sleeper.resume() }
    }
}

@MainActor
final class WidgetReloadCounter {
    var count = 0
}

@MainActor
@Suite("Writing the widget snapshot")
final class WidgetSnapshotWriterTests {
    let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("hum-widget-writer-\(UUID().uuidString)", isDirectory: true)
    let sleeper: WidgetTestSleeper
    let reloads = WidgetReloadCounter()
    let settings = SettingsStore(fileURL: nil)
    var source: FakeSource!
    var store: NowPlayingStore!

    init() {
        sleeper = WidgetTestSleeper(clock: clock)
        use(FakeSource(state: Fixtures.state(position: 10, at: clock.now)))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func use(_ source: FakeSource) {
        let clock = clock
        self.source = source
        store = NowPlayingStore(sources: [source], now: { clock.now })
        store.start()
    }

    func makeWriter() -> WidgetSnapshotWriter {
        let clock = clock, sleeper = sleeper, reloads = reloads
        return WidgetSnapshotWriter(
            store: store,
            directory: directory,
            now: { clock.now },
            sleep: { await sleeper.sleep($0) },
            reload: { reloads.count += 1 }
        )
    }

    var written: WidgetSnapshot? {
        WidgetFiles.readSnapshot(in: directory)
    }

    func push(
        track: Track? = Fixtures.track(),
        status: PlaybackStatus = .playing,
        position: TimeInterval,
        shuffle: Bool? = nil,
        repeatMode: RepeatMode? = nil
    ) {
        var state = Fixtures.state(track: track, status: status, position: position, at: clock.now)
        state.snapshot.shuffle = shuffle
        state.snapshot.repeatMode = repeatMode
        source.push(state)
    }

    /// Lets observation callbacks and the store's own tasks run.
    func letChangesLand() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
        for _ in 0..<20 { await Task.yield() }
    }

    /// Waits up to 30 s for `condition`, which takes that long only when the
    /// whole suite is busy on the main actor; the expectations after it say
    /// what must hold.
    func waitFor(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: When it writes

    @Test func startingWritesTheSongAndReloadsOnce() async throws {
        let writer = makeWriter()
        writer.start()
        await writer.settle()
        #expect(reloads.count == 1)
        let snapshot = try #require(written)
        #expect(snapshot.song == .init(title: "Title t1", artist: "Artist", album: "Album", duration: 200))
        #expect(snapshot.isPlaying)
        #expect(abs(snapshot.position - 10) < 0.001)
        #expect(snapshot.positionDate == clock.now)
        #expect(snapshot.actions == Set(HumURLAction.allCases))
    }

    @Test func changesInsideTwoSecondsFoldIntoOneReloadCarryingTheLast() async throws {
        let writer = makeWriter()
        writer.start()
        await writer.settle()
        #expect(reloads.count == 1)

        clock.advance(0.5)
        push(status: .paused, position: 10.5)
        await waitFor { !sleeper.requests.isEmpty }
        #expect(sleeper.requests == [.milliseconds(1500)])
        #expect(reloads.count == 1)
        #expect(written?.isPlaying == true)

        clock.advance(0.5)
        push(status: .playing, position: 10.5, shuffle: true, repeatMode: .one)
        await letChangesLand()
        // Still one reload, and no second wait: the waiting one will carry it.
        #expect(reloads.count == 1)
        #expect(sleeper.requests.count == 1)

        clock.advance(1)
        sleeper.wake()
        await waitFor { reloads.count == 2 }
        await writer.settle()
        #expect(reloads.count == 2)
        let snapshot = try #require(written)
        #expect(snapshot.isPlaying)
        #expect(snapshot.shuffle == true)
        #expect(snapshot.repeatMode == .one)
    }

    @Test func progressAloneWritesNothing() async {
        let writer = makeWriter()
        writer.start()
        await writer.settle()
        clock.advance(30)
        await letChangesLand()
        // The source reports the same song further on, as it does now and then.
        push(position: 40)
        await letChangesLand()
        #expect(reloads.count == 1)
        #expect(sleeper.requests.isEmpty)
    }

    @Test func eachChangeTheWidgetsShowIsWritten() async throws {
        let writer = makeWriter()
        writer.start()
        await writer.settle()
        sleeper.immediate = true
        var expected = 1

        func expectWrite(_ check: (WidgetSnapshot) -> Bool, _ comment: Comment) async {
            expected += 1
            await waitFor { reloads.count == expected }
            await writer.settle()
            #expect(reloads.count == expected, comment)
            #expect(written.map(check) == true, comment)
        }

        clock.advance(3)
        push(track: Fixtures.track("t2"), position: 0)
        await expectWrite({ $0.song?.title == "Title t2" }, "song")
        clock.advance(3)
        push(track: Fixtures.track("t2"), status: .paused, position: 3)
        await expectWrite({ !$0.isPlaying }, "play state")
        clock.advance(3)
        push(track: Fixtures.track("t2"), status: .paused, position: 3, shuffle: true)
        await expectWrite({ $0.shuffle == true }, "shuffle")
        clock.advance(3)
        push(track: Fixtures.track("t2"), status: .paused, position: 3, shuffle: true, repeatMode: .all)
        await expectWrite({ $0.repeatMode == .all }, "repeat")
        clock.advance(3)
        push(track: Fixtures.track("t2"), status: .paused, position: 120, shuffle: true, repeatMode: .all)
        await expectWrite({ abs($0.position - 120) < 0.001 }, "a seek")
    }

    @Test func aJumpWhileAWriteIsStillMakingTheCoverIsWrittenToo() async throws {
        source.artworkData = Self.png(side: 900)
        await waitFor { store.artwork != nil }
        let writer = makeWriter()
        // The first write makes the cover off the main actor. Before it lands,
        // the position jumps: a seek, or the source correcting where Hum
        // guessed it was as a command went out.
        writer.start()
        push(position: 100)
        await writer.settle()
        await letChangesLand()
        #expect(reloads.count == 1)
        #expect(sleeper.requests == [.milliseconds(2000)])

        clock.advance(2)
        sleeper.wake()
        await waitFor { reloads.count == 2 }
        await writer.settle()
        let snapshot = try #require(written)
        #expect(snapshot.isPlaying)
        #expect(abs(snapshot.position - 102) < 0.001)
        #expect(snapshot.coverFile != nil)
    }

    @Test func nothingPlayingIsWrittenAsNoSong() async throws {
        use(FakeSource(state: Fixtures.state(track: nil, status: .stopped, position: nil, at: clock.now)))
        let writer = makeWriter()
        writer.start()
        await writer.settle()
        let snapshot = try #require(written)
        #expect(snapshot.song == nil)
        #expect(snapshot.playback(at: clock.now) == .nothingPlaying)
    }

    @Test func quittingWritesTheSongPausedAndStopsWriting() async throws {
        let writer = makeWriter()
        writer.start()
        await writer.settle()
        clock.advance(3)
        writer.writeForQuit()
        #expect(reloads.count == 2)
        let snapshot = try #require(written)
        #expect(snapshot.song?.title == "Title t1")
        #expect(!snapshot.isPlaying)
        #expect(abs(snapshot.position - 13) < 0.001)

        clock.advance(3)
        push(track: Fixtures.track("t2"), position: 0)
        await letChangesLand()
        #expect(reloads.count == 2)
        #expect(written?.song?.title == "Title t1")
    }

    @Test func theTransportFollowsWhatTheSourceCanDo() async throws {
        use(FakeSource(state: Fixtures.state(position: 10, at: clock.now, capabilities: [.playPause, .skipNext])))
        let writer = makeWriter()
        writer.start()
        await writer.settle()
        #expect(written?.actions == [.playPause, .next, .show])
    }

    // MARK: What it writes

    @Test func theMusicAppIsNeverNamed() async throws {
        let spotify = FakeSource(
            id: SourceID("spotify"),
            displayName: "Spotify",
            appBundleIdentifier: "com.spotify.client",
            state: Fixtures.state(position: 10, at: clock.now)
        )
        use(spotify)
        let writer = makeWriter()
        writer.start()
        await writer.settle()
        let data = try Data(contentsOf: directory.appendingPathComponent(WidgetFiles.snapshotName))
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        #expect(json.contains("title t1"))
        #expect(!json.contains("spotify"))
        #expect(!json.contains("source"))
    }

    @Test func theCoverIsWrittenSmallAndFollowsTheSong() async throws {
        source.artworkData = Self.png(side: 900)
        sleeper.immediate = true
        let writer = makeWriter()
        writer.start()
        await waitFor { written?.coverFile != nil }
        await writer.settle()
        let snapshot = try #require(written)
        let url = try #require(WidgetFiles.coverURL(for: snapshot, in: directory))
        let image = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width == 600 && image.height == 600)
        #expect(snapshot.palette != nil)

        source.artworkData = nil
        clock.advance(3)
        push(track: Fixtures.track("t2"), position: 0)
        await waitFor { written?.song?.title == "Title t2" }
        await writer.settle()
        #expect(written?.coverFile == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == [WidgetFiles.snapshotName])
    }

    @Test func aNewSongNeverCarriesTheLastSongsCover() async throws {
        source.artworkData = Self.png(side: 900)
        sleeper.immediate = true
        let writer = makeWriter()
        writer.start()
        await waitFor { written?.coverFile != nil }
        await writer.settle()
        #expect(written?.coverFile != nil)

        source.artworkData = nil
        clock.advance(3)
        push(track: Fixtures.track("t2"), position: 0)
        // The store keeps the last song's cover until the new one loads.
        #expect(store.artwork != nil)
        let snapshot = writer.makeSnapshot(at: clock.now, paused: false)
        #expect(snapshot.song?.title == "Title t2")
        #expect(snapshot.palette == nil)
        await writer.write().value
        #expect(written?.song?.title == "Title t2")
        #expect(written?.coverFile == nil)
    }

    @Test func theAccentIsTheSystemsUnlessSettingsSayOtherwise() async throws {
        let writer = makeWriter()
        writer.settings = settings
        settings.appearance.style = .bigArt
        settings.appearance.accent = .system
        writer.start()
        await writer.settle()
        #expect(written?.style == .bigArt)
        #expect(written?.accent == nil)

        settings.appearance.accent = .custom
        settings.appearance.customAccent = PaletteColor(red: 0.1, green: 0.1, blue: 0.3)
        let snapshot = writer.makeSnapshot(at: clock.now, paused: false)
        let accent = try #require(snapshot.accent)
        // Lifted to read as a glyph over the cover (DESIGN.md §3.5.3).
        #expect(accent.contrast(with: .black) >= AccentResolver.glyphContrast - 0.01)
    }

    static func png(side: Int) -> Data {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
