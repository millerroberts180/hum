import Foundation
@testable import HumCore

/// A fixed calendar, clock, and listen builder for history tests.
enum HistoryFixtures {
    /// Gregorian, UTC, US English, weeks starting Sunday.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }()

    /// Tuesday, November 4, 2025, 3:00 PM UTC.
    static let now = date(2025, 11, 4, 15)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func daysAgo(_ days: Double, from date: Date = now) -> Date {
        date.addingTimeInterval(-days * 86_400)
    }

    static func listen(
        _ title: String = "Song",
        artist: String = "Artist",
        album: String = "Album",
        at startedAt: Date,
        listened: TimeInterval = 200,
        duration: TimeInterval? = 200,
        ending: ListenEnding? = nil,
        source: SourceID = .demo,
        context: PlaybackContext? = nil,
        trackID: String? = nil
    ) -> Listen {
        let resolvedEnding = ending ?? PlayRules.ending(listened: listened, duration: duration, exit: .changedTrack, wasPlaying: true)
        return Listen(
            trackID: TrackID(trackID ?? "t:" + title),
            title: title,
            artist: artist,
            album: album,
            source: source,
            context: context,
            startedAt: startedAt,
            listened: listened,
            duration: duration,
            ending: resolvedEnding,
            counts: PlayRules.counts(listened: listened, duration: duration)
        )
    }

    /// `count` full plays of one song, `spacing` seconds apart, ending at `last`.
    static func plays(
        _ title: String = "Song",
        artist: String = "Artist",
        count: Int,
        endingAt last: Date,
        spacing: TimeInterval = 86_400
    ) -> [Listen] {
        (0 ..< count).map { index in
            listen(title, artist: artist, at: last.addingTimeInterval(-Double(count - 1 - index) * spacing))
        }
    }

    static func temporaryURL(_ name: String = "History.sqlite") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hum-history-tests-" + UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }
}
