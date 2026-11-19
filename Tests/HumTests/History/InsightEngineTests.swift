import Foundation
@testable import HumCore
import Testing

@Suite("Insights")
struct InsightEngineTests {
    let calendar = HistoryFixtures.calendar
    let now = HistoryFixtures.now
    let track = Track(id: TrackID("t:Song"), title: "Song", artist: "Artist", album: "Album", duration: 200)

    func days(_ value: Double) -> Date { HistoryFixtures.daysAgo(value) }

    func insights(
        _ listens: [Listen],
        monthPlayCounts: [String: Int] = [:],
        trackedSince: Date? = HistoryFixtures.daysAgo(365)
    ) -> [Insight] {
        InsightEngine.songInsights(
            .init(track: track, listens: listens, monthPlayCounts: monthPlayCounts, trackedSince: trackedSince, now: now),
            calendar: calendar
        )
    }

    func insight(_ kind: Insight.Kind, in listens: [Listen], trackedSince: Date? = HistoryFixtures.daysAgo(365)) -> Insight? {
        insights(listens, trackedSince: trackedSince).first { $0.kind == kind }
    }

    func play(_ date: Date, listened: TimeInterval = 200) -> Listen {
        HistoryFixtures.listen("Song", at: date, listened: listened)
    }

    func skip(_ date: Date) -> Listen {
        HistoryFixtures.listen("Song", at: date, listened: 10)
    }

    // MARK: Cold start

    @Test func aSongHumHasNeverHeardSaysSo() throws {
        let only = try #require(insights([], trackedSince: nil).first)
        #expect(insights([], trackedSince: nil).count == 1)
        #expect(only.kind == .firstTime)
        #expect(only.value == nil)
        #expect(only.label == "no plays yet")
        #expect(only.sentence == "First time Hum has heard this song")
        #expect(only.explanation == "Tracked by Hum since Nov 4.")
    }

    @Test func shortListensAloneAreNotAPlay() throws {
        let result = insights([skip(days(3)), skip(days(2))])
        #expect(result.count == 1)
        let only = try #require(result.first)
        #expect(only.kind == .firstTime)
        #expect(only.label == "2 short listens before")
        // The range and source first, so a card that cuts the line keeps them.
        #expect(only.explanation.hasPrefix("Tracked by Hum since "))
        #expect(only.explanation.hasSuffix("A play counts after 30 seconds, once you’ve heard half the song or 4 minutes of it."))
    }

    // MARK: Song insights

    @Test func timeTogetherSaysWhatItCountsWithoutATitle() {
        #expect(InsightEngine.togetherLabel(plays: 1, song: "Low Tide Radio", listened: 3_780) == "play of Low Tide Radio · 1 hr 3 min")
        #expect(InsightEngine.togetherLabel(plays: 2, song: "", listened: 420) == "plays · 7 min")
    }

    @Test func timeTogetherNeedsTwoPlays() throws {
        #expect(insight(.togetherTime, in: [play(days(2))]) == nil)
        let together = try #require(insight(.togetherTime, in: [play(days(2)), play(days(1)), skip(days(1))]))
        #expect(together.value == "2")
        // It names the song, since Echo's card doesn't show the title.
        #expect(together.label == "plays of Song · 7 min")
        #expect(together.explanation == "Counted from Nov 4, 2024 to today, tracked by Hum.")
    }

    @Test func aFirstPlayAtTheStartOfTrackingIsCalledThat() throws {
        let start = days(40)
        let near = try #require(insight(.firstAndLast, in: [play(start.addingTimeInterval(3_600)), play(days(1))], trackedSince: start))
        #expect(near.sentence == "With you since Hum started tracking")
        #expect(near.explanation.contains("so the first listen may be earlier"))

        let far = try #require(insight(.firstAndLast, in: [play(days(10)), play(days(1))], trackedSince: start))
        #expect(far.sentence == nil)
        #expect(far.value == "Oct 25")
        #expect(far.explanation == "2 plays from Oct 25 to yesterday, tracked by Hum.")
        #expect(far.timeline?.marks.count == 2)
    }

