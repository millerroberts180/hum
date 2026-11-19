import HumCore
import SwiftUI

/// Months of 10-pt rounded squares, one per day, in five steps of the accent
/// (DESIGN.md §3.5.8, §5.7). Click a day or move with the arrow keys to select it.
struct HeatCalendar: View {
    var months: [CalendarMonth]
    var totals: [Date: DayTotal]
    var scale: HeatScale
    var today: Date
    var calendar: Calendar
    @Binding var selection: Date?

    @FocusState private var isFocused: Bool

    /// A day's square (DESIGN.md §5.7).
    nonisolated static let cell: CGFloat = 10
    /// Between days, across and down.
    nonisolated static let gap = Spacing.xs
    nonisolated static let cellRadius = Spacing.xxs
    /// The selected day's ring: just outside the square, concentric with it,
    /// clear of its neighbours.
    nonisolated static let ringOutset = Spacing.xxs
    nonisolated static let ringWidth: CGFloat = 1.5
    nonisolated static let ringRadius = cellRadius + ringOutset

    var body: some View {
        let initials = CalendarMonth.weekdayInitials(calendar: calendar)
        VStack(alignment: .leading, spacing: Spacing.l) {
            MonthGrid {
                ForEach(months) { month in
                    monthView(month, initials: initials)
                }
            }
            legend
        }
        // Room for the selected day's ring at the grid's edges.
        .padding(Spacing.xs)
        .focusable()
        .focused($isFocused)
        // The arrow keys move the selection, and the selected day's ring
        // shows where it is; the whole grid takes no ring of its own (§5.7).
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            move(by: Self.offset(for: press.key))
            return .handled
        }
    }

    private func monthView(_ month: CalendarMonth, initials: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(month.start.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide)))
                .humText(.cardTitle)
                .padding(.bottom, Spacing.xxs)
            HStack(spacing: Self.gap) {
                ForEach(Array(initials.enumerated()), id: \.offset) { _, initial in
                    // Shrinks to the column rather than clipping at larger sizes.
                    Text(initial)
                        .humText(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: Self.cell)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Self.gap) {
                ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: Self.gap) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day)
                            } else {
                                Color.clear.frame(width: Self.cell, height: Self.cell)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(month.start.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()))
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let isFuture = day > today
        let total = totals[day]
        let level = scale.level(total?.listened ?? 0)
        let isSelected = selection == day
        RoundedRectangle(cornerRadius: Self.cellRadius, style: .continuous)
            .fill(isFuture ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Self.fill(level)))
            .frame(width: Self.cell, height: Self.cell)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Self.ringRadius, style: .continuous)
                        .strokeBorder(HumColor.label, lineWidth: Self.ringWidth)
                        .padding(-Self.ringOutset)
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                guard !isFuture else { return }
                selection = isSelected ? nil : day
                isFocused = true
            }
            .help(isFuture ? "" : tooltip(day, total))
            .accessibilityElement()
            .accessibilityLabel(day.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).month(.wide).day()))
            .accessibilityValue(isFuture ? "Not yet" : spoken(total))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { if !isFuture { selection = day } }
            .accessibilityHidden(isFuture)
    }

    private var legend: some View {
        HStack(spacing: Self.gap) {
            Text("Less")
                .padding(.trailing, Spacing.xxs)
            ForEach(0 ..< HeatScale.levels, id: \.self) { level in
                RoundedRectangle(cornerRadius: Self.cellRadius, style: .continuous)
                    .fill(Self.fill(level))
                    .frame(width: Self.cell, height: Self.cell)
            }
            Text("More")
                .padding(.leading, Spacing.xxs)
        }
        .humText(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Darker squares mean more time listened that day")
    }

    /// `fillQuaternary` for none, then the accent at 25, 50, 75, and 100%.
    static func fill(_ level: Int) -> AnyShapeStyle {
        level == 0
            ? AnyShapeStyle(HumColor.fillQuaternary)
            : AnyShapeStyle(HumColor.accent.opacity(Double(min(level, 4)) * 0.25))
    }

    private func tooltip(_ day: Date, _ total: DayTotal?) -> String {
        let format = HistoryFormat(calendar: calendar)
        return format.weekday(day) + ", " + format.day(day, now: today) + ": " + spoken(total)
    }

    private func spoken(_ total: DayTotal?) -> String {
        guard let total, total.listened > 0 else { return "No listening" }
        return HistoryFormat.duration(total.listened) + ", " + HistoryFormat.count(total.plays, "play")
    }

    nonisolated static func offset(for key: KeyEquivalent) -> Int {
        switch key {
        case .leftArrow: -1
        case .rightArrow: 1
        case .upArrow: -7
        default: 7
        }
    }

    private func move(by days: Int) {
        let start = months.first?.start ?? today
        if let day = Self.day(moving: selection, by: days, from: start, through: today, calendar: calendar) {
            selection = day
        }
    }

    /// Where an arrow key takes the selection: `days` on from it, or today
    /// when nothing is selected yet. `nil` past either end of the calendar,
    /// where the selection stays.
    nonisolated static func day(
        moving selection: Date?,
        by days: Int,
        from start: Date,
        through today: Date,
        calendar: Calendar
    ) -> Date? {
        let base = selection ?? calendar.startOfDay(for: today)
        guard let next = calendar.date(byAdding: .day, value: selection == nil ? 0 : days, to: base) else { return nil }
        let day = calendar.startOfDay(for: next)
        return day >= start && day <= today ? day : nil
    }
}

