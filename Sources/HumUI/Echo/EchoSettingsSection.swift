import HumCore
import SwiftUI

/// Listening-history controls for Settings › History & Privacy: collection,
/// what's collected, import, export, and erase. Reads everything from the
/// environment; embed it in a grouped `Form`. Every button is an action button
/// in a row that says why you'd press it (DESIGN.md §8).
struct EchoSettingsSection: View {
    @Environment(ListeningHistory.self) private var history: ListeningHistory?
    @Environment(HistoryWindowPresenter.self) private var historyWindow: HistoryWindowPresenter?
    @State private var isConfirmingErase = false
    @State private var isConfirmingRemoveImported = false
    @State private var exportResult: String?
    @State private var importResult: String?
    @State private var isImporting = false
    /// Settings, for the open and save panels to come down on.
    @State private var host = HostWindow()

    var body: some View {
        if let history {
            content(history)
        } else {
            Section("Listening History") {
                Text("Listening history isn’t available in this window.")
                    .foregroundStyle(HumColor.secondaryLabel)
            }
        }
    }

    @ViewBuilder
    private func content(_ history: ListeningHistory) -> some View {
        Section {
            DetailToggle(
                title: "Collect listening history",
                detail: history.isCollecting
                    ? "Hum notes each song you play on this Mac. Turning this off keeps what’s already saved."
                    : "Paused. Nothing you play is saved until you turn this back on.",
                isOn: Binding(get: { history.isCollecting }, set: { history.setCollecting($0) })
            )
            if let historyWindow {
                LabeledContent {
                    Button {
                        historyWindow.show()
                    } label: {
                        ActionLabel("Open Listening History…", symbol: "clock")
                    }
                    .buttonStyle(ActionButtonStyle())
                } label: {
                    DetailLabel(title: "Look back at your listening", detail: "Your week, a calendar, every listen, and your top songs.")
                }
            }
        } header: {
            Text("Listening History")
        } footer: {
            // A blank line until history is read, so the count doesn't open
            // on "Nothing saved yet." and the sections below don't jump.
            FooterNote(history.hasLoaded ? summary(history.echo) : " ")
        }

        Section("What Hum Keeps") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("For each song: its title, artist, and album, the app that played it, the playlist or album it came from when the app says, when it started, and how long you listened.")
                Text("A play counts after 30 seconds and half the song, or 4 minutes for long songs. Paused time never counts.")
                Text("History stays in a file on this Mac. Hum never sends it anywhere.")
            }
            .font(.callout)
            .foregroundStyle(HumColor.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }

        Section {
            LabeledContent {
                HStack(spacing: Spacing.s) {
                    if isImporting {
                        DelayedSpinner()
                    }
                    Button {
                        importHistory(history)
                    } label: {
                        ActionLabel("Import Spotify History…", symbol: "square.and.arrow.down")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(isImporting)
                }
            } label: {
                DetailLabel(title: "Add listening from before Hum", detail: "From Spotify’s data download.")
            }
            .readsHostWindow(into: host)
            if history.echo.imported != nil {
                LabeledContent {
                    Button {
                        isConfirmingRemoveImported = true
                    } label: {
                        ActionLabel("Remove Imported History…", symbol: "trash")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(isImporting)
                } label: {
                    DetailLabel(title: "Take out what you imported", detail: "What Hum saved itself stays.")
                }
            }
            if let importResult {
                Text(importResult)
                    .font(.caption)
                    .foregroundStyle(HumColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Imported History")
        } footer: {
            FooterNote("Bring in listening from before Hum with Spotify’s data download: choose its JSON files or its folder. Imported listens are labeled as imported, and any Hum already has are skipped. Hum reads only the files.")
        }
        .confirmationDialog(
            "Remove Imported History?",
            isPresented: $isConfirmingRemoveImported,
            titleVisibility: .visible
        ) {
            Button("Remove Imported History", role: .destructive) { history.removeImported() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(HistoryImporter.removalMessage(history.echo.imported))
        }

        Section {
            LabeledContent {
                Button {
                    export(.json, history: history)
                } label: {
                    ActionLabel("Export as JSON…", symbol: "square.and.arrow.up")
                }
                .buttonStyle(ActionButtonStyle())
            } label: {
                DetailLabel(title: "A copy for apps and scripts", detail: nil)
            }
            .readsHostWindow(into: host)
            LabeledContent {
                Button {
                    export(.csv, history: history)
                } label: {
                    ActionLabel("Export as CSV…", symbol: "square.and.arrow.up")
                }
                .buttonStyle(ActionButtonStyle())
            } label: {
                DetailLabel(title: "A copy for spreadsheets", detail: nil)
            }
            LabeledContent {
                Button(role: .destructive) {
                    isConfirmingErase = true
                } label: {
                    ActionLabel("Erase All History…", symbol: "trash")
                }
                .buttonStyle(ActionButtonStyle())
            } label: {
                DetailLabel(title: "Start over", detail: "Removes every listen Hum has saved on this Mac.")
            }
            if let exportResult {
                Text(exportResult)
                    .font(.caption)
                    .foregroundStyle(HumColor.secondaryLabel)
            }
        } header: {
            Text("Your Data")
        } footer: {
            FooterNote("Exports include every listen with its times, in a format other apps can read.")
        }
        .confirmationDialog(
            "Erase All Listening History?",
            isPresented: $isConfirmingErase,
            titleVisibility: .visible
        ) {
            Button("Erase All History", role: .destructive) { history.eraseAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every listen Hum has saved on this Mac. It can’t be undone.")
        }
    }

    private func summary(_ echo: EchoSnapshot) -> String {
        Self.summary(echo, format: HistoryFormat())
    }

    /// "1,204 listens saved since Nov 4. 3,310 imported listens from Mar 2, 2021
    /// to Oct 30." Tracked and imported listens are counted apart.
    nonisolated static func summary(_ echo: EchoSnapshot, format: HistoryFormat, now: Date = .now) -> String {
        var parts: [String] = []
        let tracked = echo.listenCount - (echo.imported?.count ?? 0)
        if let since = echo.trackedSince, tracked > 0 {
            parts.append(HistoryFormat.count(tracked, "listen") + " saved since " + format.day(since, now: now) + ".")
        }
        if let imported = echo.imported {
            parts.append(
                HistoryFormat.count(imported.count, "imported listen") + " from "
                    + format.day(imported.since, now: now) + " to " + format.day(imported.until, now: now) + "."
            )
        }
        return parts.isEmpty ? "Nothing saved yet." : parts.joined(separator: " ")
    }

    private func importHistory(_ history: ListeningHistory) {
        Task {
            guard let urls = await HistoryImporter.choose(on: host.window) else { return }
            importResult = nil
            isImporting = true
            importResult = await HistoryImporter.read(urls, into: history)
            isImporting = false
        }
    }

    private func export(_ format: HistoryExportFormat, history: ListeningHistory) {
        Task {
            if let result = await HistoryExporter.export(format, history: history, on: host.window) {
                exportResult = result
            }
        }
    }
}
