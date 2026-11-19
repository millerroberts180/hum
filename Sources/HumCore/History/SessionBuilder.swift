import Foundation

/// Splits listening into sessions and derives what each one was like. Pure.
public enum SessionBuilder {
    /// A silence longer than this starts a new session.
    public static let gap: TimeInterval = 30 * 60

    /// Group listens (any order) into sessions, oldest first.
    public static func split(_ listens: [Listen], gap: TimeInterval = gap) -> [[Listen]] {
        var groups: [[Listen]] = []
        var lastEnd: Date?
        for listen in listens.sorted(by: { $0.startedAt < $1.startedAt }) {
            if let lastEnd, listen.startedAt.timeIntervalSince(lastEnd) <= gap {
                groups[groups.count - 1].append(listen)
            } else {
                groups.append([listen])
            }
            lastEnd = max(lastEnd ?? listen.endedAt, listen.endedAt)
        }
        return groups
    }

    /// Seconds heard in each session described by `spans`, oldest first.
    public static func sessionLengths(_ spans: [ListenSpan], gap: TimeInterval = gap) -> [TimeInterval] {
        var lengths: [TimeInterval] = []
        var lastEnd: Date?
        for span in spans.sorted(by: { $0.startedAt < $1.startedAt }) {
            if let lastEnd, span.startedAt.timeIntervalSince(lastEnd) <= gap {
                lengths[lengths.count - 1] += span.listened
            } else {
                lengths.append(span.listened)
            }
            lastEnd = max(lastEnd ?? span.endedAt, span.endedAt)
        }
        return lengths
    }

    /// The session still going at `now`: the newest one, if it ended within `gap`
    /// or its last listen is in progress.
    public static func current(
        _ listens: [Listen],
        inProgress: Listen?,
        firstHeard: [String: Date],
        now: Date,
        calendar: Calendar
    ) -> ListeningSession? {
        var all = listens
        if let inProgress { all.append(inProgress) }
        guard let newest = split(all).last, let last = newest.last else { return nil }
        let ongoing = inProgress.map(newest.contains) ?? false
        guard ongoing || now.timeIntervalSince(last.endedAt) <= gap else { return nil }
        return session(newest, firstHeard: firstHeard, isOngoing: ongoing, calendar: calendar)
    }

    /// Describe one session. `firstHeard` gives the first listen of each song ever;
    /// songs missing from it are treated as first heard here.
    public static func session(
        _ listens: [Listen],
        firstHeard: [String: Date],
        isOngoing: Bool = false,
        calendar: Calendar
    ) -> ListeningSession {
        let ordered = listens.sorted { $0.startedAt < $1.startedAt }
        let start = ordered.first?.startedAt ?? .distantPast
        let end = ordered.map(\.endedAt).max() ?? start

        var songOrder: [String] = []
        var songTimes: [String: Int] = [:]
        // Only listens that count as plays make a song come back.
        var songPlays: [String: Int] = [:]
        var songInfo: [String: Listen] = [:]
        var artists = Set<String>()
        var trail: [TrailStop] = []
        var mix: [String: SourceShare] = [:]
        var mixOrder: [String] = []
        var known = 0

        for listen in ordered {
            if songTimes[listen.songKey] == nil {
                songOrder.append(listen.songKey)
                songInfo[listen.songKey] = listen
            }
            songTimes[listen.songKey, default: 0] += 1
            if listen.counts { songPlays[listen.songKey, default: 0] += 1 }
            artists.insert(SongKey.normalize(listen.artist))

            let album = listen.album.isEmpty ? listen.title : listen.album
            if let lastStop = trail.last, lastStop.album == album, lastStop.artist == listen.artist {
                trail[trail.count - 1].listens += 1
            } else {
                trail.append(TrailStop(
                    id: trail.count,
                    album: album,
                    artist: listen.artist,
                    title: listen.title,
                    trackID: listen.trackID,
                    artworkKey: listen.artworkKey,
                    source: listen.source,
                    listens: 1
                ))
            }

            if let context = listen.context {
                known += 1
                let key = context.kind.rawValue + "\u{1F}" + (context.name ?? "")
                if mix[key] == nil { mixOrder.append(key) }
                mix[key, default: SourceShare(kind: context.kind, name: context.name, listens: 0)].listens += 1
            }
        }

        let returns = songOrder.compactMap { key -> SongReturn? in
            guard let times = songPlays[key], times > 1, let info = songInfo[key] else { return nil }
            return SongReturn(songKey: key, title: info.title, artist: info.artist, times: times)
        }
        .sorted { $0.times > $1.times }

        let newCount = songOrder.filter { key in
            guard let first = firstHeard[key] else { return true }
            return first >= start
        }.count

        // Stable order for ties: the context that came up first.
        let sourceMix = mixOrder.compactMap { mix[$0] }
            .enumerated()
            .sorted { $0.element.listens != $1.element.listens ? $0.element.listens > $1.element.listens : $0.offset < $1.offset }
            .map(\.element)

        let timeOfDay = TimeOfDay(hour: calendar.component(.hour, from: start))
        return ListeningSession(
            listens: ordered,
            start: start,
            end: end,
            listened: ordered.reduce(0) { $0 + $1.listened },
            songCount: songOrder.count,
            artistCount: artists.count,
            trail: trail,
            returns: returns,
            repeatCount: ordered.count - songOrder.count,
            familiarCount: songOrder.count - newCount,
            newCount: newCount,
            sourceMix: sourceMix,
            knownContextCount: known,
            chapterName: chapterName(start: start, timeOfDay: timeOfDay, calendar: calendar),
            timeOfDay: timeOfDay,
            isOngoing: isOngoing
        )
    }

    /// "Tuesday afternoon listening". Late-night sessions after midnight belong to
    /// the evening before, the way people talk about them.
    static func chapterName(start: Date, timeOfDay: TimeOfDay, calendar: Calendar) -> String {
        var day = start
        if timeOfDay == .night, calendar.component(.hour, from: start) < 5,
           let previous = calendar.date(byAdding: .day, value: -1, to: start) {
            day = previous
        }
        let weekday = HistoryFormat(calendar: calendar).weekday(day)
        return "\(weekday) \(timeOfDay.adjective) listening"
    }
}
