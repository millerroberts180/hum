import Foundation

/// Five steps for the calendar: none, then four levels split at the quartiles
/// of the days that had any listening, so a light listener's busiest days still
/// read as busy.
public struct HeatScale: Equatable, Sendable {
    /// Listening above `bounds[i]` is at least level `i + 2`.
    public var bounds: [TimeInterval]

    public static let levels = 5

    public init(values: [TimeInterval]) {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else {
            bounds = []
            return
        }
        bounds = [0.25, 0.5, 0.75].map { quantile in
            sorted[Int((Double(sorted.count - 1) * quantile).rounded())]
        }
    }

    /// 0 for no listening, otherwise 1 through 4.
    public func level(_ listened: TimeInterval) -> Int {
        guard listened > 0 else { return 0 }
        return 1 + bounds.count { listened > $0 }
    }
}

/// One month of the heat calendar, laid out in weeks.
public struct CalendarMonth: Identifiable, Hashable, Sendable {
    public var id: Date { start }
    /// Midnight on the first of the month.
    public var start: Date
    /// Rows of seven days starting on the calendar's first weekday. Days outside
    /// the month are nil.
    public var weeks: [[Date?]]

    public init(start: Date, weeks: [[Date?]]) {
        self.start = start
        self.weeks = weeks
    }

    /// The month containing `date`.
    public static func containing(_ date: Date, calendar: Calendar) -> CalendarMonth? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        let first = interval.start
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        var day = first
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        days += Array(repeating: nil, count: (7 - days.count % 7) % 7)
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0 ..< $0 + 7]) }
        return CalendarMonth(start: first, weeks: weeks)
    }

    /// `count` months ending with the one containing `end`, oldest first.
    public static func months(endingAt end: Date, count: Int, calendar: Calendar) -> [CalendarMonth] {
        (0 ..< max(0, count)).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: end).flatMap { containing($0, calendar: calendar) }
        }
    }

    /// Weekday initials in display order, such as "S M T W T F S".
    public static func weekdayInitials(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0 ..< 7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}
