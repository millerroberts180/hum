import AppKit
import HumCore
import UniformTypeIdentifiers

/// Asks where to save an export, then writes it.
enum HistoryExporter {
    /// Show a save panel, as a sheet on `window` (or else the key window), and
    /// export. Returns a short result for the caller to show, or `nil` if
    /// cancelled.
    static func export(_ format: HistoryExportFormat, history: ListeningHistory, on window: NSWindow? = nil) async -> String? {
        let panel = NSSavePanel()
        panel.title = "Export Listening History"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [contentType(for: format)]
        panel.nameFieldStringValue = fileName(for: format, on: .now)

        let response: NSApplication.ModalResponse
        if let window = window ?? NSApp.keyWindow {
            NSApp.activate()
            response = await panel.beginSheetModal(for: window)
        } else {
            NSApp.activate()
            response = panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return nil }
        return await write(format, history: history, to: url)
    }

    /// "Hum Listening History 2025-11-04.json", dated in the user's time zone.
    nonisolated static func fileName(for format: HistoryExportFormat, on date: Date, timeZone: TimeZone = .current) -> String {
        let stamp = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        return "Hum Listening History \(stamp).\(format.fileExtension)"
    }

    nonisolated static func contentType(for format: HistoryExportFormat) -> UTType {
        switch format {
        case .json: .json
        case .csv: .commaSeparatedText
        }
    }

    /// Write the export to `url` and say how it went.
    static func write(_ format: HistoryExportFormat, history: ListeningHistory, to url: URL) async -> String {
        do {
            let count = try await history.export(format, to: url)
            return "Exported " + HistoryFormat.count(count, "listen") + "."
        } catch {
            HumLog.history.error("Export failed: \(String(describing: error), privacy: .private)")
            return "Couldn’t export: \(error.localizedDescription)"
        }
    }
}
