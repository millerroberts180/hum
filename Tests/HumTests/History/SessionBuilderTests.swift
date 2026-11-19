import Foundation
@testable import HumCore
import Testing

@Suite("Listening sessions")
struct SessionBuilderTests {
    let calendar = HistoryFixtures.calendar
    let start = HistoryFixtures.date(2025, 11, 4, 14)

    func listen(_ title: String, album: String = "Album", artist: String = "Artist", at offset: TimeInterval, listened: TimeInterval = 200) -> Listen {
        HistoryFixtures.listen(title, artist: artist, album: album, at: start.addingTimeInterval(offset), listened: listened)
    }

    @Test func aGapOfThirtyMinutesKeepsTheSession() {
        let first = listen("A", at: 0)
        // Starts exactly 30 minutes after the first ended.
        let second = listen("B", at: 200 + SessionBuilder.gap)
        #expect(SessionBuilder.split([first, second]).count == 1)
    }

    @Test func aLongerGapStartsANewSession() {
        let first = listen("A", at: 0)
        let second = listen("B", at: 200 + SessionBuilder.gap + 1)
        let sessions = SessionBuilder.split([second, first])
        #expect(sessions.count == 2)
        #expect(sessions[0].map(\.title) == ["A"])
    }

    @Test func gapsAreMeasuredFromTheEndOfTheLastListen() {
        // A 40-minute listen, then a song 50 minutes after it started.
        let long = listen("Long", at: 0, listened: 2_400)
        let next = listen("Next", at: 3_000)
        #expect(SessionBuilder.split([long, next]).count == 1)
    }

    @Test func sessionLengthsAddUpListening() {
        let spans = [
            ListenSpan(startedAt: start, endedAt: start.addingTimeInterval(200), listened: 200),
            ListenSpan(startedAt: start.addingTimeInterval(210), endedAt: start.addingTimeInterval(400), listened: 190),
            ListenSpan(startedAt: start.addingTimeInterval(10_000), endedAt: start.addingTimeInterval(10_100), listened: 100),
        ]
        #expect(SessionBuilder.sessionLengths(spans) == [390, 100])
    }

    @Test func theCurrentSessionIncludesTheListenInProgress() throws {
        let earlier = [listen("A", at: 0), listen("B", at: 210)]
        let playing = listen("C", at: 420, listened: 30)
        let session = try #require(SessionBuilder.current(
            earlier,
            inProgress: playing,
            firstHeard: [:],
            now: start.addingTimeInterval(450),
            calendar: calendar
        ))
        #expect(session.isOngoing)
        #expect(session.songCount == 3)
        #expect(session.listened == 430)
    }

    @Test func aSessionEndsAfterTheGap() {
        let earlier = [listen("A", at: 0)]
        let soon = SessionBuilder.current(earlier, inProgress: nil, firstHeard: [:], now: start.addingTimeInterval(200 + 20 * 60), calendar: calendar)
        #expect(soon?.isOngoing == false)
        let later = SessionBuilder.current(earlier, inProgress: nil, firstHeard: [:], now: start.addingTimeInterval(200 + 31 * 60), calendar: calendar)
        #expect(later == nil)
    }

    @Test func theTrailFoldsConsecutiveSongsFromOneAlbum() {
        let listens = [
            listen("One", album: "Blue", at: 0),
            listen("Two", album: "Blue", at: 210),
            listen("Three", album: "Red", at: 420),
            listen("Four", album: "Blue", at: 630),
            listen("Single", album: "", at: 840),
        ]
        let session = SessionBuilder.session(listens, firstHeard: [:], calendar: calendar)
        #expect(session.trail.map(\.album) == ["Blue", "Red", "Blue", "Single"])
        #expect(session.trail.map(\.listens) == [2, 1, 1, 1])
        #expect(session.trail.map(\.id) == [0, 1, 2, 3])
    }

    /// Each stop keeps the first song heard from its album, so its menu can
    /// act on that song and its cover is that song's.
    @Test func aStopRemembersItsFirstSong() throws {
        let listens = [
            listen("One", album: "Blue", at: 0),
            listen("Two", album: "Blue", at: 210),
            listen("Three", album: "Red", at: 420),
        ]
        let session = SessionBuilder.session(listens, firstHeard: [:], calendar: calendar)
        let blue = try #require(session.trail.first)
        #expect(blue.title == "One")
        #expect(blue.trackID == TrackID("t:One"))
        #expect(blue.artworkKey == listens[0].artworkKey)
        #expect(blue.source == .demo)
        #expect(session.trail.last?.trackID == TrackID("t:Three"))
    }

    @Test func returnsAndFamiliarity() {
        let listens = [
            listen("Old", at: 0),
            listen("New", at: 210),
            listen("Old", at: 420),
            listen("Old", at: 630),
        ]
        let firstHeard = [
            SongKey.make(artist: "Artist", title: "Old"): start.addingTimeInterval(-30 * 86_400),
            SongKey.make(artist: "Artist", title: "New"): start.addingTimeInterval(210),
        ]
        let session = SessionBuilder.session(listens, firstHeard: firstHeard, calendar: calendar)
        #expect(session.songCount == 2)
        #expect(session.repeatCount == 2)
        #expect(session.familiarCount == 1)
        #expect(session.newCount == 1)
        #expect(session.returns.first?.title == "Old")
        #expect(session.returns.first?.times == 3)
    }

    @Test func skipsDontMakeASongComeBack() {
        let listens = [
            listen("Old", at: 0, listened: 4),
            listen("Old", at: 30, listened: 6),
            listen("Other", at: 60),
            listen("Old", at: 270),
        ]
        let session = SessionBuilder.session(listens, firstHeard: [:], calendar: calendar)
        #expect(session.returns.isEmpty)
        let again = SessionBuilder.session(listens + [listen("Old", at: 480)], firstHeard: [:], calendar: calendar)
        #expect(again.returns.first?.times == 2)
    }

    @Test func artistsAreCountedOnce() {
        let listens = [
            listen("A", artist: "Beyoncé", at: 0),
            listen("B", artist: "beyonce", at: 210),
            listen("C", artist: "Other", at: 420),
        ]
        #expect(SessionBuilder.session(listens, firstHeard: [:], calendar: calendar).artistCount == 2)
    }

    @Test func chaptersAreNamedForTheDayAndTime() {
        let afternoon = SessionBuilder.session([listen("A", at: 0)], firstHeard: [:], calendar: calendar)
        #expect(afternoon.chapterName == "Tuesday afternoon listening")

        // 1 AM on Wednesday still belongs to Tuesday night.
        let late = HistoryFixtures.listen("A", at: HistoryFixtures.date(2025, 11, 5, 1))
        let night = SessionBuilder.session([late], firstHeard: [:], calendar: calendar)
        #expect(night.chapterName == "Tuesday late-night listening")
    }

    @Test func sourcesOnlyCountListensThatSaidWhereTheyCameFrom() {
        let mix = PlaybackContext(kind: .playlist, name: "Morning Mix")
        let listens = [
            HistoryFixtures.listen("A", at: start, context: mix),
            HistoryFixtures.listen("B", at: start.addingTimeInterval(210), context: mix),
            HistoryFixtures.listen("C", at: start.addingTimeInterval(420)),
        ]
        let session = SessionBuilder.session(listens, firstHeard: [:], calendar: calendar)
        #expect(session.knownContextCount == 2)
        #expect(session.sourceMix.first?.displayName == "Morning Mix")
    }
}
