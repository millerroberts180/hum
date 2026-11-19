import Foundation
@testable import HumCore
import Testing

/// Small stand-ins for the two shapes of Spotify's data download.
enum ImportFixtures {
    /// Account data: three songs, one too short to keep.
    static let accountData = """
        [
          { "endTime" : "2025-10-01 08:04", "artistName" : "Ana", "trackName" : "Café Nights", "msPlayed" : 200000 },
          { "endTime" : "2025-10-01 08:05", "artistName" : "Ana", "trackName" : "Café Nights", "msPlayed" : 15000 },
          { "endTime" : "2025-10-01 09:30", "artistName" : "The Examples", "trackName" : "Night Drive", "msPlayed" : 90000 },
          { "endTime" : "2025-10-01 10:00", "artistName" : "Ana", "trackName" : "Short", "msPlayed" : 1000 }
        ]
        """

    /// Extended streaming history: a full play, a skip, a partial play, a
    /// podcast episode, and a private-session play.
    static let extended = """
        [
          {
            "ts": "2025-10-02T20:00:00Z", "platform": "macOS", "ms_played": 180000, "conn_country": "US",
            "master_metadata_track_name": "Night Drive", "master_metadata_album_artist_name": "The Examples",
            "master_metadata_album_album_name": "Roads", "spotify_track_uri": "spotify:track:night",
            "episode_name": null, "episode_show_name": null, "spotify_episode_uri": null,
            "reason_start": "clickrow", "reason_end": "trackdone", "shuffle": false, "skipped": false,
            "offline": false, "offline_timestamp": null, "incognito_mode": false
          },
          {
            "ts": "2025-10-02T20:00:12Z", "ms_played": 12000,
            "master_metadata_track_name": "Roadside", "master_metadata_album_artist_name": "The Examples",
            "master_metadata_album_album_name": "Roads", "spotify_track_uri": "spotify:track:roadside",
            "reason_start": "trackdone", "reason_end": "fwdbtn", "skipped": true, "incognito_mode": false
          },
          {
            "ts": "2025-10-03T07:30:00Z", "ms_played": 100000,
            "master_metadata_track_name": "Night Drive", "master_metadata_album_artist_name": "The Examples",
            "master_metadata_album_album_name": "Roads", "spotify_track_uri": "spotify:track:night",
            "reason_start": "clickrow", "reason_end": "endplay", "skipped": null, "incognito_mode": false
          },
          {
            "ts": "2025-10-03T09:00:00Z", "ms_played": 1800000,
            "master_metadata_track_name": null, "master_metadata_album_artist_name": null,
            "master_metadata_album_album_name": null, "spotify_track_uri": null,
            "episode_name": "Episode 12", "episode_show_name": "A Show", "spotify_episode_uri": "spotify:episode:12",
            "reason_start": "clickrow", "reason_end": "endplay", "skipped": null, "incognito_mode": false
          },
          {
            "ts": "2025-10-03T23:00:00Z", "ms_played": 200000,
            "master_metadata_track_name": "Secret", "master_metadata_album_artist_name": "Ana",
            "master_metadata_album_album_name": "Quiet", "spotify_track_uri": "spotify:track:secret",
            "reason_start": "clickrow", "reason_end": "trackdone", "skipped": false, "incognito_mode": true
          }
        ]
        """

    static func data(_ text: String) -> Data { Data(text.utf8) }

    /// An extended-history entry for one play of "Night Drive".
    static func nightDrive(endingAt end: String, playedMs: Int = 180_000, reason: String = "trackdone") -> String {
        """
        { "ts": "\(end)", "ms_played": \(playedMs), "master_metadata_track_name": "Night Drive",
          "master_metadata_album_artist_name": "The Examples", "master_metadata_album_album_name": "Roads",
          "spotify_track_uri": "spotify:track:night", "reason_end": "\(reason)", "skipped": false, "incognito_mode": false }
        """
    }

    static func extended(_ entries: [String]) -> Data {
        data("[" + entries.joined(separator: ",") + "]")
    }

    static func utc(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }
}

@Suite("History import")
struct HistoryImportTests {
    typealias F = ImportFixtures

    func batch(_ texts: String...) throws -> HistoryImport.Batch {
        try #require(HistoryImport.batch(texts.map(F.data)))
    }

    func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hum-import-tests-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Account data

