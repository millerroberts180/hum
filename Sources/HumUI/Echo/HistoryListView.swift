import HumCore
import SwiftUI

/// History: every listen, newest first, grouped by day. Search and filter by
/// artist, album, playlist, and time of day; remove listens with undo.
struct HistoryListView: View {
    @Environment(ListeningHistory.self) private var history
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = HistoryQuery()
    @State private var listens: [Listen] = []
    @State private var options = FilterOptions()
    @State private var total = 0
    /// How many listens the search and filters match, past the list's limit.
    @State private var matches = 0
    @State private var sources = HistoryProvenance()
    @State private var selection: Set<Int64> = []
    @State private var isLoaded = false
    /// Whether the list has scrolled under the filters, for the hairline there.
    @State private var isScrolled = false

    struct FilterOptions: Equatable {
        var artists: [String] = []
        var albums: [String] = []
        var playlists: [String] = []
    }

    private struct LoadKey: Equatable {
        var query: HistoryQuery
        var revision: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HistoryPageHeader(title: "History", caption: caption) { EmptyView() }
                filters
            }
            .padding([.horizontal, .top], Spacing.xl)
            .padding(.bottom, Spacing.m)
            list
        }
        .searchable(text: $query.search, placement: .toolbar, prompt: "Search history")
        .task(id: LoadKey(query: query, revision: history.revision)) { await load() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !history.lastRemoved.isEmpty {
                HistoryUndoBar(count: history.lastRemoved.count) { undo() } dismiss: {
                    history.clearUndo()
                }
                .padding(Spacing.m)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.spatial(Motion.smooth, reduceMotion: reduceMotion), value: history.lastRemoved.isEmpty)
    }

    private var caption: String {
        guard isLoaded else { return " " }
        return Self.count(shown: listens.count, of: isFiltered ? matches : total, isFiltered: isFiltered)
            + " · " + HistoryFormat.source(sources)
    }

    /// "512 listens", or "The latest 400 of 512 listens" when the list stops
    /// short; under a filter, "12 listens match" or "The latest 400 of 512
    /// matching listens".
    nonisolated static func count(shown: Int, of total: Int, isFiltered: Bool) -> String {
        if shown < total {
            return "The latest \(shown.formatted()) of " + HistoryFormat.count(total, isFiltered ? "matching listen" : "listen")
        }
        guard isFiltered else { return HistoryFormat.count(total, "listen") }
        return HistoryFormat.count(total, "listen") + (total == 1 ? " matches" : " match")
    }

    private var isFiltered: Bool { query.isFiltered }

    /// The hard scroll edge draws its own hairline on macOS 26.
    private static var drawsScrollHairline: Bool {
        if #available(macOS 26, *) { false } else { true }
    }

    // MARK: Filters

    /// Pill menus (DESIGN.md §5.9, family 10), and Clear Filters as an
    /// action button once one is set.
    private var filters: some View {
        HStack(spacing: Spacing.s) {
            filterMenu("Artist", all: "Any Artist", values: options.artists, selection: $query.artist)
            filterMenu("Album", all: "Any Album", values: options.albums, selection: $query.album)
            if !options.playlists.isEmpty {
                filterMenu("Playlist", all: "Any Playlist", values: options.playlists, selection: $query.playlist)
            }
            PillMenu(
                title: "Time of Day",
                selection: $query.timeOfDay,
                any: .init(value: nil, title: "Any Time"),
                options: TimeOfDay.allCases.map { .init(value: $0, title: $0.title) }
            )
            if isFiltered {
                Button("Clear Filters") {
                    query = HistoryQuery()
                }
                .buttonStyle(ActionButtonStyle())
            }
            Spacer(minLength: 0)
        }
    }

    private func filterMenu(_ title: String, all: String, values: [String], selection: Binding<String?>) -> some View {
        PillMenu(
            title: title,
            selection: selection,
            any: .init(value: nil, title: all),
            options: values.map { .init(value: $0, title: $0) }
        )
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if isLoaded, listens.isEmpty {
            Spacer()
            if isFiltered {
                HistoryEmptyState(symbol: "magnifyingglass", title: "No Listens Match", message: "Try another search or clear the filters.")
            } else {
                HistoryEmptyState(
                    symbol: "clock",
                    title: "No Listening History Yet",
                    message: history.isCollecting
                        ? "Songs you play will appear here."
                        : "History is paused. Songs you play aren’t being saved."
                )
            }
            Spacer()
        } else {
            let format = HistoryFormat(calendar: history.calendar)
            let now = Date()
            List(selection: $selection) {
                ForEach(days, id: \.day) { group in
                    // A row, not a section header: the list's sticky headers
                    // float on a material, and these covers may be Spotify's.
                    Text(Self.dayTitle(group.day, format: format, now: now))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HumColor.secondaryLabel)
                        .padding(.top, group.day == days.first?.day ? 0 : Spacing.m)
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.listens) { listen in
                        HistoryListenRow(listen: listen, format: format)
                            .tag(listen.id)
                    }
                }
            }
            .listStyle(.inset)
            .historyScrollEdge()
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0.5 } action: { _, scrolled in
                isScrolled = scrolled
            }
            .overlay(alignment: .top) {
                if isScrolled, Self.drawsScrollHairline { Divider() }
            }
            .contextMenu(forSelectionType: Int64.self) { ids in
                if ids.count == 1, let library, let listen = listens.first(where: { ids.contains($0.id) }) {
                    ListenMenu(listen: listen, library: library)
                    Divider()
                }
                if !ids.isEmpty {
                    Button(ids.count == 1 ? "Remove from History" : "Remove \(ids.count) Listens from History") {
                        remove(ids)
                    }
                }
            }
            .onDeleteCommand { remove(selection) }
        }
    }

    private struct DayGroup {
        var day: Date
        var listens: [Listen]
    }

    private var days: [DayGroup] {
        var groups: [DayGroup] = []
        for listen in listens {
            let day = history.calendar.startOfDay(for: listen.startedAt)
            if groups.last?.day == day {
                groups[groups.count - 1].listens.append(listen)
            } else {
                groups.append(DayGroup(day: day, listens: [listen]))
            }
        }
        return groups
    }

    static func dayTitle(_ day: Date, format: HistoryFormat, now: Date) -> String {
        let relative = format.relativeDay(day, now: now)
        let named = relative.prefix(1).uppercased() + relative.dropFirst()
        return relative == format.day(day, now: now) ? format.weekday(day) + ", " + named : named
    }

    // MARK: Actions

    private func remove(_ ids: Set<Int64>) {
        let removed = listens.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        history.remove(removed)
        selection.subtract(ids)
        undoManager?.registerUndo(withTarget: history) { history in
            history.restore(removed)
        }
        undoManager?.setActionName(removed.count == 1 ? "Remove from History" : "Remove Listens")
    }

    private func undo() {
        if let undoManager, undoManager.canUndo {
            undoManager.undo()
        } else {
            history.undoRemove()
        }
    }

    private func load() async {
        let store = history.store
        let calendar = history.calendar
        let query = query
        do {
            let found = try await store.listens(matching: query, calendar: calendar)
            let filters = try await store.filterOptions()
            let total = try await store.count()
            let matches = query.isFiltered ? try await store.count(matching: query, calendar: calendar) : total
            // Under a filter the caption covers only the matches, so it names
            // only their sources.
            let sources = query.isFiltered ? HistoryProvenance(found) : try await store.provenance()
            guard !Task.isCancelled else { return }
            listens = found
            options = FilterOptions(artists: filters.artists, albums: filters.albums, playlists: filters.playlists)
            self.total = total
            self.matches = matches
            self.sources = sources
            selection.formIntersection(found.map(\.id))
            isLoaded = true
        } catch {
            HumLog.history.error("History page couldn't load: \(String(describing: error), privacy: .public)")
            isLoaded = true
        }
    }
}

