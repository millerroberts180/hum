import Foundation
@testable import HumCore
import Testing

/// How the history file holds up: what removing listens leaves behind, how big
/// the log grows, which indexes the slow lookups use, and the import's
/// duplicate check against a plain reading of its rules.
@Suite("History storage")
struct HistoryStorageTests {
    func at(_ day: Int, _ hour: Int = 12) -> Date { HistoryFixtures.date(2025, 11, day, hour) }

    func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// The file and its write-ahead log, as bytes.
    func bytes(_ url: URL) -> Data {
        let wal = URL(fileURLWithPath: url.path + "-wal")
        return ((try? Data(contentsOf: url)) ?? Data()) + ((try? Data(contentsOf: wal)) ?? Data())
    }

    func logSize(_ url: URL) -> Int {
        let wal = url.path + "-wal"
        return ((try? FileManager.default.attributesOfItem(atPath: wal))?[.size] as? Int) ?? 0
    }

    func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    // MARK: Removing

    /// Erase All History leaves nothing of what was erased in the file or its
    /// log, and gives the space back.
    @Test func erasingLeavesNoTrace() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        let secret = "Quokka Marmalade Overture"
        let store = try HistoryStore(url: url)
        try await store.insert(contentsOf: (0 ..< 400).map {
            HistoryFixtures.listen(secret + " \($0)", artist: "The Erasables", at: at(1).addingTimeInterval(Double($0) * 300))
        })
        await store.checkpoint()
        let before = fileSize(url)
        #expect(bytes(url).range(of: Data(secret.utf8)) != nil)