    @Test func accountDataBecomesImportedListens() throws {
        let result = try batch(F.accountData)
        let listens = result.listens
        #expect(listens.count == 3)
        #expect(result.skipped == 1)
        #expect(result.files.count == 1)

        let first = try #require(listens.first)
        #expect(first.title == "Café Nights")
        #expect(first.artist == "Ana")
        #expect(first.album == "")
        #expect(first.trackID.rawValue == "")
        #expect(first.source == .spotifyApp)
        #expect(first.origin == .imported)
        #expect(first.context == nil)
        #expect(first.duration == nil)
        // The time is when the stream ended, in UTC, so it started before.
        #expect(first.endedAt == F.utc("2025-10-01T08:04:00Z"))
        #expect(first.startedAt == F.utc("2025-10-01T08:00:40Z"))
        #expect(first.listened == 200)
        #expect(listens.allSatisfy { $0.origin == .imported })
    }

    @Test func accountDataPlaysAreJudgedByTheLongestListen() throws {
        let listens = try batch(F.accountData).listens
        let full = try #require(listens.first { $0.title == "Café Nights" && $0.listened == 200 })
        let short = try #require(listens.first { $0.title == "Café Nights" && $0.listened == 15 })
        #expect(full.counts)
        #expect(full.ending == .completed)
        #expect(!short.counts)
        // Night Drive's only listen is its longest, so it reads as heard through.
        let drive = try #require(listens.first { $0.title == "Night Drive" })
        #expect(drive.counts)
    }

    // MARK: Extended history

    @Test func extendedHistoryKeepsOnlyMusicFromOrdinarySessions() throws {
        let result = try batch(F.extended)
        #expect(result.listens.map(\.title) == ["Night Drive", "Roadside", "Night Drive"])
        // The episode and the private-session play.
        #expect(result.skipped == 2)
    }

    @Test func extendedHistoryCarriesTheTrackAndHowItEnded() throws {
        let listens = try batch(F.extended).listens
        let full = listens[0], skip = listens[1], partial = listens[2]
        #expect(full.trackID == TrackID("spotify:track:night"))
        #expect(full.album == "Roads")
        #expect(full.endedAt == F.utc("2025-10-02T20:00:00Z"))
        #expect(full.startedAt == F.utc("2025-10-02T19:57:00Z"))
        #expect(full.ending == .completed)
        #expect(full.counts)

        #expect(skip.ending == .skipped)
        #expect(!skip.counts)

        // 100 of the 180 seconds the full play showed the song to be.
        #expect(partial.ending == .partial)
        #expect(partial.counts)
    }

    @Test func aSkipIsNeverAPlayEvenWhenLong() throws {
        let entry = """
            [{ "ts": "2025-10-02T20:00:00Z", "ms_played": 250000, "master_metadata_track_name": "Long",
               "master_metadata_album_artist_name": "Ana", "reason_end": "fwdbtn", "skipped": true }]
            """
        let listen = try #require(try batch(entry).listens.first)
        #expect(listen.ending == .skipped)
        #expect(!listen.counts)
    }

    // MARK: What isn't history

    @Test func otherJSONIsNotHistory() {
        #expect(HistoryImport.batch([F.data(#"{ "userName": "someone" }"#)]) == nil)
        #expect(HistoryImport.batch([F.data(#"[{ "searchQuery": "night drive" }]"#)]) == nil)
        #expect(HistoryImport.batch([F.data("not json")]) == nil)
    }

    @Test func anEmptyHistoryFileIsStillHistory() throws {
        let result = try batch("[]")
        #expect(result.listens.isEmpty)
        #expect(result.files.count == 1)
    }

    @Test func historyFilesAreRecognizedByName() {
        #expect(HistoryImport.isHistoryFileName("StreamingHistory_music_0.json"))
        #expect(HistoryImport.isHistoryFileName("StreamingHistory0.json"))
        #expect(HistoryImport.isHistoryFileName("Streaming_History_Audio_2021-2023_3.json"))
        #expect(HistoryImport.isHistoryFileName("endsong_2.json"))
        #expect(!HistoryImport.isHistoryFileName("StreamingHistory_podcast_0.json"))
        #expect(!HistoryImport.isHistoryFileName("Streaming_History_Video_2024.json"))
        #expect(!HistoryImport.isHistoryFileName("Userdata.json"))
        #expect(!HistoryImport.isHistoryFileName("StreamingHistory_music_0.pdf"))
    }

    @Test func accountDataTimesAreUTCAndChecked() {
        #expect(HistoryImport.accountDate("2025-10-01 08:04") == F.utc("2025-10-01T08:04:00Z"))
        #expect(HistoryImport.accountDate("2025-13-01 08:04") == nil)
        #expect(HistoryImport.accountDate("yesterday") == nil)
    }

