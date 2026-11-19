import Foundation
@testable import HumCore
import Testing

@Suite("History summaries")
struct HistorySummaryTests {
    let calendar = HistoryFixtures.calendar

    // MARK: Heat calendar

    @Test func heatLevelsSplitAtTheQuartilesOfActiveDays() {
        let scale = HeatScale(values: [0, 0, 60, 120, 180, 240, 300])
        #expect(scale.bounds == [120, 180, 240])
        #expect(scale.level(0) == 0)
        #expect(scale.level(1) == 1)
        #expect(scale.level(120) == 1)
        #expect(scale.level(121) == 2)
        #expect(scale.level(200) == 3)
        #expect(scale.level(10_000) == 4)
    }

    @Test func aLightListenersBusiestDayStillReadsAsBusy() {
        let scale = HeatScale(values: [30, 30, 40, 90])
        #expect(scale.level(90) == 4)
        #expect(HeatScale(values: []).level(30) == 1, "no history yet: any listening is the first step")
    }

    @Test func monthsStartOnTheCalendarsFirstWeekday() throws {
        // November 2025 starts on a Saturday.
        let month = try #require(CalendarMonth.containing(HistoryFixtures.now, calendar: calendar))
        #expect(month.start == HistoryFixtures.date(2025, 11, 1, 0))
        #expect(month.weeks.count == 6)
        #expect(month.weeks.allSatisfy { $0.count == 7 })
        #expect(month.weeks[0].prefix(6).allSatisfy { $0 == nil })
        #expect(month.weeks[0][6] == HistoryFixtures.date(2025, 11, 1, 0))
        #expect(month.weeks.flatMap { $0 }.compactMap { $0 }.count == 30)

        var monday = calendar
        monday.firstWeekday = 2
        let mondayMonth = try #require(CalendarMonth.containing(HistoryFixtures.now, calendar: monday))
        #expect(mondayMonth.weeks[0].prefix(5).allSatisfy { $0 == nil })
        #expect(mondayMonth.weeks.count == 5)
        #expect(CalendarMonth.weekdayInitials(calendar: monday) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(CalendarMonth.weekdayInitials(calendar: calendar) == ["S", "M", "T", "W", "T", "F", "S"])
    }

    @Test func monthsRunOldestFirst() {
        let months = CalendarMonth.months(endingAt: HistoryFixtures.now, count: 6, calendar: calendar)
        #expect(months.map { calendar.component(.month, from: $0.start) } == [6, 7, 8, 9, 10, 11])
    }

    // MARK: Week receipt

    let weekStart = HistoryFixtures.date(2025, 11, 2, 0)
    let weekEnd = HistoryFixtures.now

    func receipt(_ listens: [Listen], firstHeard: [String: Date] = [:], totalBefore: Int = 0, songBefore: [String: Int] = [:]) -> WeekReceipt {
        WeekReceipt.make(
            start: weekStart,
            end: weekEnd,
            listens: listens,
            firstHeard: firstHeard,
            totalPlaysBefore: totalBefore,
            songPlaysBefore: songBefore,
            calendar: calendar
        )
    }

    @Test func aQuietWeekSaysSo() {
        let empty = receipt([])
        #expect(empty.takeaway == "A quiet week so far.")
        #expect(empty.plays == 0)
        #expect(empty.topArtist == nil)
        #expect(empty.days.count == 3, "Sunday through today")
        #expect(receipt([HistoryFixtures.listen("A", at: HistoryFixtures.date(2025, 11, 3, 9))]).takeaway == "A light week so far.")
    }