        try await store.eraseAll()
        #expect(try await store.count() == 0)
        #expect(bytes(url).range(of: Data(secret.utf8)) == nil)
        #expect(bytes(url).range(of: Data("The Erasables".utf8)) == nil)
        #expect(fileSize(url) < before, "the space is given back")
        #expect(logSize(url) == 0)
    }

    /// Remove Imported History takes the imported listens out of the file too,
    /// and keeps every tracked one.
    @Test func removingImportedHistoryLeavesNoTrace() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        let imported = "Imported Albatross Lullaby"
        let store = try HistoryStore(url: url)
        try await store.insert(HistoryFixtures.listen("Kept Song", artist: "Stays", at: at(20)))
        try await store.insertImported((0 ..< 300).map {
            HistoryFixtures.listen(imported + " \($0)", artist: "Gone", at: at(1).addingTimeInterval(Double($0) * 300))
        })
        await store.checkpoint()
        #expect(bytes(url).range(of: Data(imported.utf8)) != nil)

        #expect(try await store.removeImported() == 300)
        #expect(bytes(url).range(of: Data(imported.utf8)) == nil)
        #expect(logSize(url) == 0)
        let left = try await store.listens()
        #expect(left.map(\.title) == ["Kept Song"])
        #expect(left.first?.origin == .tracked)
        #expect(try await store.trackedSince() == at(20))
    }

    /// Removed listens are overwritten as they go, even before the file is
    /// compacted: a single listen removed from the list leaves no copy.
    @Test func removingOneListenOverwritesIt() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        let store = try HistoryStore(url: url)
        let kept = try await store.insert(HistoryFixtures.listen("Ordinary Song", at: at(1)))
        let removed = try await store.insert(HistoryFixtures.listen("Pangolin Serenade", at: at(2)))
        _ = try await store.delete(ids: [removed.id])
        await store.checkpoint()
        #expect(bytes(url).range(of: Data("Pangolin Serenade".utf8)) == nil)
        #expect(try await store.listens().map(\.id) == [kept.id])
    }

    // MARK: The log

    /// A big import doesn't leave the write-ahead log at its size.
    @Test func anImportEmptiesTheLog() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        let store = try HistoryStore(url: url)
        let listens = (0 ..< 2_000).map {
            HistoryFixtures.listen("Song \($0 % 300)", artist: "Artist \($0 % 40)", at: at(1).addingTimeInterval(Double($0) * 240))
        }
        let summary = try await store.importListens(HistoryImport.Batch(files: [listens]))
        #expect(summary.added == 2_000)
        #expect(logSize(url) == 0)
        #expect(try await store.count() == 2_000)
    }

    // MARK: Indexes

    /// A file from an earlier Hum gets the imported listens' index when it's
    /// opened, keeps its listens and schema version, and still opens in that
    /// Hum afterwards.
    @Test func anOlderFileGetsTheIndexAndKeepsItsListens() async throws {
        let url = HistoryFixtures.temporaryURL()
        defer { cleanUp(url) }
        do {
            let older = try HistoryStore(url: url, migrations: HistorySchema.migrations)
            try await older.insert(HistoryFixtures.listen("Before", at: at(1)))
        }
        // Take the index out again, as the earlier Hum left the file.
        do {
            let database = try SQLiteDatabase(url: url)
            try database.execute("DROP INDEX plays_imported")
            #expect(try indexes(database).contains("plays_imported") == false)
        }

        let store = try HistoryStore(url: url)
        #expect(try await store.listens().map(\.title) == ["Before"])
        let database = try SQLiteDatabase(url: url)
        #expect(try indexes(database).contains("plays_imported"))
        #expect(try HistorySchema.version(of: database) == 2)
        // The earlier Hum's own migrations find nothing to do.
        try HistorySchema.migrate(database, migrations: HistorySchema.migrations)
    }

    func indexes(_ database: SQLiteDatabase) throws -> [String] {
        try database.query("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'plays'") { $0.text(0) }
    }

    @Test func theSlowLookupsUseTheirIndexes() async throws {
        let store = try HistoryStore(url: nil)
        let firstHeard = try await store.queryPlan(HistoryStore.firstHeardOfOriginSQL, [.text("key"), .text("tracked")])
        #expect(firstHeard.contains { $0.contains("plays_by_song") }, "\(firstHeard)")
        #expect(!firstHeard.contains { $0.contains("TEMP B-TREE") }, "no sort: the index is in order")
        let anyOrigin = try await store.queryPlan(HistoryStore.firstHeardSQL, [.text("key")])
        #expect(anyOrigin.contains { $0.contains("COVERING INDEX plays_by_song") }, "\(anyOrigin)")
        let imported = try await store.queryPlan(HistoryStore.importedHistorySQL)
        #expect(imported.contains { $0.contains("COVERING INDEX plays_imported") }, "\(imported)")
    }

    // MARK: First heard

    /// The first listen counts from the earliest of `origin`, or of any origin.
    @Test func firstHeardTakesTheEarliestListenOfItsOrigin() async throws {
        let store = try HistoryStore(url: nil)
        let a = SongKey.make(artist: "Artist", title: "A")
        let b = SongKey.make(artist: "Artist", title: "B")
        let c = SongKey.make(artist: "Artist", title: "C")
        try await store.insertImported([
            HistoryFixtures.listen("A", at: at(1)),
            HistoryFixtures.listen("B", at: at(2)),
        ])
        try await store.insert(contentsOf: [
            HistoryFixtures.listen("A", at: at(9)),
            HistoryFixtures.listen("A", at: at(5)),
            HistoryFixtures.listen("A", at: at(7)),
        ])
        #expect(try await store.firstHeard(songKeys: [a, b, c]) == [a: at(1), b: at(2)])
        #expect(try await store.firstHeard(songKeys: [a, b, c], origin: .tracked) == [a: at(5)])
        #expect(try await store.firstHeard(songKeys: [a, b], origin: .imported) == [a: at(1), b: at(2)])
        #expect(try await store.firstHeard(songKeys: []).isEmpty)
    }

    // MARK: The import's duplicate check

    /// The duplicate check finds the same listens, and claims the same ones,
    /// as a plain reading of its rules that compares every pair.
    @Test(arguments: 0 ..< 6)
    func theDuplicateCheckMatchesItsRules(seed: UInt64) {
        var random = SeededRandom(seed: seed)
        for _ in 0 ..< 40 {
            let existing = Self.listens(count: Int.random(in: 0 ... 30, using: &random), using: &random)
            let files = (0 ..< Int.random(in: 1 ... 4, using: &random)).map { _ in
                Self.listens(count: Int.random(in: 0 ... 30, using: &random), using: &random)
            }
            let fast = HistoryImport.newListens(files, existing: existing)
            let plain = ReferenceDuplicateCheck.newListens(files, existing: existing)
            #expect(fast.duplicates == plain.duplicates)
            #expect(fast.new.map(\.id).sorted() == plain.new.map(\.id).sorted())
        }
    }

    /// Few names and times on a coarse grid, so listens overlap, artists
    /// relate, and ties in distance happen.
    static func listens(count: Int, using random: inout SeededRandom) -> [Listen] {
        let titles = ["Harbor", "harbor", "Harbor (Live)", "Signal", "Low Tide"]
        let artists = ["Northe", "Northe feat. Vale", "Vale", "", "The Coast"]
        let tracks = ["", "", "t1", "t2", "t3"]
        let start = HistoryFixtures.date(2025, 11, 1, 12)
        return (0 ..< count).map { _ in
            let title = titles.randomElement(using: &random)!
            let artist = artists.randomElement(using: &random)!
            let started = start.addingTimeInterval(Double(Int.random(in: 0 ..< 120, using: &random)) * 60)
            let listened = Double(Int.random(in: 1 ... 8, using: &random)) * 30
            return Listen(
                id: Int64.random(in: 1 ... Int64.max, using: &random),
                trackID: TrackID(tracks.randomElement(using: &random)!),
                // Sometimes a key the title and artist wouldn't make.
                songKey: Bool.random(using: &random) ? nil : ["k1", "k2"].randomElement(using: &random)!,
                title: title,
                artist: artist,
                source: .spotifyApp,
                startedAt: started,
                endedAt: started.addingTimeInterval(listened),
                listened: listened,
                duration: 240,
                ending: .completed,
                counts: true
            )
        }
    }
}

