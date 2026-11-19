import HumCore
import SwiftUI

/// Top: the most-played songs, artists, or albums for a period.
struct TopHistoryView: View {
    @Environment(ListeningHistory.self) private var history
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @State private var dimension: TopDimension = .songs
    @State private var period: Period = .month
    @State private var entries: [TopEntry] = []
    @State private var sources = HistoryProvenance()
    @State private var start: Date?
    @State private var isLoaded = false

    enum Period: String, CaseIterable, Identifiable {
        case week, month, year, all

        var id: Self { self }

        var title: String {
            switch self {
            case .week: "This Week"
            case .month: "This Month"
            case .year: "This Year"
            case .all: "All Time"
            }
        }

        func start(now: Date, calendar: Calendar) -> Date? {
            switch self {
            case .week: calendar.dateInterval(of: .weekOfYear, for: now)?.start
            case .month: calendar.dateInterval(of: .month, for: now)?.start
            case .year: calendar.dateInterval(of: .year, for: now)?.start
            case .all: nil
            }
        }
    }

    private struct LoadKey: Equatable {
        var dimension: TopDimension
        var period: Period
        var revision: Int
    }

    var body: some View {
        HistoryPage(title: "Top", caption: caption) {
            PillMenu(
                title: "Period",
                selection: $period,
                options: Period.allCases.map { .init(value: $0, title: $0.title) }
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                dimensionChips
                if isLoaded, entries.isEmpty {
                    HistoryEmptyState(
                        symbol: "chart.bar",
                        title: "Nothing Counted Yet",
                        message: "A play counts after 30 seconds, once you’ve heard half the song or 4 minutes of it."
                    )
                } else if !entries.isEmpty {
                    ranking
                }
            }
        }
        .task(id: LoadKey(dimension: dimension, period: period, revision: history.revision)) { await load() }
    }

    /// What to rank, as History's filter chips (DESIGN.md §5.9). They scroll
    /// with the page rather than floating over it, so they take a fill (§3.6).
    private var dimensionChips: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(TopDimension.allCases, id: \.self) { choice in
                Button {
                    dimension = choice
                } label: {
                    Text(choice.title)
                        .fixedSize()
                }
                .buttonStyle(PlayerButtonStyle(.chip, isOn: dimension == choice))
                .accessibilityAddTraits(dimension == choice ? .isSelected : [])
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }

    private var caption: String {
        guard isLoaded else { return " " }
        let format = HistoryFormat(calendar: history.calendar)
        let range = start.map { "Counted plays since " + format.day($0) } ?? "Counted plays, all time"
        return range + " · " + HistoryFormat.source(sources)
    }

    private var ranking: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: Spacing.m) {
                    Text("\(index + 1)")
                        .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(HumColor.tertiaryLabel)
                        .frame(width: 24, alignment: .trailing)
                    HistoryItemRow(
                        artworkKey: entry.artworkKey,
                        title: entry.title,
                        subtitle: entry.subtitle
                    ) {
                        VStack(alignment: .trailing, spacing: 1) {
                            HistoryNumber(HistoryFormat.count(entry.plays, "play"), color: .label)
                            Text(HistoryFormat.duration(entry.listened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(HumColor.tertiaryLabel)
                        }
                    }
                }
                .contentShape(.rect)
                .contextMenu { HistoryEntryMenu(entry: entry, dimension: dimension, library: library) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Number \(index + 1), \(entry.title)" + (entry.subtitle.isEmpty ? "" : ", \(entry.subtitle)"))
                .accessibilityValue(HistoryFormat.count(entry.plays, "play") + ", " + HistoryFormat.duration(entry.listened))
                if index < entries.count - 1 {
                    Divider().padding(.leading, 24 + Spacing.m + 32 + Spacing.m)
                }
            }
        }
    }

    private func load() async {
        let now = Date()
        let start = period.start(now: now, calendar: history.calendar)
        do {
            let entries = try await history.store.top(dimension, from: start, to: nil)
            let sources = try await history.store.provenance(from: start, to: nil)
            guard !Task.isCancelled else { return }
            self.entries = entries
            self.sources = sources
            self.start = start
            isLoaded = true
        } catch {
            HumLog.history.error("Top page couldn't load: \(String(describing: error), privacy: .public)")
            isLoaded = true
        }
    }
}