    @Test func oneEarlierPlayIsMentioned() throws {
        let once = try #require(insight(.firstAndLast, in: [play(days(1))]))
        #expect(once.sentence == "Heard once before, yesterday")
    }

    @Test func aTimeOfDayPatternNeedsFivePlaysAndSixtyPercent() throws {
        let evenings = (1...3).map { play(HistoryFixtures.date(2025, 10, 20 + $0, 19)) }
        let mornings = (1...2).map { play(HistoryFixtures.date(2025, 10, 25 + $0, 8)) }
        let pattern = try #require(insight(.pattern, in: evenings + mornings))
        #expect(pattern.value == "60%")
        #expect(pattern.label == "of plays in the evening")
        #expect(pattern.sentence == "Usually played in the evening")
        #expect(pattern.explanation == "Counted since Nov 4, 2024, tracked by Hum. 3 of 5 plays were between 5 PM and 10 PM.")

        // Four plays is too few, and two of five is too weak.
        #expect(insight(.pattern, in: Array(evenings + mornings.prefix(1))) == nil)
        let spread = [8, 13, 19, 23, 9].enumerated().map { play(HistoryFixtures.date(2025, 10, 20 + $0.offset, $0.element)) }
        #expect(insight(.pattern, in: spread) == nil)
    }

    @Test func aWeekdayPatternNeedsFourPlaysOnOneDay() throws {
        // Every Tuesday, at different times of day.
        let tuesdays = [8, 13, 19, 23].enumerated().map { index, hour in
            play(HistoryFixtures.date(2025, 10, 7 + index * 7, hour))
        }
        let other = play(HistoryFixtures.date(2025, 11, 1, 12))
        let pattern = try #require(insight(.pattern, in: tuesdays + [other]))
        #expect(pattern.value == "80%")
        #expect(pattern.sentence == "Usually a Tuesday song")

        // Three Tuesdays, and no time of day reaching 60%.
        let three = Array(tuesdays.prefix(3)) + [play(HistoryFixtures.date(2025, 11, 1, 23)), play(HistoryFixtures.date(2025, 11, 2, 6))]
        #expect(insight(.pattern, in: three) == nil)
    }

    @Test func backAfterALongTimeAway() throws {
        let relationship = try #require(insight(.relationship, in: [play(days(100)), play(days(70))]))
        #expect(relationship.sentence == "Back after 70 days")
        #expect(relationship.value == "70")
        #expect(relationship.relevance == 0.85)
    }

    @Test func rediscoveredAfterALongGap() throws {
        let relationship = try #require(insight(.relationship, in: [play(days(100)), play(days(1))]))
        #expect(relationship.sentence == "Rediscovered after 99 days")
        #expect(relationship.label == "days away before yesterday")
    }

    @Test func aReturnStillCountsAfterAFewMorePlays() throws {
        let relationship = try #require(insight(.relationship, in: [play(days(100)), play(days(4)), play(days(2)), play(days(1))]))
        #expect(relationship.sentence == "Rediscovered after 96 days")
        #expect(relationship.label == "days away before Friday")
        #expect(relationship.details == ["3 plays since coming back"])
    }

    @Test func onRepeatIsNeverAStreak() throws {
        let plays = HistoryFixtures.plays("Song", count: 5, endingAt: now.addingTimeInterval(-3_600), spacing: 12 * 3_600)
        let relationship = try #require(insight(.relationship, in: plays))
        #expect(relationship.sentence == "On repeat lately")
        #expect(relationship.value == "5")
        #expect(relationship.label == "plays in 3 days")

        let four = Array(plays.suffix(4))
        #expect(insight(.relationship, in: four)?.sentence != "On repeat lately")
    }

    @Test func newThisWeekOnlyWhenTrackingIsOlder() throws {
        let plays = [play(days(2)), play(days(1))]
        let fresh = try #require(insight(.relationship, in: plays, trackedSince: days(30)))
        #expect(fresh.sentence == "New to Hum this week")
        #expect(fresh.label == "first heard Sunday")
        // Tracking began this week too, so there's nothing to compare with.
        #expect(insight(.relationship, in: plays, trackedSince: days(4)) == nil)
    }

