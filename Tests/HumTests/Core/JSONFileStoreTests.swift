import Foundation
@testable import HumCore
import Testing

@Suite("JSON file store")
struct JSONFileStoreTests {
    struct Document: Codable, Equatable {
        var name: String
        var count: Int
    }

    /// A new, empty folder of its own for each test.
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hum-json-store-tests-" + UUID().uuidString, isDirectory: true)

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func whatIsSavedLoadsBack() throws {
        defer { remove() }
        let url = folder.appendingPathComponent("Settings.json")
        let saved = Document(name: "Hum", count: 3)
        try JSONFileStore.save(saved, to: url)
        #expect(try JSONFileStore.load(Document.self, from: url) == saved)
    }

    @Test func aMissingFileLoadsAsNothing() throws {
        defer { remove() }
        let url = folder.appendingPathComponent("Missing.json")
        #expect(try JSONFileStore.load(Document.self, from: url) == nil)
    }

    @Test func aCorruptFileThrows() throws {
        defer { remove() }
        let url = folder.appendingPathComponent("Corrupt.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        #expect(throws: (any Error).self) {
            try JSONFileStore.load(Document.self, from: url)
        }
    }

    @Test func aFileOfTheWrongShapeThrows() throws {
        defer { remove() }
        let url = folder.appendingPathComponent("Other.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"title": "Hum"}"#.utf8).write(to: url)
        #expect(throws: DecodingError.self) {
            try JSONFileStore.load(Document.self, from: url)
        }
    }

    @Test func savingCreatesTheFoldersItNeeds() throws {
        defer { remove() }
        let url = folder
            .appendingPathComponent("One", isDirectory: true)
            .appendingPathComponent("Two", isDirectory: true)
            .appendingPathComponent("Deep.json")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        try JSONFileStore.save(Document(name: "Deep", count: 1), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func savingReplacesTheWholeFile() throws {
        defer { remove() }
        let url = folder.appendingPathComponent("Settings.json")
        try JSONFileStore.save(Document(name: "A much longer name than the next one", count: 1), to: url)
        try JSONFileStore.save(Document(name: "Short", count: 2), to: url)
        #expect(try JSONFileStore.load(Document.self, from: url) == Document(name: "Short", count: 2))
        // Nothing of the longer first save is left at the end of the file.
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("longer"))
    }

    @Test func savingSwapsInANewFileRatherThanWritingOverTheOld() throws {
        defer { remove() }
        let url = folder.appendingPathComponent("Settings.json")
        let link = folder.appendingPathComponent("Earlier.json")
        try JSONFileStore.save(Document(name: "First", count: 1), to: url)
        // A second name for the first file. Written in place, it would change
        // too; replaced atomically, it keeps the first save whole.
        try FileManager.default.linkItem(at: url, to: link)

        try JSONFileStore.save(Document(name: "Second", count: 2), to: url)

        #expect(try JSONFileStore.load(Document.self, from: url) == Document(name: "Second", count: 2))
        #expect(try JSONFileStore.load(Document.self, from: link) == Document(name: "First", count: 1))
    }

    @Test func savingLeavesNoTemporaryFilesBehind() throws {
        defer { remove() }
        let url = folder.appendingPathComponent("Settings.json")
        try JSONFileStore.save(Document(name: "A", count: 1), to: url)
        try JSONFileStore.save(Document(name: "B", count: 2), to: url)
        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(contents == ["Settings.json"])
    }

    @Test func savedJSONIsSortedAndReadable() throws {
        defer { remove() }
        let url = folder.appendingPathComponent("Settings.json")
        try JSONFileStore.save(Document(name: "Hum", count: 3), to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        let count = try #require(text.range(of: "\"count\""))
        let name = try #require(text.range(of: "\"name\""))
        #expect(count.lowerBound < name.lowerBound)
        #expect(text.contains("\n"))
    }

    @Test func quarantineMovesTheFileAsideWithADatedName() throws {
        defer { remove() }
        let url = folder.appendingPathComponent("Settings.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let now = Date(timeIntervalSince1970: 1_762_300_800)

        let moved = try #require(JSONFileStore.quarantine(url, now: now))

        #expect(moved.lastPathComponent == "Settings.corrupt-1762300800.json")
        #expect(moved.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: moved) == Data("{ not json".utf8))
        // With the bad file aside, the store starts over from nothing.
        #expect(try JSONFileStore.load(Document.self, from: url) == nil)
    }

    @Test func quarantiningAMissingFileReturnsNothing() {
        defer { remove() }
        let url = folder.appendingPathComponent("Missing.json")
        #expect(JSONFileStore.quarantine(url) == nil)
    }
}
