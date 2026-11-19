import AppKit
import HumCore
import UniformTypeIdentifiers

/// Asks for Spotify's data download, then imports it. Hum reads only the
/// files; it never asks Spotify for history.
enum HistoryImporter {
    /// Show an open panel for history files or the download's folder, as a
    /// sheet on `window` (or else the key window). Returns what was chosen, or
    /// `nil` if cancelled.
    static func choose(on window: NSWindow? = nil) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "Import Spotify Listening History"
        panel.message = "Choose the JSON files or the folder from your Spotify data download."
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json, .folder]

        let response: NSApplication.ModalResponse
        if let window = window ?? NSApp.keyWindow {
            NSApp.activate()
            response = await panel.beginSheetModal(for: window)
        } else {
            NSApp.activate()
            response = panel.runModal()
        }
        guard response == .OK, !panel.urls.isEmpty else { return nil }
        return panel.urls
    }

    /// Import `urls` and say how it went.
    static func read(_ urls: [URL], into history: ListeningHistory) async -> String {
        do {
            return try await history.importHistory(from: urls).message
        } catch let failure as HistoryImport.Failure {
            return failure.description
        } catch {
            return "Couldn’t import: \(error.localizedDescription)"
        }
    }

    /// What removing imported history does, for its confirmation.
    nonisolated static func removalMessage(_ imported: ImportedHistory?) -> String {
        let what = imported.map { "the " + HistoryFormat.count($0.count, "imported listen") } ?? "every imported listen"
        return "This removes \(what). What Hum tracked on this Mac stays, and you can import the files again."
    }
}