    // MARK: Reading files

    @Test func aFolderIsSearchedForHistoryFiles() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let account = folder.appendingPathComponent("Spotify Account Data", isDirectory: true)
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        try F.data(F.accountData).write(to: account.appendingPathComponent("StreamingHistory_music_0.json"))
        try F.data(#"[{ "endTime": "2025-10-01 08:00", "podcastName": "A Show", "episodeName": "One", "msPlayed": 60000 }]"#)
            .write(to: account.appendingPathComponent("StreamingHistory_podcast_0.json"))
        try F.data(#"{ "username": "someone" }"#).write(to: account.appendingPathComponent("Userdata.json"))
        try F.data(F.extended).write(to: folder.appendingPathComponent("Streaming_History_Audio_2025_0.json"))

        let result = try await HistoryImport.read([folder])
        #expect(result.files.count == 2)
        // Extended history is read first.
        #expect(result.files[0].first?.trackID == TrackID("spotify:track:night"))
        #expect(result.listens.count == 6)
    }

    @Test func aChosenFileThatIsntHistoryIsAnError() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Playlist1.json")
        try F.data(#"{ "playlists": [] }"#).write(to: file)
        await #expect(throws: HistoryImport.Failure.unreadable(fileName: "Playlist1.json")) {
            try await HistoryImport.read([file])
        }
    }

