import Foundation
@testable import HumCore
@testable import HumUI
import Testing

@MainActor
@Suite("Exporting and importing from Echo")
struct HistoryFileActionsTests {
    let clock = TestClock(HistoryFixtures.now)
    let nowPlaying: NowPlayingStore
    let settings = SettingsStore(fileURL: nil)

    init() {
        let clock = clock
        let source = FakeSource(state: Fixtures.state(track: nil, status: .stopped, position: 0, at: clock.now))
        nowPlaying = NowPlayingStore(sources: [source], preferredSourceID: nil, now: { clock.now })
        nowPlaying.start()
    }

    func makeHistory(_ store: HistoryStore) -> ListeningHistory {
        let clock = clock
        let history = ListeningHistory(
            store: store,
            nowPlaying: nowPlaying,
            settings: settings,
            artworkCache: ArtworkCache(directory: nil),
            calendar: HistoryFixtures.calendar,
            now: { clock.now }
        )
        history.start()
        return history
    }

    func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hum-echo-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Export

    @Test func exportsAreNamedForTheDayInTheUsersTimeZone() throws {
        let lateEvening = ImportFixtures.utc("2025-11-05T02:30:00Z")
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        #expect(HistoryExporter.fileName(for: .json, on: lateEvening, timeZone: newYork) == "Hum Listening History 2025-11-04.json")
        #expect(HistoryExporter.fileName(for: .csv, on: lateEvening, timeZone: .gmt) == "Hum Listening History 2025-11-05.csv")
        #expect(HistoryExporter.contentType(for: .json) == .json)
        #expect(HistoryExporter.contentType(for: .csv) == .commaSeparatedText)
    }

    @Test func writingAnExportSaysHowManyListens() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(HistoryFixtures.listen("One", at: HistoryFixtures.daysAgo(2)))
        try await store.insert(HistoryFixtures.listen("Two", at: HistoryFixtures.daysAgo(1)))
        let history = makeHistory(store)
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("history.json")
        #expect(await HistoryExporter.write(.json, history: history, to: url) == "Exported 2 listens.")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aFailedExportSaysItCouldnt() async throws {
        let history = makeHistory(try HistoryStore(url: nil))
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("missing", isDirectory: true).appendingPathComponent("history.csv")
        let message = await HistoryExporter.write(.csv, history: history, to: url)
        #expect(message.hasPrefix("Couldn’t export: "))
    }

    // MARK: Import

    @Test func importingShowsTheSummaryAndUpdatesEcho() async throws {
        let history = makeHistory(try HistoryStore(url: nil))
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Streaming_History_Audio_2025.json")
        try ImportFixtures.data(ImportFixtures.extended).write(to: file)

        let revision = history.revision
        #expect(await HistoryImporter.read([file], into: history) == "Imported 3 listens.")
        await history.settle()
        #expect(history.revision > revision)
        #expect(history.echo.imported?.count == 3)
        #expect(history.echo.trackedSince == nil)

        #expect(await HistoryImporter.read([file], into: history) == "Nothing new to import. 3 were already in your history.")
    }

    @Test func importingSomethingElseSaysWhatToChoose() async throws {
        let history = makeHistory(try HistoryStore(url: nil))
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(await HistoryImporter.read([folder], into: history) == HistoryImport.Failure.noHistory.description)
        let other = folder.appendingPathComponent("YourLibrary.json")
        try ImportFixtures.data(#"{ "tracks": [] }"#).write(to: other)
        #expect(await HistoryImporter.read([other], into: history) == "YourLibrary.json couldn’t be read.")
    }

    @Test func removingImportedHistoryLeavesTrackedListens() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(HistoryFixtures.listen("Mine", at: HistoryFixtures.daysAgo(1)))
        let history = makeHistory(store)
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("StreamingHistory_music_0.json")
        try ImportFixtures.data(ImportFixtures.accountData).write(to: file)
        _ = try await history.importHistory(from: [file])
        await history.settle()
        #expect(history.echo.imported != nil)

        history.removeImported()
        await history.settle()
        #expect(history.echo.imported == nil)
        #expect(history.echo.listenCount == 1)
    }

    @Test func theRemovalConfirmationCountsWhatGoes() {
        let imported = ImportedHistory(count: 1_204, since: HistoryFixtures.daysAgo(400), until: HistoryFixtures.daysAgo(30))
        #expect(HistoryImporter.removalMessage(imported)
            == "This removes the 1,204 imported listens. What Hum tracked on this Mac stays, and you can import the files again.")
        #expect(HistoryImporter.removalMessage(nil)
            == "This removes every imported listen. What Hum tracked on this Mac stays, and you can import the files again.")
    }

    // MARK: Settings

    @Test func theSettingsSummaryCountsTrackedAndImportedApart() {
        let format = HistoryFormat(calendar: HistoryFixtures.calendar)
        let now = HistoryFixtures.now
        #expect(EchoSettingsSection.summary(.empty, format: format, now: now) == "Nothing saved yet.")

        let tracked = EchoSnapshot(trackedSince: HistoryFixtures.daysAgo(30), listenCount: 120)
        #expect(EchoSettingsSection.summary(tracked, format: format, now: now) == "120 listens saved since Oct 5.")

        let imported = ImportedHistory(count: 3_310, since: ImportFixtures.utc("2021-03-02T10:00:00Z"), until: ImportFixtures.utc("2025-10-30T10:00:00Z"))
        let both = EchoSnapshot(trackedSince: HistoryFixtures.daysAgo(30), listenCount: 3_430, imported: imported)
        #expect(EchoSettingsSection.summary(both, format: format, now: now)
            == "120 listens saved since Oct 5. 3,310 imported listens from Mar 2, 2021 to Oct 30.")

        let onlyImported = EchoSnapshot(listenCount: 3_310, imported: imported)
        #expect(EchoSettingsSection.summary(onlyImported, format: format, now: now)
            == "3,310 imported listens from Mar 2, 2021 to Oct 30.")
    }

}