    @Test func oftenSkippedNeedsMostRecentListensSkipped() throws {
        let listens = [play(days(20)), play(days(10)), skip(days(5)), skip(days(4)), skip(days(3))]
        let relationship = try #require(insight(.relationship, in: listens))
        #expect(relationship.sentence == "Often skipped lately")
        #expect(relationship.value == "3 of 5")

        let fewer = [play(days(20)), play(days(10)), skip(days(5)), skip(days(4)), play(days(3))]
        #expect(insight(.relationship, in: fewer)?.sentence != "Often skipped lately")
    }

    @Test func aLongTermFavoriteSpansFourMonths() throws {
        let plays = HistoryFixtures.plays("Song", count: 8, endingAt: days(2), spacing: 20 * 86_400)
        let relationship = try #require(insight(.relationship, in: plays))
        #expect(relationship.sentence == "A long-term favorite")
        #expect(relationship.value == "6")

        let seven = Array(plays.suffix(7))
        #expect(insight(.relationship, in: seven) == nil)
    }

    @Test func noRelationshipWithoutSomethingToSay() {
        #expect(insight(.relationship, in: [play(days(10)), play(days(5))]) == nil)
    }

    @Test func rankNeedsAFullEnoughMonth() throws {
        let me = SongKey.make(artist: "Artist", title: "Song")
        var counts = [me: 5, "a": 6, "b": 5]
        for index in 0 ..< 7 { counts["filler \(index)"] = 3 }
        // 37 plays across 10 songs.
        let second = try #require(InsightEngine.rank(songKey: me, counts: counts, format: HistoryFormat(calendar: calendar), calendar: calendar, now: now))
        #expect(second.value == "2nd")
        #expect(second.sentence == "Your 2nd-most-played song this month")
        #expect(second.details == ["5 of 37 plays this month", "Tied with 1 other song"])
        #expect(second.explanation == "Ranked by plays from Nov 1 to today, tracked by Hum.")

        func rank(_ counts: [String: Int]) -> Insight? {
            InsightEngine.rank(songKey: me, counts: counts, format: HistoryFormat(calendar: calendar), calendar: calendar, now: now)
        }
        var nineSongs = counts
        nineSongs["filler 0"] = nil
        nineSongs["a"] = 9
        #expect(rank(nineSongs) == nil, "fewer than 10 songs this month")

        var quiet = Dictionary(uniqueKeysWithValues: (0 ..< 9).map { ("q\($0)", 1) })
        quiet[me] = 3
        #expect(rank(quiet) == nil, "fewer than 20 plays this month")

        var twoPlays = counts
        twoPlays[me] = 2
        #expect(rank(twoPlays) == nil, "fewer than 3 plays of the song")

        var crowded = Dictionary(uniqueKeysWithValues: (0 ..< 10).map { ("c\($0)", 9) })
        crowded[me] = 3
        #expect(rank(crowded) == nil, "outside the top 10")

        var top = counts
        top[me] = 12
        #expect(rank(top)?.sentence == "Your most-played song this month")
    }

    @Test func milestonesAreOnlyNewsForAWeek() throws {
        let recent = HistoryFixtures.plays("Song", count: 10, endingAt: days(2), spacing: 86_400)
        let milestone = try #require(insight(.milestone, in: recent))
        #expect(milestone.value == "10")
        #expect(milestone.sentence == "Reached 10 plays Sunday")

        let old = HistoryFixtures.plays("Song", count: 10, endingAt: days(8), spacing: 86_400)
        #expect(insight(.milestone, in: old) == nil)
        #expect(insight(.milestone, in: Array(recent.suffix(9))) == nil)
    }