    @Test func theReceiptAddsUpTheWeek() throws {
        let evening = (0 ..< 4).map { HistoryFixtures.listen("Home", artist: "Wren", at: HistoryFixtures.date(2025, 11, 3, 19, $0 * 4)) }
        let morning = [
            HistoryFixtures.listen("Road", artist: "Ada", at: HistoryFixtures.date(2025, 11, 4, 8)),
            HistoryFixtures.listen("Fresh", artist: "Ada", at: HistoryFixtures.date(2025, 11, 4, 9)),
            HistoryFixtures.listen("Skip", artist: "Ada", at: HistoryFixtures.date(2025, 11, 4, 10), listened: 5),
        ]
        let old = HistoryFixtures.daysAgo(100)
        let firstHeard = [
            SongKey.make(artist: "Wren", title: "Home"): old,
            SongKey.make(artist: "Ada", title: "Road"): old,
            SongKey.make(artist: "Ada", title: "Fresh"): HistoryFixtures.date(2025, 11, 4, 9),
        ]
        let week = receipt(evening + morning, firstHeard: firstHeard)
        #expect(week.plays == 6)
        #expect(week.songs == 3)
        #expect(week.listened == 6 * 200 + 5)
        #expect(week.topArtist == WeekReceipt.Line(name: "Wren", detail: "4 plays", plays: 4))
        #expect(week.mostRepeated?.name == "Home")
        #expect(week.mostRepeated?.detail == "Wren · 4 plays")
        #expect(week.discovery == WeekReceipt.Line(name: "Fresh", detail: "Ada · first heard today", plays: 1))
        #expect(week.takeaway == "Mostly evenings, some new songs among old ones.")
        #expect(week.days.map(\.plays) == [0, 4, 2])
    }

    @Test func milestonesAreFactsReachedThisWeek() {
        let plays = (0 ..< 3).map { HistoryFixtures.listen("Song", at: HistoryFixtures.date(2025, 11, 3, 12 + $0)) }
        let week = receipt(plays, totalBefore: 98, songBefore: [SongKey.make(artist: "Artist", title: "Song"): 23])
        #expect(week.milestones == [
            "Your 100th play tracked by Hum, yesterday",
            "Song reached 25 plays yesterday",
        ])
        #expect(receipt(plays, totalBefore: 10).milestones.isEmpty)
    }

    @Test func theReceiptReadsFromTheStore() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(contentsOf: [
            HistoryFixtures.listen("Before", at: HistoryFixtures.date(2025, 11, 1, 12)),
            HistoryFixtures.listen("During", at: HistoryFixtures.date(2025, 11, 3, 12)),
        ])
        let week = try await store.weekReceipt(now: HistoryFixtures.now, calendar: calendar)
        #expect(week.start == weekStart)
        #expect(week.plays == 1)
        #expect(week.discovery?.name == "During")
    }

    // MARK: Format

    @Test func sourcesAreNamedPlainly() {
        #expect(HistoryFormat.source([]) == "tracked by Hum on this Mac")
        #expect(HistoryFormat.source([.musicApp]) == "tracked by Hum from Music")
        #expect(HistoryFormat.source([.spotifyApp, .musicApp, .spotifyApp]) == "tracked by Hum from Music and Spotify")
        #expect(HistoryFormat.source([.spotifyApp, .musicApp, .demo]) == "tracked by Hum from Music, Spotify and the demo player")
    }

    @Test func numbersReadNaturally() {
        #expect(HistoryFormat.duration(40) == "40 sec")
        #expect(HistoryFormat.duration(45 * 60) == "45 min")
        #expect(HistoryFormat.duration(71 * 60) == "1 hr 11 min")
        #expect(HistoryFormat.duration(120 * 60) == "2 hr")
        #expect(["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "112th"] == [1, 2, 3, 4, 11, 12, 13, 21, 112].map(HistoryFormat.ordinal))
        #expect(HistoryFormat.count(1, "play") == "1 play")
        #expect(HistoryFormat.count(1_200, "play") == "1,200 plays")
        #expect(HistoryFormat.percent(0.714) == "71%")
    }

    @Test func daysReadRelativeToToday() {
        let format = HistoryFormat(calendar: calendar)
        let now = HistoryFixtures.now
        #expect(format.relativeDay(HistoryFixtures.date(2025, 11, 4, 1), now: now) == "today")
        #expect(format.relativeDay(HistoryFixtures.date(2025, 11, 3, 23), now: now) == "yesterday")
        #expect(format.relativeDay(HistoryFixtures.date(2025, 10, 30), now: now) == "Thursday")
        #expect(format.relativeDay(HistoryFixtures.date(2025, 10, 28), now: now) == "Oct 28")
        #expect(format.day(HistoryFixtures.date(2024, 12, 31), now: now) == "Dec 31, 2024")
    }
}