/// One listen: cover, title, artist and album, the time it started, and how
/// much was heard.
struct HistoryListenRow: View {
    var listen: Listen
    var format: HistoryFormat

    var body: some View {
        HistoryItemRow(
            artworkKey: listen.artworkKey,
            title: listen.title,
            subtitle: [listen.artist, listen.album].filter { !$0.isEmpty }.joined(separator: " · ")
        ) {
            VStack(alignment: .trailing, spacing: 1) {
                HistoryNumber(format.time(listen.startedAt))
                Text(heard)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(HumColor.tertiaryLabel)
            }
        }
        .accessibilityValue(format.time(listen.startedAt) + ", " + heard)
    }

    /// How much was heard, and "imported" for listens Hum didn't see itself.
    private var heard: String {
        let time = TimeFormatting.clock(listen.listened)
        let heard = switch listen.ending {
        case .completed: listen.counts ? time : time + " · not counted"
        case .skipped: "Skipped at " + time
        case .partial: listen.counts ? time + " heard" : time + " · not counted"
        }
        return listen.origin == .imported ? heard + " · imported" : heard
    }
}

/// "Removed 3 listens." with Undo, along the bottom edge.
struct HistoryUndoBar: View {
    var count: Int
    var undo: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text("Removed " + HistoryFormat.count(count, "listen") + ".")
                .font(.callout)
                .foregroundStyle(HumColor.label)
            Button("Undo", action: undo)
                .buttonStyle(ActionButtonStyle(compact: true))
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .modifier(FloatingChipBackground())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// A capsule that floats over content, as the undo bar does over the list:
/// interactive Liquid Glass on macOS 26, the `glassCard` material before that
/// (DESIGN.md §3.6). A capsule that sits in the content takes a fill instead.
private struct FloatingChipBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.humMaterial(.glassCard, in: Capsule())
        }
    }
}
