import Foundation

/// A week of listening on one page: time, plays, the top artist, the most
/// repeated song, a discovery, a one-line takeaway, and factual milestones.
public struct WeekReceipt: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var name: String
        public var detail: String
        public var plays: Int

        public init(name: String, detail: String, plays: Int) {
            self.name = name
            self.detail = detail
            self.plays = plays
        }
    }

    public var start: Date
    public var end: Date
    public var listened: TimeInterval
    public var plays: Int
    public var songs: Int
    public var topArtist: Line?
    public var mostRepeated: Line?
    public var discovery: Line?
    public var takeaway: String
    public var milestones: [String]
    /// Listening per day, oldest first, one entry for every day in the range.
    public var days: [DayTotal]

    public init(
        start: Date,
        end: Date,
        listened: TimeInterval,
        plays: Int,
        songs: Int,
        topArtist: Line?,
        mostRepeated: Line?,
        discovery: Line?,
        takeaway: String,
        milestones: [String],
        days: [DayTotal]
    ) {
        self.start = start
        self.end = end
        self.listened = listened
        self.plays = plays
        self.songs = songs
        self.topArtist = topArtist
        self.mostRepeated = mostRepeated
        self.discovery = discovery
        self.takeaway = takeaway
        self.milestones = milestones
        self.days = days
    }

    static let totalMilestones = [100, 250, 500, 1_000, 2_500, 5_000, 10_000, 25_000]

    /// Build the receipt for `[start, end)`.
    ///
    /// - Parameters:
    ///   - listens: Every listen in the range.
    ///   - firstHeard: When each song in the range was first heard, ever.
    ///   - totalPlaysBefore: Counted plays before `start`.
    ///   - songPlaysBefore: Counted plays before `start`, per song.
    public static func make(
        start: Date,
        end: Date,
        listens: [Listen],
        firstHeard: [String: Date],
        totalPlaysBefore: Int,
        songPlaysBefore: [String: Int],
        calendar: Calendar
    ) -> WeekReceipt {
        let format = HistoryFormat(calendar: calendar)
        let ordered = listens.sorted { $0.startedAt < $1.startedAt }
        let plays = ordered.filter(\.counts)

        var artistPlays: [String: (name: String, plays: Int)] = [:]
        var songPlays: [String: (listen: Listen, plays: Int)] = [:]
        for play in plays {
            let artistKey = SongKey.normalize(play.artist)
            artistPlays[artistKey, default: (play.artist, 0)].plays += 1
            songPlays[play.songKey, default: (play, 0)].plays += 1
        }
        let topArtist = artistPlays.values
            .max { $0.plays != $1.plays ? $0.plays < $1.plays : $0.name > $1.name }
            .map { Line(name: $0.name, detail: HistoryFormat.count($0.plays, "play"), plays: $0.plays) }
        let mostRepeated = songPlays.values
            .filter { $0.plays >= 2 }
            .max { $0.plays != $1.plays ? $0.plays < $1.plays : $0.listen.title > $1.listen.title }
            .map { Line(name: $0.listen.title, detail: $0.listen.artist + " · " + HistoryFormat.count($0.plays, "play"), plays: $0.plays) }
        let discovery = songPlays.values
            .filter { entry in (firstHeard[entry.listen.songKey] ?? .distantPast) >= start }
            .max { $0.plays != $1.plays ? $0.plays < $1.plays : $0.listen.title > $1.listen.title }
            .map { entry in
                let first = firstHeard[entry.listen.songKey] ?? entry.listen.startedAt
                return Line(
                    name: entry.listen.title,
                    detail: entry.listen.artist + " · first heard \(format.relativeDay(first, now: end))",
                    plays: entry.plays
                )
            }

        // Milestones: facts reached this week, never streaks.
        var milestones: [String] = []
        for threshold in totalMilestones where totalPlaysBefore < threshold && totalPlaysBefore + plays.count >= threshold {
            let play = plays[threshold - totalPlaysBefore - 1]
            milestones.append("Your \(threshold.formatted())th play tracked by Hum, \(format.relativeDay(play.startedAt, now: end))")
        }
        var running = songPlaysBefore
        for play in plays {
            let before = running[play.songKey, default: 0]
            running[play.songKey] = before + 1
            if InsightEngine.milestones.contains(before + 1), before + 1 >= 25 {
                milestones.append("\(play.title) reached \(before + 1) plays \(format.relativeDay(play.startedAt, now: end))")
            }
        }

        // One entry per day, so the chart shows quiet days too.
        var days: [DayTotal] = []
        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
            let inDay = ordered.filter { $0.startedAt >= cursor && $0.startedAt < next }
            days.append(DayTotal(day: cursor, listened: inDay.reduce(0) { $0 + $1.listened }, plays: inDay.count(where: \.counts)))
            cursor = next
        }

        return WeekReceipt(
            start: start,
            end: end,
            listened: ordered.reduce(0) { $0 + $1.listened },
            plays: plays.count,
            songs: Set(plays.map(\.songKey)).count,
            topArtist: topArtist,
            mostRepeated: mostRepeated,
            discovery: discovery,
            takeaway: takeaway(plays: plays, firstHeard: firstHeard, start: start, calendar: calendar),
            milestones: milestones,
            days: days
        )
    }

    /// "Mostly evenings, mostly songs you knew."
    static func takeaway(plays: [Listen], firstHeard: [String: Date], start: Date, calendar: Calendar) -> String {
        guard plays.count >= 5 else {
            return plays.isEmpty ? "A quiet week so far." : "A light week so far."
        }
        var byTime: [TimeOfDay: Int] = [:]
        for play in plays {
            byTime[TimeOfDay(hour: calendar.component(.hour, from: play.startedAt)), default: 0] += 1
        }
        let songs = Set(plays.map(\.songKey))
        let fresh = songs.count { (firstHeard[$0] ?? .distantPast) >= start }
        let freshShare = Double(fresh) / Double(max(1, songs.count))
        let familiarity = freshShare >= 0.5 ? "mostly new songs" : (freshShare >= 0.2 ? "some new songs among old ones" : "mostly songs you knew")
        guard let (time, count) = byTime.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }),
              Double(count) / Double(plays.count) >= 0.4
        else {
            return "Spread across the day, " + familiarity + "."
        }
        let when: String = switch time {
        case .morning: "Mostly mornings"
        case .afternoon: "Mostly afternoons"
        case .evening: "Mostly evenings"
        case .night: "Mostly late nights"
        }
        return when + ", " + familiarity + "."
    }
}

extension HistoryStore {
    /// The receipt for the calendar week containing `now`, up to `now`.
    public func weekReceipt(now: Date, calendar: Calendar) throws -> WeekReceipt {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let end = now
        let listens = try listens(from: start, to: end)
        let keys = Set(listens.map(\.songKey))
        let before = try playCounts(from: .distantPast, to: start)
        return WeekReceipt.make(
            start: start,
            end: end,
            listens: listens,
            firstHeard: try firstHeard(songKeys: keys),
            totalPlaysBefore: before.values.reduce(0, +),
            songPlaysBefore: before.filter { keys.contains($0.key) },
            calendar: calendar
        )
    }
}
