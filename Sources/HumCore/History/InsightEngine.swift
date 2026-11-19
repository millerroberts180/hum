import Foundation

/// Turns history into candidate insights, each with a relevance score. Pure: the
/// same history, clock, and calendar always give the same insights.
///
/// Rules of voice: plain facts with their range and source, no streaks, no guilt,
/// and no number more precise than what Hum actually saw.
public enum InsightEngine {
    /// What the song insights are computed from.
    public struct SongInput: Sendable {
        public var track: Track
        /// Every stored listen of the song, oldest first. The listen in progress
        /// is not included.
        public var listens: [Listen]
        /// Counted plays per song from the start of this calendar month.
        public var monthPlayCounts: [String: Int]
        public var trackedSince: Date?
        /// The span imported history covers, if any was imported.
        public var importedRange: ClosedRange<Date>?
        public var now: Date

        public init(
            track: Track,
            listens: [Listen],
            monthPlayCounts: [String: Int],
            trackedSince: Date?,
            importedRange: ClosedRange<Date>? = nil,
            now: Date
        ) {
            self.track = track
            self.listens = listens
            self.monthPlayCounts = monthPlayCounts
            self.trackedSince = trackedSince
            self.importedRange = importedRange
            self.now = now
        }

        /// When history begins: Hum's tracking or the imported history,
        /// whichever reaches back further.
        var historySince: Date? {
            [trackedSince, importedRange?.lowerBound].compactMap(\.self).min()
        }

        /// Whether history begins with the imported part.
        var beginsImported: Bool {
            guard let imported = importedRange?.lowerBound else { return false }
            return trackedSince.map { imported < $0 } ?? true
        }

        public var songKey: String { SongKey.make(artist: track.artist, title: track.title) }
    }

    // MARK: Thresholds

    static let milestones = [10, 25, 50, 100, 250, 500, 1000]
    static let rediscoverGap: TimeInterval = 60 * 86_400
    static let repeatWindow: TimeInterval = 3 * 86_400
    static let repeatPlays = 5
    static let patternPlays = 5
    static let patternShare = 0.6
    static let weekdayShare = 0.45
    static let rankMaximum = 10
    static let rankMinimumMonthPlays = 20
    static let rankMinimumMonthSongs = 10
    static let rankMinimumSongPlays = 3
    static let favoriteMonths = 4
    static let favoritePlays = 8
    static let longestMinimum: TimeInterval = 45 * 60
    static let longestMinimumSessions = 5

    // MARK: Songs

    public static func songInsights(_ input: SongInput, calendar: Calendar) -> [Insight] {
        let format = HistoryFormat(calendar: calendar)
        let now = input.now
        let listens = input.listens.sorted { $0.startedAt < $1.startedAt }
        let plays = listens.filter(\.counts)
        let since = input.historySince ?? listens.first?.startedAt ?? now
        let sinceText = format.day(since, now: now)
        let source = historySource(input, format: format)

        guard !plays.isEmpty else {
            return [coldStart(earlierListens: listens.count, source: source)]
        }

        var insights: [Insight] = []
        if plays.count >= 2 {
            insights.append(togetherTime(listens: listens, plays: plays, sinceText: sinceText, format: format, now: now))
        }
        insights.append(firstAndLast(plays: plays, since: since, beginsImported: input.beginsImported, format: format, now: now))
        if let pattern = pattern(plays: plays, sinceText: sinceText, calendar: calendar) {
            insights.append(pattern)
        }
        if let relationship = relationship(
            listens: listens, plays: plays, since: since, history: historyPhrase(input), format: format, calendar: calendar, now: now
        ) {
            insights.append(relationship)
        }
        if let rank = rank(
            songKey: input.songKey, counts: input.monthPlayCounts, importedRange: input.importedRange, format: format, calendar: calendar, now: now
        ) {
            insights.append(rank)
        }
        if let milestone = milestone(plays: plays, sinceText: sinceText, format: format, now: now) {
            insights.append(milestone)
        }
        return ranked(insights)
    }

    /// Where a set of listens came from: "tracked by Hum", "imported", or
    /// "tracked by Hum and imported". Echo and the widgets show these, so they
    /// never name the music app (DESIGN.md §10).
    static func provenance(_ listens: some Sequence<Listen>) -> String {
        var imported = false
        var tracked = false
        for listen in listens {
            if listen.origin == .imported { imported = true } else { tracked = true }
        }
        guard imported else { return "tracked by Hum" }
        return tracked ? "tracked by Hum and imported" : "imported"
    }

