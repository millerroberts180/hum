import HumCore
import SwiftUI

/// Calendar: six months of daily listening, and the songs from a chosen day.
struct CalendarHistoryView: View {
    @Environment(ListeningHistory.self) private var history
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @State private var model: Model?
    @State private var selection: Date?
    @State private var dayListens: [Listen] = []

    static let monthCount = 6

    struct Model: Equatable {
        var months: [CalendarMonth]
        var totals: [Date: DayTotal]
        var scale: HeatScale
        var today: Date
        var sources: HistoryProvenance
        var listened: TimeInterval
        var activeDays: Int
    }

    var body: some View {
        HistoryPage(title: "Calendar", caption: caption) {
            if let model {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    summary(model)
                    HeatCalendar(
                        months: model.months,
                        totals: model.totals,
                        scale: model.scale,
                        today: model.today,
                        calendar: history.calendar,
                        selection: $selection
                    )
                    if let selection {
                        dayDetail(selection, model: model)
                    } else {
                        Text("Choose a day to see what you played.")
                            .font(.callout)
                            .foregroundStyle(HumColor.secondaryLabel)
                    }
                }
            }
        }
        .task(id: history.revision) { await load() }
        .task(id: DayKey(day: selection, revision: history.revision)) { await loadDay() }
    }

    private struct DayKey: Equatable {
        var day: Date?
        var revision: Int
    }

    private var caption: String {
        guard let model, let first = model.months.first?.start else { return " " }
        let format = HistoryFormat(calendar: history.calendar)
        return format.day(first, now: model.today) + " – today · " + HistoryFormat.source(model.sources)
    }

    private func summary(_ model: Model) -> some View {
        HStack(spacing: Spacing.xl) {
            stat(HistoryFormat.duration(model.listened), "listened")
            stat(model.activeDays.formatted(), model.activeDays == 1 ? "day with music" : "days with music")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(HumColor.label)
            Text(label)
                .font(.callout)
                .foregroundStyle(HumColor.secondaryLabel)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func dayDetail(_ day: Date, model: Model) -> some View {
        let format = HistoryFormat(calendar: history.calendar)
        let total = model.totals[day]
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                HistorySubheading(format.weekday(day) + ", " + format.day(day, now: model.today))
                Spacer()
                if let total {
                    HistoryNumber(HistoryFormat.duration(total.listened) + " · " + HistoryFormat.count(total.plays, "play"))
                }
            }
            if dayListens.isEmpty {
                Text("Nothing played this day.")
                    .font(.callout)
                    .foregroundStyle(HumColor.secondaryLabel)
            } else {
                VStack(spacing: 0) {
                    ForEach(dayListens) { listen in
                        HistoryItemRow(artworkKey: listen.artworkKey, title: listen.title, subtitle: listen.artist) {
                            HistoryNumber(format.time(listen.startedAt), color: .tertiaryLabel)
                        }
                        .contentShape(.rect)
                        .contextMenu { ListenMenu(listen: listen, library: library) }
                        if listen.id != dayListens.last?.id {
                            Divider().padding(.leading, 32 + Spacing.m)
                        }
                    }
                }
            }
        }
        .padding(Spacing.l)
        .background(HumColor.fillQuaternary, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func load() async {
        let calendar = history.calendar
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let months = CalendarMonth.months(endingAt: now, count: Self.monthCount, calendar: calendar)
        guard let start = months.first?.start else { return }
        do {
            let totals = try await history.store.dailyTotals(from: start, to: now, calendar: calendar)
            let sources = try await history.store.provenance(from: start, to: now)
            model = Model(
                months: months,
                totals: Dictionary(totals.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first }),
                scale: HeatScale(values: totals.map(\.listened)),
                today: today,
                sources: sources,
                listened: totals.reduce(0) { $0 + $1.listened },
                activeDays: totals.count { $0.listened > 0 }
            )
            // Open on the latest day with music, so the page starts with something.
            if selection == nil { selection = totals.last?.day }
        } catch {
            HumLog.history.error("Calendar page couldn't load: \(String(describing: error), privacy: .public)")
            model = nil
        }
    }

    private func loadDay() async {
        guard let selection,
              let end = history.calendar.date(byAdding: .day, value: 1, to: selection)
        else {
            dayListens = []
            return
        }
        dayListens = (try? await history.store.listens(from: selection, to: end)) ?? []
    }
}