    @Test func aFolderWithoutHistoryIsAnError() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try F.data(#"{ "username": "someone" }"#).write(to: folder.appendingPathComponent("Userdata.json"))
        await #expect(throws: HistoryImport.Failure.noHistory) {
            try await HistoryImport.read([folder])
        }
    }

    // MARK: Duplicates

    func tracked(_ title: String = "Night Drive", artist: String = "The Examples", start: String, listened: TimeInterval = 180, wallClock: TimeInterval? = nil) -> Listen {
        let started = F.utc(start)
        return Listen(
            trackID: TrackID("spotify:track:night"),
            title: title,
            artist: artist,
            album: "Roads",
            source: .spotifyApp,
            startedAt: started,
            endedAt: started.addingTimeInterval(wallClock ?? listened),
            listened: listened,
            duration: 180,
            ending: .completed,
            counts: true
        )
    }

    @Test func aListenHumTrackedIsNotImportedAgain() async throws {
        let store = try HistoryStore(url: nil)
        // Tracked with a 20-second pause, so its span is longer than what was heard.
        try await store.insert(tracked(start: "2025-10-02T19:56:45Z", wallClock: 200))
        let summary = try await store.importListens(try batch(F.extended))
        #expect(summary.duplicates == 1)
        #expect(summary.added == 2)
        #expect(summary.skipped == 2)
        #expect(try await store.count() == 3)
    }

    @Test func artistsNamedDifferentlyStillMatch() async throws {
        let store = try HistoryStore(url: nil)
        var listen = tracked(artist: "The Examples, Guest", start: "2025-10-02T19:57:00Z")
        listen.trackID = TrackID("music:123")
        try await store.insert(listen)
        let summary = try await store.importListens(try batch(F.extended))
        #expect(summary.duplicates == 1)
    }

    @Test func listensFarApartAreBothKept() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(tracked(start: "2025-10-02T18:00:00Z"))
        let summary = try await store.importListens(try batch(F.extended))
        #expect(summary.duplicates == 0)
        #expect(summary.added == 3)
    }

    @Test func playsBackToBackInOneFileAreBothKept() async throws {
        let store = try HistoryStore(url: nil)
        let file = F.extended([F.nightDrive(endingAt: "2025-10-02T20:00:00Z"), F.nightDrive(endingAt: "2025-10-02T20:03:00Z")])
        let summary = try await store.importListens(try #require(HistoryImport.batch([file])))
        #expect(summary.added == 2)
        #expect(summary.duplicates == 0)
    }

    @Test func eachTrackedListenAccountsForOneImportedListen() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(tracked(start: "2025-10-02T19:57:00Z"))
        let file = F.extended([F.nightDrive(endingAt: "2025-10-02T20:00:00Z"), F.nightDrive(endingAt: "2025-10-02T20:03:00Z")])
        let summary = try await store.importListens(try #require(HistoryImport.batch([file])))
        #expect(summary.added == 1)
        #expect(summary.duplicates == 1)
        let imported = try await store.listens().filter { $0.origin == .imported }
        #expect(imported.map(\.endedAt) == [F.utc("2025-10-02T20:03:00Z")])
    }

    @Test func importingTheSameFilesTwiceAddsNothing() async throws {
        let store = try HistoryStore(url: nil)
        let first = try await store.importListens(try batch(F.accountData, F.extended))
        let second = try await store.importListens(try batch(F.accountData, F.extended))
        #expect(second.added == 0)
        #expect(second.duplicates == first.added)
        #expect(try await store.count() == first.added)
        #expect(second.message == "Nothing new to import. \(first.added) were already in your history.")
    }

    @Test func accountDataOverlappingExtendedHistoryIsKeptOnce() async throws {
        let store = try HistoryStore(url: nil)
        let account = """
            [{ "endTime" : "2025-10-02 20:00", "artistName" : "The Examples", "trackName" : "Night Drive", "msPlayed" : 180000 }]
            """
        let summary = try await store.importListens(try batch(F.extended, account))
        #expect(summary.duplicates == 1)
        #expect(summary.added == 3)
        // The richer extended entry is the one kept.
        let kept = try await store.listens().first { $0.title == "Night Drive" }
        #expect(kept?.trackID == TrackID("spotify:track:night"))
    }

    // MARK: The store

    @Test func importingLeavesWhenTrackingStartedAlone() async throws {
        let store = try HistoryStore(url: nil)
        _ = try await store.importListens(try batch(F.extended))
        #expect(try await store.trackedSince() == nil)

        let since = F.utc("2025-11-01T12:00:00Z")
        try await store.insert(tracked(start: "2025-11-01T12:00:00Z"))
        _ = try await store.importListens(try batch(F.accountData))
        #expect(try await store.trackedSince() == since)
    }

    @Test func importedHistoryIsSummarized() async throws {
        let store = try HistoryStore(url: nil)
        #expect(try await store.importedHistory() == nil)
        _ = try await store.importListens(try batch(F.extended))
        let imported = try #require(try await store.importedHistory())
        #expect(imported.count == 3)
        #expect(imported.since == F.utc("2025-10-02T19:57:00Z"))
        #expect(imported.until == F.utc("2025-10-03T07:30:00Z"))
    }

    @Test func removingImportedHistoryKeepsWhatHumTracked() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(tracked(start: "2025-11-01T12:00:00Z"))
        _ = try await store.importListens(try batch(F.extended))
        #expect(try await store.removeImported() == 3)
        let left = try await store.listens()
        #expect(left.count == 1)
        #expect(left.first?.origin == .tracked)
        #expect(try await store.importedHistory() == nil)
    }

    @Test func provenanceSeparatesTrackedFromImported() async throws {
        let store = try HistoryStore(url: nil)
        var music = tracked(start: "2025-11-01T12:00:00Z")
        music.source = .musicApp
        try await store.insert(music)
        _ = try await store.importListens(try batch(F.extended))

        let all = try await store.provenance()
        #expect(all.tracked == [.musicApp])
        #expect(all.imported == [.spotifyApp])
        #expect(HistoryFormat.source(all) == "tracked by Hum from Music, plus imported from Spotify")

        let october = try await store.provenance(from: F.utc("2025-10-01T00:00:00Z"), to: F.utc("2025-10-31T00:00:00Z"))
        #expect(HistoryFormat.source(october) == "imported from Spotify")

        let november = try await store.provenance(from: F.utc("2025-11-01T00:00:00Z"))
        #expect(HistoryFormat.source(november) == "tracked by Hum from Music")
        #expect(HistoryFormat.source(HistoryProvenance()) == "tracked by Hum on this Mac")
    }

    // MARK: Messages

    @Test func summariesSayWhatHappened() {
        #expect(HistoryImport.Summary(added: 1204, duplicates: 38, skipped: 3, files: 2).message
            == "Imported 1,204 listens. 38 were already in your history.")
        #expect(HistoryImport.Summary(added: 1, duplicates: 1, skipped: 0, files: 1).message
            == "Imported 1 listen. 1 was already in your history.")
        #expect(HistoryImport.Summary(added: 0, duplicates: 0, skipped: 0, files: 1).message == "Nothing new to import.")
    }
}

@Suite("Imported history in Echo")
struct ImportedInsightTests {
    let calendar = HistoryFixtures.calendar
    let now = HistoryFixtures.now
    let track = Track(id: TrackID("t:Song"), title: "Song", artist: "Artist", album: "Album", duration: 200)