    /// Where the whole history came from, for claims about everything in it.
    static func historyPhrase(_ input: SongInput) -> String {
        guard input.importedRange != nil else { return "tracked by Hum" }
        return input.trackedSince == nil ? "imported" : "tracked by Hum and imported"
    }

    /// The range and source of everything history knows: "Tracked by Hum since
    /// Nov 4.", with the imported part's reach when there is one.
    static func historySource(_ input: SongInput, format: HistoryFormat) -> String {
        let now = input.now
        guard let imported = input.importedRange?.lowerBound else {
            let since = input.trackedSince ?? input.listens.map(\.startedAt).min() ?? now
            return "Tracked by Hum since \(format.day(since, now: now))."
        }
        guard let tracked = input.trackedSince else {
            return "Imported history back to \(format.day(imported, now: now))."
        }
        return "Tracked by Hum since \(format.day(tracked, now: now)), with imported history back to \(format.day(imported, now: now))."
    }

    static func coldStart(earlierListens: Int, source: String) -> Insight {
        if earlierListens == 0 {
            return Insight(
                kind: .firstTime,
                title: "New to Hum",
                value: nil,
                label: "no plays yet",
                sentence: "First time Hum has heard this song",
                explanation: source,
                relevance: 0.5
            )
        }
        return Insight(
            kind: .firstTime,
            title: "New to Hum",
            value: nil,
            label: HistoryFormat.count(earlierListens, "short listen") + " before",
            sentence: "Heard briefly before, not yet a full play",
            // The range and source first, so a card that cuts the line short
            // keeps them (§6.5).
            explanation: source + " A play counts after 30 seconds, once you’ve heard half the song or 4 minutes of it.",
            relevance: 0.45
        )
    }

    static func togetherTime(listens: [Listen], plays: [Listen], sinceText: String, format: HistoryFormat, now: Date) -> Insight {
        let total = listens.reduce(0) { $0 + $1.listened }
        let completed = listens.count { $0.ending == .completed }
        var details: [String] = []
        if completed > 0 {
            details.append("Played to the end " + HistoryFormat.count(completed, "time"))
        }
        details.append("About \(HistoryFormat.duration(total / Double(listens.count))) per listen")
        if let first = plays.first {
            details.append("First play counted \(format.day(first.startedAt, now: now))")
        }
        return Insight(
            kind: .togetherTime,
            title: "Time together",
            value: plays.count.formatted(),
            label: togetherLabel(plays: plays.count, song: listens.last?.title ?? "", listened: total),
            explanation: "Counted from \(sinceText) to today, \(provenance(listens)).",
            details: details,
            relevance: 0.35 + min(Double(plays.count), 60) / 150
        )
    }

    /// What the play count counts, naming the song, since Echo's card doesn't
    /// show its title: "plays of Low Tide Radio · 10 hr 23 min".
    static func togetherLabel(plays: Int, song: String, listened: TimeInterval) -> String {
        let counted = plays == 1 ? "play" : "plays"
        let named = song.isEmpty ? counted : counted + " of " + song
        return named + " · " + HistoryFormat.duration(listened)
    }

    static func firstAndLast(plays: [Listen], since: Date, beginsImported: Bool = false, format: HistoryFormat, now: Date) -> Insight {
        let first = plays[0].startedAt
        let last = plays[plays.count - 1].startedAt
        // A first play right at the start of tracking says nothing about when the
        // song was really first heard.
        let nearStart = first.timeIntervalSince(since) < 3 * 86_400
        let spanDays = Int(now.timeIntervalSince(first) / 86_400)
        let sentence: String?
        let explanation: String
        if nearStart, beginsImported {
            sentence = "With you since your imported history begins"
            explanation = "Imported history begins on \(format.day(since, now: now)), so the first listen may be earlier."
        } else if nearStart {
            sentence = "With you since Hum started tracking"
            explanation = "Hum began tracking on \(format.day(since, now: now)), so the first listen may be earlier."
        } else {
            sentence = plays.count == 1 ? "Heard once before, \(format.relativeDay(last, now: now))" : nil
            explanation = HistoryFormat.count(plays.count, "play") + " from \(format.day(first, now: now)) to \(format.relativeDay(last, now: now)), \(provenance(plays))."
        }
        return Insight(
            kind: .firstAndLast,
            title: "First and last heard",
            value: format.day(first, now: now),
            label: "first · last \(format.relativeDay(last, now: now))",
            sentence: sentence,
            explanation: explanation,
            details: [HistoryFormat.count(plays.count, "play") + " so far"],
            timeline: MiniTimelineData(plays: plays.map(\.startedAt), from: since, to: now, format: format),
            relevance: plays.count == 1 ? 0.55 : 0.4 + Double(min(spanDays, 180)) / 600
        )
    }

