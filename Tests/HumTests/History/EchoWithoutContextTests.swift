import Foundation
@testable import HumCore
import Testing

/// Spotify's app doesn't say which playlist or album a song is playing from,
/// so its listens carry no context. Echo and History leave out what would need
/// one, rather than naming nothing or the wrong thing (DESIGN.md §4.3, §4.4).
@MainActor
@Suite("Echo without a context")
struct EchoWithoutContextTests {
    let calendar = HistoryFixtures.calendar
    let now = HistoryFixtures.now
    let start = HistoryFixtures.date(2025, 11, 4, 14)

    func spotify(_ titles: [String], from start: Date) -> [Listen] {
        titles.enumerated().map { index, title in
            HistoryFixtures.listen(title, artist: "Low Tide", at: start.addingTimeInterval(Double(index) * 210), source: .spotifyApp)
        }
    }

    func sessionInsights(_ listens: [Listen]) -> [Insight] {
        let session = SessionBuilder.session(listens, firstHeard: [:], calendar: calendar)
        return InsightEngine.sessionInsights(session, priorLengths: [], trackedSince: HistoryFixtures.daysAgo(365), now: now, calendar: calendar)
    }

    /// Every word an insight shows or speaks.
    func words(_ insight: Insight) -> [String] {
        [insight.title, insight.value ?? "", insight.label, insight.sentence ?? "", insight.explanation, insight.spokenSummary] + insight.details
    }

    @Test func aSpotifySessionSaysNothingAboutWhereItCameFrom() throws {
        let listens = spotify(["A", "B", "C", "D", "E", "F"], from: start)
        let session = SessionBuilder.session(listens, firstHeard: [:], calendar: calendar)
        #expect(session.sourceMix.isEmpty)
        #expect(session.knownContextCount == 0)

        let insights = sessionInsights(listens)
        #expect(!insights.isEmpty)
        #expect(!insights.contains { $0.kind == .sessionSources })
        for insight in insights {
            for text in words(insight) {
                #expect(!text.hasSuffix("from "), "\(insight.kind): \(text)")
                #expect(!text.contains("from ."), "\(insight.kind): \(text)")
                #expect(!text.contains("  "), "\(insight.kind): \(text)")
                #expect(!text.localizedCaseInsensitiveContains("playlist"), "\(insight.kind): \(text)")
                #expect(!text.localizedCaseInsensitiveContains("didn’t say where"), "\(insight.kind): \(text)")
            }
            #expect(!insight.title.isEmpty)
            #expect(!insight.label.isEmpty)
        }
    }

    /// Music's listens still say where they came from beside Spotify's,
    /// counted as the ones that didn't say.
    @Test func spotifysListensCountAsUnsaidBesideMusics() throws {
        let mix = PlaybackContext(kind: .playlist, name: "Late Shift")
        let music = ["A", "B", "C"].enumerated().map { index, title in
            HistoryFixtures.listen(title, at: start.addingTimeInterval(Double(index) * 210), source: .musicApp, context: mix)
        }
        let listens = music + spotify(["D", "E"], from: start.addingTimeInterval(630))
        let sources = try #require(sessionInsights(listens).first { $0.kind == .sessionSources })
        #expect(sources.sentence == "Mostly from Late Shift")
        #expect(sources.value == "3 of 3")
        #expect(sources.details.first == "Late Shift: 3 listens")
        #expect(sources.details.last == "2 other listens didn’t say where they came from")
    }

    /// A context the app gave without a name reads as its kind, never blank.
    @Test func anUnnamedContextReadsAsItsKind() {
        #expect(SourceShare(kind: .playlist, name: nil, listens: 1).displayName == "a playlist")
        #expect(SourceShare(kind: .playlist, name: "", listens: 1).displayName == "a playlist")
        #expect(SourceShare(kind: .liked, name: nil, listens: 1).displayName == "your favorites")
        #expect(SourceShare(kind: .album, name: "Harbor", listens: 1).displayName == "Harbor")
    }

    /// History's Playlist filter offers only playlists that were named, so
    /// Spotify's listens add no blank choices.
    @Test func noBlankPlaylistChoices() async throws {
        let store = try HistoryStore(url: nil)
        let named = PlaybackContext(kind: .playlist, name: "Late Shift")
        let blank = PlaybackContext(kind: .playlist, name: "")
        let spaces = PlaybackContext(kind: .playlist, name: "  ")
        try await store.insert(contentsOf: spotify(["A", "B", "C"], from: start)
            + [
                HistoryFixtures.listen("D", at: start.addingTimeInterval(700), source: .musicApp, context: named),
                HistoryFixtures.listen("E", at: start.addingTimeInterval(900), source: .musicApp, context: blank),
                HistoryFixtures.listen("F", at: start.addingTimeInterval(1_100), source: .musicApp, context: spaces),
            ])
        #expect(try await store.filterOptions().playlists == ["Late Shift"])
        // The songs themselves still rank.
        #expect(try await store.top(.songs, from: nil, to: nil).count == 6)
    }

    @Test func aSpotifyOnlyHistoryHasNoPlaylistsToFilter() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(contentsOf: spotify(["A", "B", "C"], from: start))
        #expect(try await store.filterOptions().playlists.isEmpty)
        let listens = try await store.listens()
        #expect(listens.count == 3)
        #expect(listens.allSatisfy { $0.context == nil })
    }

    /// A Spotify song that follows one of Music's playlists doesn't take the
    /// playlist with it.
    @Test func spotifysSongDoesntTakeTheLastContext() throws {
        let recorder = ListeningRecorder()
        var finished: [Listen] = []
        recorder.onFinish = { finished.append($0) }
        let mix = PlaybackContext(kind: .playlist, name: "Late Shift")
        let musicSong = Fixtures.track("music-1")
        recorder.begin(with: PlaybackSnapshot(track: musicSong, status: .playing, context: mix), source: .musicApp, at: start)
        let spotifySong = Fixtures.track("spotify:track:4uLU6hMCjMI75M1A2tKUQC")
        let spotifySnapshot = PlaybackSnapshot(track: spotifySong, status: .playing, context: nil)
        recorder.handle(
            .trackChanged(previous: musicSong, current: spotifySong, source: .spotifyApp, listened: .greatestFiniteMagnitude),
            snapshot: spotifySnapshot,
            at: start.addingTimeInterval(200)
        )
        recorder.noteSnapshot(spotifySnapshot)
        #expect(recorder.current?.source == .spotifyApp)
        #expect(recorder.current?.context == nil)
        recorder.handle(
            .trackChanged(previous: spotifySong, current: nil, source: .spotifyApp, listened: .greatestFiniteMagnitude),
            snapshot: PlaybackSnapshot(track: nil, status: .stopped),
            at: start.addingTimeInterval(400)
        )
        #expect(finished.map(\.source) == [.musicApp, .spotifyApp])
        #expect(finished.map(\.context) == [mix, nil])
    }
}