/// The duplicate check as first written: every kept listen is a candidate,
/// the closest end wins, and the earliest-listed candidate wins a tie.
private enum ReferenceDuplicateCheck {
    static func newListens(_ files: [[Listen]], existing: [Listen]) -> (new: [Listen], duplicates: Int) {
        var kept: [(listen: Listen, file: Int, claimed: Bool)] = existing.map { ($0, -1, false) }
        var new: [Listen] = []
        var duplicates = 0
        for (file, listens) in files.enumerated() {
            for listen in listens {
                let title = SongKey.normalize(listen.title)
                let artist = SongKey.normalize(listen.artist)
                let indices = Array(kept.indices)
                // In the order the first version listed them: same song, same
                // track, then the same title with a related artist.
                let candidates = indices.filter { kept[$0].listen.songKey == listen.songKey }
                    + (listen.trackID.rawValue.isEmpty ? [] : indices.filter { kept[$0].listen.trackID == listen.trackID })
                    + indices.filter { index in
                        guard SongKey.normalize(kept[index].listen.title) == title else { return false }
                        let other = SongKey.normalize(kept[index].listen.artist)
                        return other.contains(artist) || artist.contains(other)
                    }
                let best = candidates
                    .filter { !kept[$0].claimed && kept[$0].file != file && overlaps(kept[$0].listen, listen) }
                    .min { distance(kept[$0].listen, listen) < distance(kept[$1].listen, listen) }
                if let best {
                    kept[best].claimed = true
                    duplicates += 1
                } else {
                    new.append(listen)
                    kept.append((listen, file, false))
                }
            }
        }
        return (new, duplicates)
    }

    static func distance(_ a: Listen, _ b: Listen) -> TimeInterval {
        abs(a.endedAt.timeIntervalSince(b.endedAt))
    }

    static func overlaps(_ stored: Listen, _ listen: Listen) -> Bool {
        stored.startedAt.addingTimeInterval(-HistoryImport.matchTolerance) <= listen.endedAt
            && listen.startedAt <= stored.endedAt.addingTimeInterval(HistoryImport.matchTolerance)
    }
}

/// SplitMix64, so every run tries the same listens.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