    static func pattern(plays: [Listen], sinceText: String, calendar: Calendar) -> Insight? {
        guard plays.count >= patternPlays else { return nil }
        let total = Double(plays.count)
        var byTime: [TimeOfDay: Int] = [:]
        var byWeekday: [Int: Int] = [:]
        for play in plays {
            byTime[TimeOfDay(hour: calendar.component(.hour, from: play.startedAt)), default: 0] += 1
            byWeekday[calendar.component(.weekday, from: play.startedAt), default: 0] += 1
        }
        if let (time, count) = byTime.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }),
           Double(count) / total >= patternShare {
            let share = Double(count) / total
            return Insight(
                kind: .pattern,
                title: "Listening pattern",
                value: HistoryFormat.percent(share),
                label: "of plays \(time.phrase)",
                sentence: "Usually played \(time.phrase)",
                // The range and source first, so a card that cuts the line
                // short keeps them (§6.5).
                explanation: "Counted since \(sinceText), \(provenance(plays)). \(count) of \(plays.count) plays were between \(time.span).",
                relevance: 0.45 + (share - patternShare)
            )
        }
        if let (weekday, count) = byWeekday.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }),
           count >= 4, Double(count) / total >= weekdayShare {
            let share = Double(count) / total
            let name = calendar.weekdaySymbols[weekday - 1]
            return Insight(
                kind: .pattern,
                title: "Listening pattern",
                value: HistoryFormat.percent(share),
                label: "of plays on \(name)s",
                sentence: "Usually a \(name) song",
                explanation: "Counted since \(sinceText), \(provenance(plays)). \(count) of \(plays.count) plays were on a \(name).",
                relevance: 0.45 + (share - weekdayShare)
            )
        }
        return nil
    }

    static func relationship(
        listens: [Listen],
        plays: [Listen],
        since: Date,
        history: String = "tracked by Hum",
        format: HistoryFormat,
        calendar: Calendar,
        now: Date
    ) -> Insight? {
        let last = plays[plays.count - 1].startedAt
        let title = "Relationship"

        // Back after a long time away, starting now.
        let away = now.timeIntervalSince(last)
        if away >= rediscoverGap {
            let days = Int(away / 86_400)
            return Insight(
                kind: .relationship,
                title: title,
                value: days.formatted(),
                label: "days since the last play",
                sentence: "Back after \(days) days",
                explanation: "Last played \(format.day(last, now: now)), \(provenance(plays.suffix(1))).",
                relevance: 0.85
            )
        }
        // Came back this week after a long gap: the first play of the recent run
        // followed months without one.
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        if let back = plays.firstIndex(where: { $0.startedAt >= weekStart }), back > 0 {
            let previous = plays[back - 1].startedAt
            let returned = plays[back].startedAt
            let gap = returned.timeIntervalSince(previous)
            if gap >= rediscoverGap {
                let days = Int(gap / 86_400)
                let since = plays.count - back
                return Insight(
                    kind: .relationship,
                    title: title,
                    value: days.formatted(),
                    label: "days away before \(format.relativeDay(returned, now: now))",
                    sentence: "Rediscovered after \(days) days",
                    explanation: "Played \(format.day(previous, now: now)), then not again until \(format.relativeDay(returned, now: now)). "
                        + sentence(provenance(plays[(back - 1)...])) + ".",
                    details: [HistoryFormat.count(since, "play") + " since coming back"],
                    relevance: 0.75
                )
            }
        }
        // On repeat: many plays in a few days. Never framed as a streak.
        let windowStart = now.addingTimeInterval(-repeatWindow)
        let recentPlays = plays.count { $0.startedAt >= windowStart }
        if recentPlays >= repeatPlays {
            return Insight(
                kind: .relationship,
                title: title,
                value: recentPlays.formatted(),
                label: "plays in 3 days",
                sentence: "On repeat lately",
                explanation: "Plays from \(format.day(windowStart, now: now)) to today, \(provenance(plays.filter { $0.startedAt >= windowStart })).",
                relevance: 0.8
            )
        }
        // New: first heard this week, and not just because tracking began.
        let first = listens[0].startedAt
        if now.timeIntervalSince(first) <= 7 * 86_400, first.timeIntervalSince(since) >= 7 * 86_400 {
            return Insight(
                kind: .relationship,
                title: title,
                value: nil,
                label: "first heard \(format.relativeDay(first, now: now))",
                sentence: "New to Hum this week",
                explanation: "No earlier listens since \(format.day(since, now: now)), \(history).",
                relevance: 0.65
            )
        }
        // Often skipped lately: most of the recent listens ended early.
        let recentListens = listens.filter { now.timeIntervalSince($0.startedAt) <= 30 * 86_400 }.suffix(8)
        let skips = recentListens.count(where: \.wasSkipped)
        if skips >= 3, skips * 2 >= recentListens.count, let oldest = recentListens.first {
            return Insight(
                kind: .relationship,
                title: title,
                value: "\(skips) of \(recentListens.count)",
                label: "recent listens skipped",
                sentence: "Often skipped lately",
                explanation: "Listens since \(format.day(oldest.startedAt, now: now)) that ended within 30 seconds, \(provenance(recentListens)).",
                relevance: 0.55
            )
        }
        // A quiet long-term favorite: plays spread across many months.
        let months = Set(plays.map { calendar.dateComponents([.year, .month], from: $0.startedAt) })
        if months.count >= favoriteMonths, plays.count >= favoritePlays {
            return Insight(
                kind: .relationship,
                title: title,
                value: months.count.formatted(),
                label: "different months with plays",
                sentence: "A long-term favorite",
                explanation: "Played in \(months.count) months since \(format.day(plays[0].startedAt, now: now)), \(provenance(plays)).",
                relevance: 0.6
            )
        }
        return nil
    }

    static func rank(
        songKey: String,
        counts: [String: Int],
        importedRange: ClosedRange<Date>? = nil,
        format: HistoryFormat,
        calendar: Calendar,
        now: Date
    ) -> Insight? {
        let total = counts.values.reduce(0, +)
        guard let mine = counts[songKey],
              mine >= rankMinimumSongPlays,
              total >= rankMinimumMonthPlays,
              counts.count >= rankMinimumMonthSongs
        else { return nil }
        let rank = 1 + counts.values.count { $0 > mine }
        guard rank <= rankMaximum else { return nil }
        let ties = counts.values.count { $0 == mine } - 1
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var details = ["\(mine) of \(total) plays this month"]
        if ties > 0 {
            details.append("Tied with " + HistoryFormat.count(ties, "other song"))
        }
        return Insight(
            kind: .rank,
            title: "This month",
            value: HistoryFormat.ordinal(rank),
            label: "most played",
            sentence: rank == 1 ? "Your most-played song this month" : "Your \(HistoryFormat.ordinal(rank))-most-played song this month",
            explanation: "Ranked by plays from \(format.day(monthStart, now: now)) to today, "
                + (importedRange.map { $0.upperBound >= monthStart } == true ? "tracked by Hum and imported." : "tracked by Hum."),
            details: details,
            relevance: 0.9 - Double(rank - 1) * 0.04
        )
    }

    static func milestone(plays: [Listen], sinceText: String, format: HistoryFormat, now: Date) -> Insight? {
        guard let reached = milestones.last(where: { $0 <= plays.count }) else { return nil }
        let date = plays[reached - 1].startedAt
        guard now.timeIntervalSince(date) <= 7 * 86_400 else { return nil }
        return Insight(
            kind: .milestone,
            title: "Milestone",
            value: reached.formatted(),
            label: "plays",
            sentence: "Reached \(reached) plays \(format.relativeDay(date, now: now))",
            explanation: "Counted since \(sinceText), \(provenance(plays)).",
            relevance: 0.7
        )
    }

    // MARK: Sessions

    /// Insights about the session in progress. `priorLengths` are the listening
    /// times of earlier sessions.
    public static func sessionInsights(
        _ session: ListeningSession,
        priorLengths: [TimeInterval],
        trackedSince: Date?,
        now: Date,
        calendar: Calendar
    ) -> [Insight] {
        let format = HistoryFormat(calendar: calendar)
        let sinceText = format.day(trackedSince ?? session.start, now: now)
        let startText = format.relativeDay(session.start, now: now) == "today"
            ? format.time(session.start)
            : format.time(session.start) + " " + format.relativeDay(session.start, now: now)
        let range = "This session since \(startText), tracked by Hum."
        var insights: [Insight] = []

        let counts = HistoryFormat.count(session.songCount, "song") + " · " + HistoryFormat.count(session.artistCount, "artist")
        let hasLength = session.listened >= 60
        insights.append(Insight(
            kind: .sessionSummary,
            title: session.chapterName,
            value: hasLength ? HistoryFormat.duration(session.listened) : nil,
            label: hasLength ? counts : HistoryFormat.sessionLength(session.listened, isOngoing: session.isOngoing).lowercased() + " · " + counts,
            explanation: range + " A gap of more than 30 minutes starts a new one.",
            relevance: 0.3
        ))

        if priorLengths.count >= longestMinimumSessions,
           let longest = priorLengths.max(),
           session.listened > longest,
           session.listened >= longestMinimum {
            insights.append(Insight(
                kind: .sessionLongest,
                title: "Longest session",
                value: HistoryFormat.duration(session.listened),
                label: "longest since \(sinceText)",
                sentence: "Your longest session since \(sinceText)",
                explanation: "Compared with \(priorLengths.count.formatted()) earlier sessions since \(sinceText), tracked by Hum.",
                details: ["Previous longest: \(HistoryFormat.duration(longest))"],
                relevance: 0.85
            ))
        }

        if let top = session.returns.first {
            let several = session.returns.count >= 2
            insights.append(Insight(
                kind: .sessionReturns,
                title: "Returns",
                value: several ? session.returns.count.formatted() : top.times.formatted(),
                label: several ? "songs came back" : "plays this session",
                sentence: top.times >= 3 ? "\(top.title) keeps coming back" : (several ? "A few songs came back" : "\(top.title) came back"),
                explanation: range,
                details: session.returns.prefix(3).map { "\($0.title): \($0.times) times" },
                relevance: top.times >= 3 ? 0.6 : (several ? 0.5 : 0.4)
            ))
        }

        if session.songCount >= 4 {
            let familiarShare = Double(session.familiarCount) / Double(session.songCount)
            let value: String
            let label: String
            let sentence: String
            var relevance = 0.45
            if familiarShare >= 0.75 {
                value = HistoryFormat.percent(familiarShare)
                label = "heard before"
                sentence = familiarShare == 1 ? "Every song heard before" : "Mostly familiar songs"
                relevance += 0.05
            } else if familiarShare <= 0.25 {
                value = HistoryFormat.percent(1 - familiarShare)
                label = "new to Hum"
                sentence = familiarShare == 0 ? "Every song new to Hum" : "Mostly songs new to Hum"
                relevance += 0.1
            } else {
                value = "\(session.newCount) of \(session.songCount)"
                label = "songs new to Hum"
                sentence = "A mix of familiar and new"
            }
            var details = ["\(session.familiarCount) familiar, \(session.newCount) new"]
            if session.repeatCount == 0, session.songCount >= 6 {
                details.append("No repeats: every song different")
            } else if session.repeatCount > 0 {
                details.append(HistoryFormat.count(session.repeatCount, "repeat"))
            }
            insights.append(Insight(
                kind: .sessionBalance,
                title: "Familiar and new",
                value: value,
                label: label,
                sentence: sentence,
                explanation: "Heard by Hum between \(sinceText) and this session.",
                details: details,
                relevance: relevance
            ))
        }

        if session.knownContextCount >= 3, let top = session.sourceMix.first,
           top.listens * 2 >= session.knownContextCount {
            // Listens, not songs, so it never reads against the ribbon's song
            // count; and one plain sentence with its range (§10).
            let isAll = top.listens == session.listens.count
            let unsaid = session.listens.count - session.knownContextCount
            var details = session.sourceMix.prefix(3).map { "\($0.displayName): " + HistoryFormat.count($0.listens, "listen") }
            if unsaid > 0 {
                details.append(HistoryFormat.count(unsaid, "other listen") + " didn’t say where " + (unsaid == 1 ? "it" : "they") + " came from")
            }
            insights.append(Insight(
                kind: .sessionSources,
                title: "Where it came from",
                value: "\(top.listens) of \(session.knownContextCount)",
                label: "listens from \(top.displayName)",
                sentence: (isAll ? "All from " : "Mostly from ") + top.displayName,
                explanation: (isAll ? "All" : "\(top.listens) of \(session.knownContextCount) listens")
                    + " from \(top.displayName) since \(startText), tracked by Hum.",
                details: details,
                relevance: 0.4
            ))
        }

        return ranked(insights)
    }

    /// "Tracked by Hum" from "tracked by Hum", to start a sentence.
    static func sentence(_ phrase: String) -> String {
        phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    // MARK: Choosing

    /// Most relevant first; ties keep a fixed order so the UI doesn't flicker.
    static func ranked(_ insights: [Insight]) -> [Insight] {
        let order = Dictionary(uniqueKeysWithValues: Insight.Kind.allCases.enumerated().map { ($1, $0) })
        return insights.sorted {
            $0.relevance != $1.relevance ? $0.relevance > $1.relevance : order[$0.kind, default: 0] < order[$1.kind, default: 0]
        }
    }
}
