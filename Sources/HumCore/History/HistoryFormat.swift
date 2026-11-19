import Foundation

/// How history numbers and dates read in insight sentences. Uses the calendar's
/// time zone and locale so tests can pin both.
public struct HistoryFormat: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private var locale: Locale { calendar.locale ?? .current }

    private func style() -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// "Nov 4", or "Nov 4, 2025" outside the year of `now`.
    public func day(_ date: Date, now: Date = .now) -> String {
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(style().month(.abbreviated).day())
        }
        return date.formatted(style().month(.abbreviated).day().year())
    }

    /// "today", "yesterday", "Tuesday" within the week, otherwise `day(_:)`.
    public func relativeDay(_ date: Date, now: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2...6: return weekday(date)
        default: return day(date, now: now)
        }
    }

    /// "Tuesday".
    public func weekday(_ date: Date) -> String {
        date.formatted(style().weekday(.wide))
    }

    /// "2:14 PM".
    public func time(_ date: Date) -> String {
        date.formatted(style().hour().minute())
    }

    /// "Nov 4 – Nov 10".
    public func range(_ start: Date, _ end: Date, now: Date = .now) -> String {
        day(start, now: now) + " – " + day(end, now: now)
    }

    /// "1 hr 11 min", "45 min", "40 sec". Rounded to the minute past a minute.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        if total < 60 { return "\(Int(total.rounded())) sec" }
        let minutes = Int((total / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// How long a session has run, to start its stat line: its duration, or,
    /// under a minute, "Just started" while it goes on and "Under 1 min" once
    /// it's over, rather than a count of seconds.
    public static func sessionLength(_ seconds: TimeInterval, isOngoing: Bool) -> String {
        guard seconds < 60 else { return duration(seconds) }
        return isOngoing ? "Just started" : "Under 1 min"
    }

    /// "1st", "2nd", "11th", "23rd".
    public static func ordinal(_ number: Int) -> String {
        let suffix: String
        switch (number % 100, number % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }

    /// "1 play", "2 plays".
    public static func count(_ number: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(number.formatted()) " + (number == 1 ? singular : plural ?? singular + "s")
    }

    /// "71%".
    public static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// Where numbers come from: "tracked by Hum from Spotify and Music".
    public static func source(_ sources: Set<SourceID>) -> String {
        guard let list = names(sources) else { return "tracked by Hum on this Mac" }
        return "tracked by Hum from " + list
    }

    /// Where numbers come from, imported history included: "tracked by Hum from
    /// Music, plus imported from Spotify".
    public static func source(_ provenance: HistoryProvenance) -> String {
        var parts: [String] = []
        if !provenance.tracked.isEmpty || (provenance.imported.isEmpty && provenance.service.isEmpty) {
            parts.append(source(provenance.tracked))
        }
        if let list = names(provenance.imported) {
            parts.append("imported from " + list)
        }
        if let list = names(provenance.service) {
            parts.append("from " + list)
        }
        return parts.joined(separator: ", plus ")
    }

    /// "Spotify", "Music and Spotify", or `nil` for none.
    static func names(_ sources: Set<SourceID>) -> String? {
        let names = Set(sources.map(sourceName)).sorted()
        guard let last = names.last else { return nil }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }

    static func sourceName(_ source: SourceID) -> String {
        switch source {
        case .spotifyApp: "Spotify"
        case .musicApp: "Music"
        case .demo: "the demo player"
        default: source.rawValue
        }
    }
}