    @Test func everyInsightSaysWhereItsNumbersCameFrom() {
        let histories: [[Listen]] = [
            [],
            [skip(days(1))],
            HistoryFixtures.plays("Song", count: 12, endingAt: days(1), spacing: 3 * 86_400),
            [play(days(100)), play(days(1))],
            [play(days(100)), play(days(70))],
        ]
        let me = SongKey.make(artist: "Artist", title: "Song")
        var counts = Dictionary(uniqueKeysWithValues: (0 ..< 10).map { ("o\($0)", 2) })
        counts[me] = 5
        for listens in histories {
            for insight in insights(listens, monthPlayCounts: counts) {
                #expect(insight.explanation.localizedCaseInsensitiveContains("hum"), "\(insight.kind)")
                let hasNumber = insight.explanation.contains { $0.isNumber }
                #expect(hasNumber, "\(insight.kind)")
                let words = [insight.title, insight.label, insight.sentence ?? "", insight.explanation].joined(separator: " ").lowercased()
                    .replacingOccurrences(of: "’", with: "'")
                for banned in ["streak", "don't break", "neglect", "you haven't", "missed"] {
                    #expect(!words.contains(banned), "\(insight.kind): \(banned)")
                }
            }
        }
    }

    // MARK: Sessions

    func session(_ listens: [Listen], firstHeard: [String: Date] = [:]) -> ListeningSession {
        SessionBuilder.session(listens, firstHeard: firstHeard, calendar: calendar)
    }

    func run(_ titles: [String], start: Date = HistoryFixtures.date(2025, 11, 4, 14), context: PlaybackContext? = nil) -> [Listen] {
        titles.enumerated().map { index, title in
            HistoryFixtures.listen(title, at: start.addingTimeInterval(Double(index) * 210), context: context)
        }
    }

    func sessionInsights(_ session: ListeningSession, prior: [TimeInterval] = []) -> [Insight] {
        InsightEngine.sessionInsights(session, priorLengths: prior, trackedSince: days(365), now: now, calendar: calendar)
    }

    @Test func everySessionHasASummary() throws {
        let summary = try #require(sessionInsights(session(run(["A", "B"]))).first { $0.kind == .sessionSummary })
        #expect(summary.title == "Tuesday afternoon listening")
        #expect(summary.value == "7 min")
        #expect(summary.label == "2 songs · 1 artist")
        // Times may use a narrow no-break space before PM.
        #expect(summary.explanation.hasPrefix("This session since 2:00"))
        #expect(summary.explanation.hasSuffix("PM, tracked by Hum. A gap of more than 30 minutes starts a new one."))
    }

    @Test func theLongestSessionNeedsHistoryAndLength() {
        let long = session(run((0 ..< 15).map { "S\($0)" }))
        #expect(long.listened == 3_000)
        func hasLongest(_ prior: [TimeInterval], _ session: ListeningSession) -> Bool {
            sessionInsights(session, prior: prior).contains { $0.kind == .sessionLongest }
        }
        #expect(hasLongest([600, 900, 1_200, 1_500, 2_000], long))
        #expect(!hasLongest([600, 900, 1_200, 1_500], long), "fewer than five earlier sessions")
        #expect(!hasLongest([600, 900, 1_200, 1_500, 3_100], long), "not the longest")
        let short = session(run((0 ..< 12).map { "S\($0)" }))
        #expect(!hasLongest([60, 90, 120, 150, 200], short), "under 45 minutes")
    }

    @Test func returnsNameTheSongThatCameBack() throws {
        let returns = try #require(sessionInsights(session(run(["A", "B", "A", "C", "A"]))).first { $0.kind == .sessionReturns })
        #expect(returns.sentence == "A keeps coming back")
        #expect(returns.value == "3")
        #expect(returns.label == "plays this session")

        let twice = try #require(sessionInsights(session(run(["A", "B", "A"]))).first { $0.kind == .sessionReturns })
        #expect(twice.sentence == "A came back")
        #expect(!sessionInsights(session(run(["A", "B"]))).contains { $0.kind == .sessionReturns })
    }