/// Months in rows of equal length, so no month sits alone: all of them in one
/// row when they fit, otherwise the widest even split (three and three, then
/// two by three). Spare width widens the gaps, up to a limit.
struct MonthGrid: Layout {
    var minimumSpacing: CGFloat = Spacing.l
    var maximumSpacing: CGFloat = Spacing.xxl
    var rowSpacing: CGFloat = Spacing.xl

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let plan = arrangement(width: proposal.width, subviews: subviews)
        let rows = rowHeights(plan.columns, subviews: subviews)
        let width = CGFloat(plan.columns) * plan.item + CGFloat(max(0, plan.columns - 1)) * plan.spacing
        let height = rows.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * rowSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = arrangement(width: bounds.width, subviews: subviews)
        let rows = rowHeights(plan.columns, subviews: subviews)
        var y = bounds.minY
        for (row, height) in rows.enumerated() {
            for column in 0 ..< plan.columns {
                let index = row * plan.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (plan.item + plan.spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            }
            y += height + rowSpacing
        }
    }

    nonisolated static func columns(count: Int, fitting fit: Int) -> Int {
        guard count > fit else { return max(1, count) }
        return (1 ... max(1, fit)).reversed().first { count.isMultiple(of: $0) } ?? 1
    }

    private func arrangement(width: CGFloat?, subviews: Subviews) -> (columns: Int, item: CGFloat, spacing: CGFloat) {
        let item = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let available = width ?? .infinity
        let fit = available.isFinite ? Int((available + minimumSpacing) / (item + minimumSpacing)) : subviews.count
        let columns = Self.columns(count: subviews.count, fitting: fit)
        guard columns > 1, available.isFinite else { return (columns, item, minimumSpacing) }
        let spare = (available - CGFloat(columns) * item) / CGFloat(columns - 1)
        return (columns, item, min(maximumSpacing, max(minimumSpacing, spare)))
    }

    private func rowHeights(_ columns: Int, subviews: Subviews) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: max(1, columns)).map { start in
            subviews[start ..< min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(.unspecified).height }
                .max() ?? 0
        }
    }
}

#if DEBUG
struct HeatCalendar_Previews: PreviewProvider {
    static let calendar = Calendar.autoupdatingCurrent
    static let today = calendar.startOfDay(for: Date())

    /// Two months of uneven listening, with some days off.
    static let totals: [DayTotal] = (0..<60).compactMap { offset in
        guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
        let minutes = Double((offset * 37) % 11) * 12
        return minutes == 0 ? nil : DayTotal(day: day, listened: minutes * 60, plays: Int(minutes / 4))
    }

    static var previews: some View {
        PreviewGallery(cases: [.largeLight, .largeDark], isSquare: false) {
            HeatCalendar(
                months: CalendarMonth.months(endingAt: Date(), count: 2, calendar: calendar),
                totals: Dictionary(totals.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first }),
                scale: HeatScale(values: totals.map(\.listened)),
                today: today,
                calendar: calendar,
                selection: .constant(today)
            )
            .padding(Spacing.m)
        }
    }
}
#endif
