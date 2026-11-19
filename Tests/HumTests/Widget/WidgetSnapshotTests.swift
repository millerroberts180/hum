import Foundation
@testable import HumCore
import Testing

@Suite("The widget snapshot")
struct WidgetSnapshotTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func playing(position: TimeInterval = 62, duration: TimeInterval? = 214) -> WidgetSnapshot {
        WidgetSnapshot(
            song: .init(title: "Low Tide Radio", artist: "Marlow Fields", album: "Coastline Hours", duration: duration),
            isPlaying: true,
            position: position,
            positionDate: start
        )
    }

    var full: WidgetSnapshot {
        WidgetSnapshot(
            song: .init(title: "Low Tide Radio", artist: "Marlow Fields", album: "Coastline Hours", duration: 214),
            isPlaying: true,
            position: 62.5,
            positionDate: start,
            shuffle: true,
            repeatMode: .one,
            actions: [.playPause, .next, .previous, .shuffle, .repeat],
            style: .bigArt,
            accent: PaletteColor(red: 1, green: 0.5, blue: 0.25),
            palette: .neutral,
            coverFile: "cover-abc.png"
        )
    }

    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hum-widget-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func decode(_ json: String) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))
    }

    // MARK: Reading and writing

    @Test func aSnapshotSurvivesTheTripThroughItsFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let written = try WidgetFiles.write(full, cover: nil, to: directory)
        #expect(written == full)
        #expect(WidgetFiles.readSnapshot(in: directory) == full)
    }

    @Test func nothingPlayingSurvivesTheTripToo() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try WidgetFiles.write(.nothingPlaying, cover: nil, to: directory)
        let read = try #require(WidgetFiles.readSnapshot(in: directory))
        #expect(read.song == nil)
        #expect(read.playback(at: start) == .nothingPlaying)
    }

    @Test func aNewCoverIsWrittenBesideTheSnapshotAndTheOldOneRemoved() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try WidgetFiles.write(playing(), cover: Data("one".utf8), to: directory)
        let firstName = try #require(first.coverFile)
        #expect(WidgetFiles.isCoverName(firstName))
        let firstURL = try #require(WidgetFiles.coverURL(for: first, in: directory))
        #expect(try Data(contentsOf: firstURL) == Data("one".utf8))

        let second = try WidgetFiles.write(playing(), cover: Data("two".utf8), to: directory)
        let secondName = try #require(second.coverFile)
        #expect(secondName != firstName)
        #expect(WidgetFiles.readSnapshot(in: directory)?.coverFile == secondName)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(files == [secondName, WidgetFiles.snapshotName].sorted())
    }

    @Test func aSnapshotWithoutACoverLeavesNoCoverBehind() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try WidgetFiles.write(playing(), cover: Data("one".utf8), to: directory)
        let bare = try WidgetFiles.write(playing(), cover: nil, to: directory)
        #expect(bare.coverFile == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [WidgetFiles.snapshotName])
    }

    @Test func aCoverNameThatLeavesTheFolderIsIgnored() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var snapshot = playing()
        snapshot.coverFile = "../snapshot.json"
        try WidgetFiles.write(snapshot, cover: nil, to: directory)
        #expect(WidgetFiles.coverURL(for: snapshot, in: directory) == nil)
        snapshot.coverFile = WidgetFiles.snapshotName
        #expect(WidgetFiles.coverURL(for: snapshot, in: directory) == nil)
    }

    @Test func noFileOrAnUnreadableOneIsNoSnapshot() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(WidgetFiles.readSnapshot(in: directory) == nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent(WidgetFiles.snapshotName))
        #expect(WidgetFiles.readSnapshot(in: directory) == nil)
    }

    @Test func theFolderIsTheFixedOneTheExtensionMayRead() {
        // The entitlement names this path relative to the home folder.
        #expect(WidgetFiles.relativePath == "Library/Application Support/Hum/widget")
        #expect(WidgetFiles.directory.path.hasSuffix("/Library/Application Support/Hum/widget"))
        #expect(!WidgetFiles.directory.path.contains("com.millerroberts.hum"))
    }

    // MARK: Lenient decoding

    @Test func anOlderPartialFileKeepsWhatItHas() throws {
        let snapshot = try decode(#"{"song":{"title":"Low Tide Radio","artist":"Marlow Fields"},"isPlaying":true}"#)
        #expect(snapshot.version == 0)
        #expect(snapshot.song == .init(title: "Low Tide Radio", artist: "Marlow Fields", album: "", duration: nil))
        #expect(snapshot.isPlaying)
        #expect(snapshot.position == 0)
        #expect(snapshot.shuffle == nil)
        #expect(snapshot.actions == [.show])
    }

    @Test func aFieldOfTheWrongTypeFallsBackAlone() throws {
        let snapshot = try decode("""
            {"version":1,"song":{"title":"A","artist":"B","album":"C","duration":"long"},
             "isPlaying":"yes","position":30,"positionDate":1800000000,"shuffle":true,
             "repeatMode":"sometimes","actions":["next","stop",7,"play-pause"],"style":7}
            """)
        #expect(snapshot.song == .init(title: "A", artist: "B", album: "C", duration: nil))
        #expect(!snapshot.isPlaying)
        #expect(snapshot.position == 30)
        #expect(snapshot.positionDate == start)
        #expect(snapshot.shuffle == true)
        #expect(snapshot.repeatMode == nil)
        #expect(snapshot.style == nil)
    }

    /// A file written before Glass, Data and Session were retired (DESIGN.md
    /// §13.19) may name one of them and hold Echo's insight and session trail.
    /// The rest of it still reads; the style reads as none.
    @Test(arguments: ["glass", "data", "session"])
    func aFileFromBeforeTheRetiredStylesStillDecodes(retired: String) throws {
        let snapshot = try decode("""
            {"version":1,"song":{"title":"Low Tide Radio","artist":"Marlow Fields","album":"Coastline Hours","duration":214},
             "isPlaying":true,"position":62.5,"positionDate":1800000000,"shuffle":true,"repeatMode":"one",
             "actions":["next","play-pause","previous","repeat","shuffle","show"],"style":"\(retired)",
             "accent":{"red":1,"green":0.5,"blue":0.25},"coverFile":"cover-abc.png",
             "insight":{"value":"23","label":"plays since you started listening"},
             "session":{"summary":"42 min · 9 songs · 6 artists","trail":[{"png":"AQID","color":{"red":0.1,"green":0.2,"blue":0.3}}]}}
            """)
        var expected = full
        expected.style = nil
        expected.palette = nil
        #expect(snapshot == expected)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let json = try #require(String(data: try encoder.encode(snapshot), encoding: .utf8))
        for word in [retired, "insight", "session", "trail"] {
            #expect(!json.contains(word), "\(word) written back")
        }
    }

    @Test func actionsANewerHumKnowsAreSkipped() throws {
        let snapshot = try decode(#"{"actions":["next","love","play-pause"]}"#)
        #expect(snapshot.actions == [.next, .playPause, .show])
    }

    @Test func aSongWithoutATitleIsNoSong() throws {
        #expect(try decode(#"{"song":{"artist":"B"},"isPlaying":true}"#).song == nil)
    }

    @Test func showIsAlwaysAllowed() {
        #expect(WidgetSnapshot(song: nil, actions: []).supports(.show))
        #expect(!WidgetSnapshot(song: nil, actions: []).supports(.next))
    }

    // MARK: No source

    @Test func theSnapshotHasNoPlaceForTheSource() throws {
        let fields = Mirror(reflecting: full).children.compactMap(\.label).map { $0.lowercased() }
        #expect(!fields.isEmpty)
        for word in ["source", "app", "player", "provider", "service"] {
            #expect(!fields.contains { $0.contains(word) }, "field naming \(word)")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let json = try #require(String(data: try encoder.encode(full), encoding: .utf8))
        #expect(!json.lowercased().contains("source"))
    }

    // MARK: Playback at a moment

    @Test func whilePlayingProgressRunsFromTheSongsStart() throws {
        let snapshot = playing()
        guard case .playing(let start, let end, let duration) = snapshot.playback(at: at(10)) else {
            Issue.record("not playing")
            return
        }
        #expect(abs(start.timeIntervalSince(at(-62))) < 1e-6)
        #expect(abs(try #require(end).timeIntervalSince(at(152))) < 1e-6)
        #expect(duration == 214)
        #expect(snapshot.songEnd == at(152))
    }

    @Test func aSnapshotPastItsSongsEndIsStaleAndShowsTheSongPaused() {
        let snapshot = playing()
        #expect(!snapshot.isStale(at: at(151.9)))
        #expect(snapshot.isStale(at: at(152)))
        #expect(snapshot.isStale(at: at(10_000)))
        #expect(snapshot.playback(at: at(152)) == .paused(position: 214, duration: 214))
        #expect(snapshot.playback(at: at(10_000)) == .paused(position: 214, duration: 214))
    }

    @Test func aPausedSnapshotNeverGoesStaleAndStandsStill() {
        var snapshot = playing()
        snapshot.isPlaying = false
        #expect(snapshot.songEnd == nil)
        #expect(!snapshot.isStale(at: at(10_000)))
        #expect(snapshot.playback(at: at(0)) == .paused(position: 62, duration: 214))
        #expect(snapshot.playback(at: at(10_000)) == .paused(position: 62, duration: 214))
    }

    @Test func aSongOfUnknownLengthPlaysOnWithNoEnd() {
        let snapshot = playing(duration: nil)
        #expect(snapshot.songEnd == nil)
        #expect(!snapshot.isStale(at: at(10_000)))
        guard case .playing(_, let end, nil) = snapshot.playback(at: at(10)) else {
            Issue.record("not playing")
            return
        }
        #expect(end == nil)
    }

    @Test func aPositionPastTheEndIsAlreadyStale() {
        let snapshot = playing(position: 300)
        #expect(snapshot.isStale(at: start))
        #expect(snapshot.playback(at: start) == .paused(position: 214, duration: 214))
    }
}