    @Test func balanceNeedsFourSongs() throws {
        let titles = ["A", "B", "C", "D"]
        let old = days(30)
        func balance(familiar: [String]) -> Insight? {
            let firstHeard = Dictionary(uniqueKeysWithValues: familiar.map { (SongKey.make(artist: "Artist", title: $0), old) })
            return sessionInsights(session(run(titles), firstHeard: firstHeard)).first { $0.kind == .sessionBalance }
        }
        #expect(balance(familiar: titles)?.sentence == "Every song heard before")
        #expect(balance(familiar: titles)?.value == "100%")
        #expect(balance(familiar: ["A", "B", "C"])?.sentence == "Mostly familiar songs")
        #expect(balance(familiar: [])?.sentence == "Every song new to Hum")
        #expect(balance(familiar: ["A"])?.sentence == "Mostly songs new to Hum")
        let mixed = try #require(balance(familiar: ["A", "B"]))
        #expect(mixed.sentence == "A mix of familiar and new")
        #expect(mixed.value == "2 of 4")
        #expect(!sessionInsights(session(run(["A", "B", "C"]))).contains { $0.kind == .sessionBalance })
    }

    @Test func sourcesOnlyWhenEnoughListensSaid() throws {
        let mix = PlaybackContext(kind: .playlist, name: "Late Shift")
        let sources = try #require(sessionInsights(session(run(["A", "B", "C"], context: mix))).first { $0.kind == .sessionSources })
        #expect(sources.sentence == "All from Late Shift")
        #expect(sources.value == "3 of 3")
        #expect(sources.label == "listens from Late Shift")
        #expect(sources.explanation.hasPrefix("All from Late Shift since 2:00"))
        #expect(sources.explanation.hasSuffix("PM, tracked by Hum."))
        #expect(!sessionInsights(session(run(["A", "B"], context: mix))).contains { $0.kind == .sessionSources })
    }

    @Test func sourcesSayHowManyListensWhenNotAll() throws {
        let mix = PlaybackContext(kind: .playlist, name: "Late Shift")
        let other = PlaybackContext(kind: .album, name: "Harbor Lights")
        let listens = run(["A", "B", "C"], context: mix) + run(["D"], start: HistoryFixtures.date(2025, 11, 4, 14, 11), context: other)
            + run(["E"], start: HistoryFixtures.date(2025, 11, 4, 14, 15))
        let sources = try #require(sessionInsights(session(listens)).first { $0.kind == .sessionSources })
        #expect(sources.sentence == "Mostly from Late Shift")
        #expect(sources.value == "3 of 4")
        #expect(sources.explanation.hasPrefix("3 of 4 listens from Late Shift since 2:00"))
        #expect(sources.details.last == "1 other listen didn’t say where it came from")
    }

    @Test func aSessionUnderAMinuteSaysSoInsteadOfSeconds() throws {
        let short = session([HistoryFixtures.listen("A", at: HistoryFixtures.date(2025, 11, 4, 14), listened: 12)])
        let summary = try #require(sessionInsights(short).first { $0.kind == .sessionSummary })
        #expect(summary.value == nil)
        #expect(summary.label == "under 1 min · 1 song · 1 artist")
    }

    @Test func theSessionLengthReadsAsWordsUnderAMinute() {
        #expect(HistoryFormat.sessionLength(0, isOngoing: true) == "Just started")
        #expect(HistoryFormat.sessionLength(59, isOngoing: true) == "Just started")
        #expect(HistoryFormat.sessionLength(40, isOngoing: false) == "Under 1 min")
        #expect(HistoryFormat.sessionLength(60, isOngoing: true) == "1 min")
        #expect(HistoryFormat.sessionLength(3_900, isOngoing: false) == "1 hr 5 min")
    }

    // MARK: Ordering

    @Test func insightsAreOrderedByRelevanceThenKind() {
        func make(_ kind: Insight.Kind, _ relevance: Double) -> Insight {
            Insight(kind: kind, title: "", value: nil, label: "", explanation: "", relevance: relevance)
        }
        let ranked = InsightEngine.ranked([make(.rank, 0.5), make(.pattern, 0.9), make(.togetherTime, 0.5)])
        #expect(ranked.map(\.kind) == [.pattern, .togetherTime, .rank])
    }

    @Test func songInsightsComeOutRanked() {
        let result = insights([play(days(100)), play(days(70))])
        #expect(result.map(\.relevance) == result.map(\.relevance).sorted(by: >))
        #expect(result.first?.kind == .relationship)
    }
}