    func play(_ daysAgo: Double, origin: ListenOrigin = .tracked) -> Listen {
        var listen = HistoryFixtures.listen("Song", at: HistoryFixtures.daysAgo(daysAgo), source: .spotifyApp)
        listen.origin = origin
        return listen
    }

    func insights(_ listens: [Listen], trackedSince: Date?, imported: ClosedRange<Date>?) -> [Insight] {
        InsightEngine.songInsights(
            .init(track: track, listens: listens, monthPlayCounts: [:], trackedSince: trackedSince, importedRange: imported, now: now),
            calendar: calendar
        )
    }

    @Test func numbersSayTheyWereImported() throws {
        let listens = [play(300, origin: .imported), play(200, origin: .imported)]
        let result = insights(listens, trackedSince: nil, imported: HistoryFixtures.daysAgo(400) ... HistoryFixtures.daysAgo(100))
        let together = try #require(result.first { $0.kind == .togetherTime })
        #expect(together.explanation.hasSuffix(", imported."))
        #expect(!together.explanation.contains("tracked by Hum"))
    }

    @Test func mixedNumbersSayBoth() throws {
        let listens = [play(300, origin: .imported), play(20)]
        let result = insights(listens, trackedSince: HistoryFixtures.daysAgo(30), imported: HistoryFixtures.daysAgo(400) ... HistoryFixtures.daysAgo(100))
        let together = try #require(result.first { $0.kind == .togetherTime })
        #expect(together.explanation.hasSuffix(", tracked by Hum and imported."))
        // History reaches back to the import, not just to when tracking began.
        #expect(together.explanation.hasPrefix("Counted from Sep 30, 2024 to today"))
    }

    /// Echo and the widgets show these, so even history imported from Spotify
    /// never names it (DESIGN.md §10).
    @Test func importedNumbersNeverNameTheApp() {
        let listens = (0..<40).map { play(Double(300 - $0 * 7), origin: .imported) } + [play(3), play(1)]
        let result = insights(listens, trackedSince: HistoryFixtures.daysAgo(30), imported: HistoryFixtures.daysAgo(400) ... HistoryFixtures.daysAgo(10))
        #expect(result.contains { $0.explanation.contains("imported") })
        for insight in result {
            for text in [insight.title, insight.value, insight.label, insight.sentence, insight.explanation].compactMap(\.self) + insight.details {
                #expect(!text.contains("Spotify"), "\(insight.kind): \(text)")
            }
        }
    }

    @Test func aFirstPlayAtTheStartOfTheImportSaysSo() throws {
        let start = HistoryFixtures.daysAgo(400)
        let result = insights([play(399.5, origin: .imported), play(10)], trackedSince: HistoryFixtures.daysAgo(30), imported: start ... HistoryFixtures.daysAgo(100))
        let first = try #require(result.first { $0.kind == .firstAndLast })
        #expect(first.sentence == "With you since your imported history begins")
        #expect(first.explanation == "Imported history begins on Sep 30, 2024, so the first listen may be earlier.")
    }

    @Test func aNewSongNamesBothRanges() throws {
        let only = try #require(
            insights([], trackedSince: HistoryFixtures.daysAgo(30), imported: HistoryFixtures.daysAgo(400) ... HistoryFixtures.daysAgo(100)).first
        )
        #expect(only.kind == .firstTime)
        #expect(only.explanation == "Tracked by Hum since Oct 5, with imported history back to Sep 30, 2024.")
        let importOnly = try #require(insights([], trackedSince: nil, imported: HistoryFixtures.daysAgo(400) ... HistoryFixtures.daysAgo(100)).first)
        #expect(importOnly.explanation == "Imported history back to Sep 30, 2024.")
    }

    @Test func withoutAnImportNothingChanges() throws {
        let only = try #require(insights([], trackedSince: nil, imported: nil).first)
        #expect(only.explanation == "Tracked by Hum since Nov 4.")
    }

    @Test func sessionsAreOnlyWhatHumSaw() async throws {
        let store = try HistoryStore(url: nil)
        // Imported listening from an hour ago, maybe on a phone.
        var phone = HistoryFixtures.listen("Song", at: now.addingTimeInterval(-3_600), source: .spotifyApp)
        phone.origin = .imported
        try await store.insertImported([phone])
        let echo = try await store.echo(track: nil, inProgress: nil, now: now, calendar: calendar)
        #expect(echo.session == nil)
        #expect(echo.imported?.count == 1)
    }
}
