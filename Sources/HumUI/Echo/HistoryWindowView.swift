import HumCore
import SwiftUI

/// The Listening History window: a sidebar of sections and the section itself.
struct HistoryWindowView: View {
    static let defaultSize = CGSize(width: 880, height: 640)
    static let minimumSize = CGSize(width: 680, height: 480)

    @Environment(HistoryWindowPresenter.self) private var presenter
    @Environment(ListeningHistory.self) private var history
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @Environment(\.playerActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var exportMessage: String?
    @State private var importMessage: String?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isConfirmingRemoveImported = false
    /// This window, for the open and save panels to come down on.
    @State private var host = HostWindow()

    var body: some View {
        @Bindable var presenter = presenter
        NavigationSplitView(columnVisibility: $presenter.columnVisibility) {
            List(HistorySection.allCases, selection: Binding($presenter.section)) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            detail(presenter.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .top, spacing: 0) { notes }
        }
        .navigationTitle("Listening History")
        .toolbar { toolbar }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .readsHostWindow(into: host)
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
    }

    @ViewBuilder
    private func detail(_ section: HistorySection) -> some View {
        switch section {
        case .thisWeek: ThisWeekView()
        case .calendar: CalendarHistoryView()
        case .history: HistoryListView()
        case .top: TopHistoryView()
        case .rediscover: RediscoverView()
        }
    }

    /// A Play Now from any section that the source couldn't take, as the
    /// player's banner with its one fix (DESIGN.md §4.6). Then paused
    /// collection, a storage problem, or the last import or export, each in
    /// plain words with no warning colors.
    @ViewBuilder
    private var notes: some View {
        VStack(spacing: Spacing.xs) {
            if library?.failure != nil {
                LibraryFailureBanner()
            }
            if !history.isCollecting {
                HistoryNote(symbol: "pause.circle", text: "History is paused. Nothing you play is being saved.") {
                    Button("Resume") { history.setCollecting(true) }
                }
            }
            if let problem = history.storageProblem {
                HistoryNote(symbol: "externaldrive", text: problem) { EmptyView() }
            }
            if isImporting {
                HistoryNote(symbol: "square.and.arrow.down", text: "Importing Spotify history…") {
                    DelayedSpinner()
                }
            } else if let importMessage {
                HistoryNote(symbol: "square.and.arrow.down", text: importMessage) {
                    Button("OK") { self.importMessage = nil }
                }
            }
            if let exportMessage {
                HistoryNote(symbol: "square.and.arrow.up", text: exportMessage) {
                    Button("OK") { self.exportMessage = nil }
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, hasNotes ? Spacing.m : 0)
        .animation(noteMotion, value: history.isCollecting)
        .animation(noteMotion, value: exportMessage)
        .animation(noteMotion, value: importMessage)
        .animation(noteMotion, value: isImporting)
        .animation(noteMotion, value: library?.failure?.id)
    }

    private var noteMotion: Animation {
        Motion.spatial(Motion.smooth, reduceMotion: reduceMotion)
    }

    private var hasNotes: Bool {
        library?.failure != nil || !history.isCollecting || history.storageProblem != nil || exportMessage != nil
            || importMessage != nil || isImporting
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                history.setCollecting(!history.isCollecting)
            } label: {
                Label(
                    history.isCollecting ? "Pause History" : "Resume History",
                    systemImage: history.isCollecting ? "pause.circle" : "play.circle"
                )
            }
            .help(history.isCollecting ? "Stop saving what you listen to" : "Start saving what you listen to again")
            Menu {
                Button("Import Spotify History…") { importHistory() }
                    .disabled(isImporting)
                if history.echo.imported != nil {
                    Button("Remove Imported History…") { isConfirmingRemoveImported = true }
                        .disabled(isImporting)
                }
                Divider()
                Button("Export as JSON…") { export(.json) }
                    .disabled(isExporting)
                Button("Export as CSV…") { export(.csv) }
                    .disabled(isExporting)
                Divider()
                Button("History Settings…") { actions.openSettingsPane(.echoPrivacy) }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("Import, export, or manage your listening history")
        }
    }

    private func importHistory() {
        Task {
            guard let urls = await HistoryImporter.choose(on: host.window) else { return }
            importMessage = nil
            isImporting = true
            importMessage = await HistoryImporter.read(urls, into: history)
            isImporting = false
        }
    }

    private func export(_ format: HistoryExportFormat) {
        isExporting = true
        Task {
            let message = await HistoryExporter.export(format, history: history, on: host.window)
            isExporting = false
            if let message { exportMessage = message }
        }
    }
}

/// A one-line note above a page, with an optional action.
struct HistoryNote<Action: View>: View {
    var symbol: String
    var text: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(HumColor.secondaryLabel)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(HumColor.label)
            Spacer(minLength: Spacing.s)
            action
                .buttonStyle(ActionButtonStyle(compact: true))
                .controlSize(.small)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(HumColor.fillQuaternary, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
