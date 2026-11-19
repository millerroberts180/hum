import Foundation
@testable import HumCore
import Testing

@Suite("History store")
struct HistoryStoreTests {
    let calendar = HistoryFixtures.calendar

    func at(_ day: Int, _ hour: Int = 12) -> Date { HistoryFixtures.date(2025, 11, day, hour) }

    func memoryStore(_ listens: [Listen] = []) async throws -> HistoryStore {
        let store = try HistoryStore(url: nil)
        try await store.insert(contentsOf: listens)
        return store
    }

    func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: Round trip

    @Test func everyFieldSurvivesAFileRoundTrip() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        let original = Listen(
            trackID: TrackID("spotify:track:1"),
            title: "Night Drive, Part 2",
            artist: "The Examples",
            album: "Roads",
            source: .spotifyApp,
            context: PlaybackContext(kind: .playlist, name: "Late Shift", identifier: "spotify:playlist:9"),
            startedAt: at(3, 22),
            endedAt: at(3, 22).addingTimeInterval(400),
            listened: 12.5,
            duration: nil,
            ending: .skipped,
            counts: false,
            origin: .imported
        )
        let stored = try await HistoryStore(url: url).insert(original)
        #expect(stored.id > 0)

        let reopened = try HistoryStore(url: url)
        let listens = try await reopened.listens()
        #expect(listens == [stored])
        #expect(try await reopened.trackedSince() == original.startedAt)
    }

    @Test func fileStoresUseWriteAheadLogging() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        _ = try HistoryStore(url: url)
        let database = try SQLiteDatabase(url: url)
        #expect(try database.query("PRAGMA journal_mode") { $0.text(0) } == ["wal"])
    }

    // MARK: Migrations

    /// The newest version this Hum writes; the tests below add one past it.
    static let latest = HistorySchema.migrations.map(\.version).max() ?? 0

    @Test func migrationsRunOnceAndInOrder() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        let kept = try await HistoryStore(url: url).insert(HistoryFixtures.listen("Kept", at: at(1)))

        let addNotes = HistoryMigration(version: Self.latest + 1) { database in
            try database.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL)")
        }
        let upgraded = try HistoryStore(url: url, migrations: HistorySchema.migrations + [addNotes])
        #expect(try await upgraded.listens() == [kept])
        #expect(try HistorySchema.version(of: SQLiteDatabase(url: url)) == Self.latest + 1)

        // Opening again doesn't re-run the new version (it would fail: the table exists).
        _ = try HistoryStore(url: url, migrations: HistorySchema.migrations + [addNotes])
    }

    @Test func aFailedMigrationLeavesTheFileAsItWas() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        try await HistoryStore(url: url).insert(HistoryFixtures.listen("Kept", at: at(1)))
        let broken = HistoryMigration(version: Self.latest + 1) { database in
            try database.execute("ALTER TABLE plays ADD COLUMN rating INTEGER")
            try database.execute("THIS IS NOT SQL")
        }
        #expect(throws: (any Error).self) {
            try HistoryStore(url: url, migrations: HistorySchema.migrations + [broken])
        }
        #expect(try HistorySchema.version(of: SQLiteDatabase(url: url)) == Self.latest)
        #expect(try await HistoryStore(url: url).count() == 1)
    }

    @Test func aFileFromANewerHumIsNotTouched() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        let future = HistoryMigration(version: Self.latest + 1) { _ in }
        try await HistoryStore(url: url, migrations: HistorySchema.migrations + [future]).insert(HistoryFixtures.listen("Future", at: at(1)))

        #expect(throws: SQLiteDatabase.Failure.newerSchema(found: Self.latest + 1, supported: Self.latest)) { try HistoryStore(url: url) }
        let (fallback, problem) = HistoryStore.openOrFallback(url: url)
        #expect(problem != nil)
        #expect(fallback.fileURL == nil)
        #expect(try await fallback.count() == 0)
        #expect(try HistorySchema.version(of: SQLiteDatabase(url: url)) == Self.latest + 1)
        #expect(try await HistoryStore(url: url, migrations: HistorySchema.migrations + [future]).count() == 1)
    }

    /// A file at version 1 comes up to the latest version with its listens and
    /// its checkpoint as they were.
    @Test func aVersionOneFileKeepsWhatItHolds() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        let first = HistorySchema.migrations.filter { $0.version == 1 }
        let heard = HistoryFixtures.listen("Heard", at: at(2), source: .spotifyApp, trackID: "spotify:track:1")
        let old = try HistoryStore(url: url, migrations: first)
        try await old.insert(heard)
        try await old.insert(HistoryFixtures.listen("Music", at: at(3), source: .musicApp))
        try await old.savePending(PendingListen(
            track: heard.track, source: .spotifyApp, context: nil,
            startedAt: heard.startedAt, lastPlayedAt: heard.endedAt, listened: heard.listened
        ))
        #expect(try HistorySchema.version(of: SQLiteDatabase(url: url)) == 1)

        let upgraded = try HistoryStore(url: url)
        #expect(try HistorySchema.version(of: SQLiteDatabase(url: url)) == Self.latest)
        #expect(try await upgraded.listens().map(\.source) == [.spotifyApp, .musicApp])
        // The checkpoint matches the listen already kept, so it isn't kept twice.
        #expect(try await upgraded.recoverPending() == nil)
        #expect(try await upgraded.count() == 2)
    }

    // MARK: Removing

    @Test func removedListensComeBackUnderTheirIDs() async throws {
        let store = try await memoryStore([
            HistoryFixtures.listen("A", at: at(1)),
            HistoryFixtures.listen("B", at: at(2)),
            HistoryFixtures.listen("C", at: at(3)),
        ])
        let all = try await store.listens()
        let removed = try await store.delete(ids: [all[1].id])
        #expect(removed == [all[1]])
        #expect(try await store.listens().map(\.title) == ["A", "C"])

        try await store.restore(removed)
        #expect(try await store.listens() == all)
    }

    @Test func removingTheFirstListenKeepsWhenTrackingBegan() async throws {
        let store = try await memoryStore([HistoryFixtures.listen("A", at: at(1)), HistoryFixtures.listen("B", at: at(2))])
        let first = try #require(try await store.listens().first)
        _ = try await store.delete(ids: [first.id])
        #expect(try await store.trackedSince() == at(1))
    }

    @Test func erasingRemovesEverything() async throws {
        let store = try await memoryStore([HistoryFixtures.listen("A", at: at(1))])
        let track = Track(id: TrackID("t"), title: "T", artist: "A", album: "", duration: 100)
        try await store.savePending(PendingListen(track: track, source: .demo, context: nil, startedAt: at(2), lastPlayedAt: at(2), listened: 50))
        try await store.eraseAll()
        #expect(try await store.count() == 0)
        #expect(try await store.trackedSince() == nil)
        #expect(try await store.takePending() == nil)
    }

    // MARK: In-progress checkpoint

    @Test func thePendingListenIsTakenOnce() async throws {
        let store = try await memoryStore()
        let track = Track(id: TrackID("t"), title: "T", artist: "A", album: "B", duration: 100)
        let pending = PendingListen(track: track, source: .musicApp, context: PlaybackContext(kind: .album), startedAt: at(2), lastPlayedAt: at(2).addingTimeInterval(80), listened: 75)
        try await store.savePending(pending)
        #expect(try await store.takePending() == pending)
        #expect(try await store.takePending() == nil)

        try await store.savePending(pending)
        try await store.savePending(nil)
        #expect(try await store.takePending() == nil)
    }

    // MARK: Export

    @Test func jsonExportCarriesEveryField() async throws {
        let url = HistoryFixtures.temporaryURL("export.json")
        defer { cleanUp(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = try await memoryStore([
            HistoryFixtures.listen("A/B", at: at(4, 14), listened: 12.34, context: PlaybackContext(kind: .playlist, name: "Mix", identifier: "p1")),
            HistoryFixtures.listen("C", at: at(4, 15), duration: nil),
        ])
        #expect(try await store.export(.json, to: url) == 2)

        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["format"] as? String == "hum-listening-history")
        #expect(object["version"] as? Int == 1)
        let rows = try #require(object["listens"] as? [[String: Any]])
        #expect(rows.count == 2)
        let first = rows[0]
        #expect(Set(first.keys) == [
            "started_at", "ended_at", "title", "artist", "album", "track_id", "source", "context",
            "listened_seconds", "duration_seconds", "ending", "counts_as_play", "origin",
        ])
        #expect(first["started_at"] as? String == "2025-11-04T14:00:00Z")
        #expect(first["title"] as? String == "A/B")
        #expect(first["listened_seconds"] as? Double == 12.3)
        #expect(first["counts_as_play"] as? Bool == false)
        #expect(first["ending"] as? String == "skipped")
        let context = try #require(first["context"] as? [String: Any])
        #expect(context["kind"] as? String == "playlist")
        #expect(context["name"] as? String == "Mix")
        #expect(context["id"] as? String == "p1")
        #expect(rows[1]["duration_seconds"] == nil)
        #expect(rows[1]["counts_as_play"] as? Bool == false, "unknown length under 4 minutes")
    }

    @Test func csvExportQuotesAndUsesCRLF() async throws {
        let url = HistoryFixtures.temporaryURL("export.csv")
        defer { cleanUp(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = try await memoryStore([
            HistoryFixtures.listen("Hello, \"World\"", artist: "Line\nBreak", at: at(4, 14)),
        ])
        try await store.export(.csv, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: "\r\n")
        #expect(lines[0] == "started_at,ended_at,title,artist,album,track_id,source,context_kind,context_name,context_id,listened_seconds,duration_seconds,ending,counts_as_play,origin")
        #expect(lines[1] == "2025-11-04T14:00:00Z,2025-11-04T14:03:20Z,\"Hello, \"\"World\"\"\",\"Line\nBreak\",Album,\"t:Hello, \"\"World\"\"\",demo,,,,200,200,completed,true,tracked")
        #expect(lines.count == 3)
        #expect(lines[2].isEmpty)
    }

    @Test func csvFieldsAreQuotedOnlyWhenNeeded() {
        #expect(HistoryExport.quoted("plain") == "plain")
        #expect(HistoryExport.quoted("a,b") == "\"a,b\"")
        #expect(HistoryExport.quoted("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(HistoryExport.quoted("a\rb") == "\"a\rb\"")
    }

    // MARK: Queries

    @Test func topRanksCountedPlaysOnly() async throws {
        let mix = PlaybackContext(kind: .playlist, name: "Mix")
        let store = try await memoryStore(
            HistoryFixtures.plays("One", artist: "X", count: 3, endingAt: at(3), spacing: 3_600)
                + HistoryFixtures.plays("Two", artist: "Y", count: 2, endingAt: at(3), spacing: 3_600)
                + (0 ..< 5).map { HistoryFixtures.listen("Skipped", artist: "Z", at: at(2).addingTimeInterval(Double($0) * 60), listened: 10) }
                + [HistoryFixtures.listen("Three", artist: "X", album: "", at: at(1), context: mix)]
        )
        let songs = try await store.top(.songs, from: nil, to: nil)
        #expect(songs.map(\.title) == ["One", "Two", "Three"])
        #expect(songs.map(\.plays) == [3, 2, 1])
        #expect(songs[0].subtitle == "X")
        #expect(songs[0].listened == 600)

        #expect(try await store.top(.artists, from: nil, to: nil).map(\.title) == ["X", "Y"])
        #expect(try await store.top(.albums, from: nil, to: nil).map(\.plays) == [3, 2], "no-album listens are left out")
        #expect(try await store.top(.songs, from: at(2), to: nil).map(\.title) == ["One", "Two"])
    }

    /// Top ranks songs, artists, and albums; a song played from a playlist
    /// still ranks as itself (DESIGN.md §6.5).
    @Test func topRanksSongsArtistsAndAlbumsOnly() async throws {
        #expect(TopDimension.allCases.map(\.title) == ["Songs", "Artists", "Albums"])
        let mix = PlaybackContext(kind: .playlist, name: "Mix")
        let store = try await memoryStore(
            HistoryFixtures.plays("From the Mix", artist: "X", count: 2, endingAt: at(3), spacing: 3_600)
                .map { var listen = $0; listen.context = mix; return listen }
        )
        #expect(try await store.top(.songs, from: nil, to: nil).map(\.title) == ["From the Mix"])
        #expect(try await store.top(.artists, from: nil, to: nil).map(\.title) == ["X"])
        #expect(try await store.top(.albums, from: nil, to: nil).map(\.title) == ["Album"])
        #expect(try await store.filterOptions().playlists == ["Mix"], "the Playlist filter still offers it")
    }

    @Test func rediscoverFindsQuietFavorites() async throws {
        let store = try await memoryStore(
            HistoryFixtures.plays("Old Favorite", count: 4, endingAt: HistoryFixtures.daysAgo(90))
                + HistoryFixtures.plays("Too Few", count: 2, endingAt: HistoryFixtures.daysAgo(90))
                + HistoryFixtures.plays("Still Playing", count: 6, endingAt: HistoryFixtures.daysAgo(90))
                + [HistoryFixtures.listen("Still Playing", at: HistoryFixtures.daysAgo(1))]
        )
        let quiet = try await store.rediscover(quietSince: HistoryFixtures.daysAgo(60))
        #expect(quiet.map(\.title) == ["Old Favorite"])
        #expect(quiet.first?.plays == 4)
        #expect(quiet.first?.lastPlayed == HistoryFixtures.daysAgo(90))
    }

    @Test func dailyTotalsAddUpEachDay() async throws {
        let store = try await memoryStore([
            HistoryFixtures.listen("A", at: at(1, 9)),
            HistoryFixtures.listen("B", at: at(1, 20), listened: 10),
            HistoryFixtures.listen("C", at: at(3, 23)),
        ])
        let totals = try await store.dailyTotals(from: at(1, 0), to: at(5, 0), calendar: calendar)
        #expect(totals == [
            DayTotal(day: at(1, 0), listened: 210, plays: 1),
            DayTotal(day: at(3, 0), listened: 200, plays: 1),
        ])
    }

    @Test func searchTreatsWildcardsAsText() async throws {
        let store = try await memoryStore([
            HistoryFixtures.listen("100% Pure", at: at(1)),
            HistoryFixtures.listen("1000 Pure", at: at(2)),
            HistoryFixtures.listen("a_b", at: at(3)),
            HistoryFixtures.listen("axb", at: at(4)),
            HistoryFixtures.listen("back\\slash", at: at(4, 13)),
        ])
        func titles(_ search: String) async throws -> [String] {
            try await store.listens(matching: HistoryQuery(search: search), calendar: calendar).map(\.title)
        }
        #expect(try await titles("100%") == ["100% Pure"])
        #expect(try await titles("a_b") == ["a_b"])
        #expect(try await titles("k\\s") == ["back\\slash"])
        #expect(try await titles("PURE") == ["1000 Pure", "100% Pure"], "case-insensitive, newest first")
        #expect(try await titles("   ").count == 5)
    }

    @Test func filtersNarrowTheList() async throws {
        let mix = PlaybackContext(kind: .playlist, name: "Mix")
        let store = try await memoryStore([
            HistoryFixtures.listen("Morning", artist: "X", album: "First", at: at(1, 8), context: mix),
            HistoryFixtures.listen("Evening", artist: "X", album: "Second", at: at(1, 19)),
            HistoryFixtures.listen("Night", artist: "Y", album: "First", at: at(1, 23), context: PlaybackContext(kind: .album, name: "First")),
        ])
        func titles(_ query: HistoryQuery) async throws -> [String] {
            try await store.listens(matching: query, calendar: calendar).map(\.title)
        }
        #expect(try await titles(HistoryQuery(artist: "X")) == ["Evening", "Morning"])
        #expect(try await titles(HistoryQuery(album: "First")) == ["Night", "Morning"])
        #expect(try await titles(HistoryQuery(playlist: "Mix")) == ["Morning"])
        #expect(try await titles(HistoryQuery(timeOfDay: .evening)) == ["Evening"])
        #expect(try await titles(HistoryQuery(artist: "X", timeOfDay: .night)) == [])
        #expect(try await titles(HistoryQuery(limit: 2)) == ["Night", "Evening"])

        let options = try await store.filterOptions()
        #expect(options.artists == ["X", "Y"])
        #expect(options.albums == ["First", "Second"])
        #expect(options.playlists == ["Mix"])
    }

    @Test func matchesAreCountedPastTheLimit() async throws {
        let store = try await memoryStore(
            (1...5).map { HistoryFixtures.listen("Evening \($0)", artist: "X", at: at($0, 19)) }
                + (1...2).map { HistoryFixtures.listen("Morning \($0)", artist: "X", at: at($0, 8)) }
                + [HistoryFixtures.listen("Other", artist: "Y", at: at(6, 19))]
        )
        func count(_ query: HistoryQuery) async throws -> Int {
            try await store.count(matching: query, calendar: calendar)
        }
        #expect(try await count(HistoryQuery(artist: "X", limit: 2)) == 7)
        #expect(try await count(HistoryQuery(search: "even", limit: 2)) == 5)
        #expect(try await count(HistoryQuery(artist: "X", timeOfDay: .evening, limit: 2)) == 5)
        #expect(try await count(HistoryQuery(timeOfDay: .morning, limit: 1)) == 2)
        #expect(try await count(HistoryQuery(artist: "Z")) == 0)
        #expect(try await count(HistoryQuery()) == 8)
    }

    @Test func perSongLookups() async throws {
        let store = try await memoryStore(
            HistoryFixtures.plays("A", count: 3, endingAt: at(3))
                + [HistoryFixtures.listen("B", at: at(2), listened: 5), HistoryFixtures.listen("B", at: at(4), source: .musicApp)]
        )
        let a = SongKey.make(artist: "Artist", title: "A")
        let b = SongKey.make(artist: "Artist", title: "B")
        #expect(try await store.firstHeard(songKeys: [a, b]) == [a: at(1), b: at(2)])
        #expect(try await store.playCounts(from: at(2), to: at(5)) == [a: 2, b: 1])
        #expect(try await store.listens(songKey: b).count == 2)
        #expect(try await store.sources() == [.demo, .musicApp])
        #expect(try await store.sources(from: at(4)) == [.musicApp])
        #expect(try await store.spans().count == 5)
    }
}
