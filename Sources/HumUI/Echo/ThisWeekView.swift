import Charts
import HumCore
import SwiftUI

/// This Week: a receipt of the week so far, time per day, and any milestones.
struct ThisWeekView: View {
    @Environment(ListeningHistory.self) private var history
    @State private var receipt: WeekReceipt?
    @State private var sources = HistoryProvenance()

    var body: some View {
        HistoryPage(title: "This Week", caption: caption) {
            if let receipt {
                if receipt.listened == 0 {
                    HistoryEmptyState(
                        symbol: "calendar",
                        title: "Nothing Played This Week",
                        message: "Songs you play this week will be added up here."
                    )
                } else {
                    content(receipt)
                }
            }
        }
        .task(id: history.revision) { await load() }
    }

    private var caption: String {
        guard let receipt else { return " " }
        let format = HistoryFormat(calendar: history.calendar)
        return "Since \(format.weekday(receipt.start)), \(format.day(receipt.start)) · " + HistoryFormat.source(sources)
    }

    private func content(_ receipt: WeekReceipt) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text(receipt.takeaway)
                .font(.title3)
                .foregroundStyle(HumColor.label)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    WeekReceiptCard(receipt: receipt)
                        .frame(width: 320)
                    sideColumn(receipt)
                }
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    WeekReceiptCard(receipt: receipt)
                    sideColumn(receipt)
                }
            }
        }
    }

    private func sideColumn(_ receipt: WeekReceipt) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HistorySubheading("Time per Day")
                WeekChart(days: receipt.days, calendar: history.calendar)
            }
            if !receipt.milestones.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HistorySubheading("Milestones")
                    ForEach(receipt.milestones, id: \.self) { milestone in
                        Label {
                            Text(milestone)
                                .font(.callout)
                                .foregroundStyle(HumColor.label)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark.seal")
                                .foregroundStyle(HumColor.accent)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        let date = Date()
        let calendar = history.calendar
        do {
            let receipt = try await history.store.weekReceipt(now: date, calendar: calendar)
            let sources = try await history.store.provenance(from: receipt.start, to: receipt.end)
            self.receipt = receipt
            self.sources = sources
        } catch {
            HumLog.history.error("This Week page couldn't load: \(String(describing: error), privacy: .public)")
            receipt = nil
        }
    }
}

/// The week as a receipt: the totals, then the top artist, the most repeated
/// song, and a discovery, each with its count.
struct WeekReceiptCard: View {
    var receipt: WeekReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            line("Time listened", value: HistoryFormat.duration(receipt.listened))
            line("Plays", value: receipt.plays.formatted())
            line("Different songs", value: receipt.songs.formatted())
            ReceiptRule()
            entry("Top artist", receipt.topArtist)
            entry("Most repeated", receipt.mostRepeated)
            entry("A discovery", receipt.discovery)
            ReceiptRule()
            Text("A play counts after 30 seconds, once you’ve heard half the song or 4 minutes of it.")
                .font(.caption)
                .foregroundStyle(HumColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.l)
        .background(HumColor.fillQuaternary, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func line(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(HumColor.secondaryLabel)
            Spacer(minLength: Spacing.s)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(HumColor.label)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func entry(_ label: String, _ line: WeekReceipt.Line?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(HumColor.secondaryLabel)
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: 1) {
                Text(line?.name ?? "None yet")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(line == nil ? HumColor.tertiaryLabel : HumColor.label)
                    .lineLimit(1)
                if let line {
                    Text(line.detail)
                        .font(.caption)
                        .foregroundStyle(HumColor.secondaryLabel)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(line.map { $0.name + ", " + $0.detail } ?? "None yet")
    }
}

/// A dashed hairline, as on a printed receipt.
struct ReceiptRule: View {
    var body: some View {
        Line()
            .stroke(HumColor.separator, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        nonisolated func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

/// Minutes per day as bars in the accent, each labeled with its time.
struct WeekChart: View {
    var days: [DayTotal]
    var calendar: Calendar

    var body: some View {
        let format = HistoryFormat(calendar: calendar)
        Chart(days, id: \.day) { day in
            BarMark(
                x: .value("Day", format.weekday(day.day)),
                y: .value("Minutes", day.listened / 60)
            )
            .foregroundStyle(HumColor.accent)
            .cornerRadius(3)
            .annotation(position: .top, spacing: 2) {
                if day.listened > 0 {
                    Text(Self.short(day.listened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(HumColor.secondaryLabel)
                }
            }
            .accessibilityLabel(format.weekday(day.day))
            .accessibilityValue(day.listened > 0
                ? HistoryFormat.duration(day.listened) + ", " + HistoryFormat.count(day.plays, "play")
                : "No listening")
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(String(name.prefix(3)))
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 150)
    }

    /// "42m", "1h 5m".
    static func short(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
