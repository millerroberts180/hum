import CoreGraphics
import HumCore
import HumSources
@testable import HumUI
import Testing

@MainActor
@Suite("Echo under the page indicator")
struct EchoIndicatorClearanceTests {
    @Test func echoClearsTheIndicatorByTheSameAmount() {
        #expect(PageIndicator.height == 18)
        #expect(PageIndicator.contentClearance == PageIndicator.height)
        #expect(EchoSurface.indicatorClearance == PageIndicator.contentClearance)
    }
}

@Suite("Insight labels")
struct InsightLabelTests {
    private func insight(value: String?, label: String) -> Insight {
        Insight(kind: .firstTime, title: "First time", value: value, label: label, explanation: "Tracked by Hum.", relevance: 1)
    }

    /// After a value the label reads on from it: "23 plays".
    @Test func afterAValueTheLabelStaysLowercase() {
        #expect(InsightCard.shownLabel(insight(value: "23", label: "plays · 1 hr 11 min")) == "plays · 1 hr 11 min")
    }

    /// With no value, the label starts the line.
    @Test func withoutAValueTheLabelStartsWithACapital() {
        #expect(InsightCard.shownLabel(insight(value: nil, label: "first heard Sunday")) == "First heard Sunday")
        #expect(InsightCard.shownLabel(insight(value: nil, label: "")) == "")
    }
}

@MainActor
@Suite("Listen menus")
struct ListenMenuTests {
    let clock = TestClock()

    func library() -> LibraryStore {
        let clock = clock
        let source = DemoSource(startsPlaying: false, startPosition: 0, latency: .zero, now: { clock.now })
        let library = DemoLibrary(source: source, listLatency: .zero)
        return LibraryStore(
            nowPlaying: NowPlayingStore(sources: [source], preferredSourceID: .demo, now: { clock.now }),
            providers: [library],
            now: { clock.now },
            sleep: { _ in }
        )
    }

    func listen(source: SourceID, trackID: String) -> Listen {
        HistoryFixtures.listen("Night Drive", artist: "The Examples", album: "Coastline Hours", at: HistoryFixtures.now, source: source, trackID: trackID)
    }

    /// A listen from the source the library serves gets the track menu, for
    /// the song itself.
    @Test func aListenFromTheServedSourceIsTheSong() throws {
        let track = try #require(ListenMenu.track(for: listen(source: .demo, trackID: "demo:night-drive"), library: library()))
        #expect(track.id == TrackID("demo:night-drive"))
        #expect(track.title == "Night Drive")
        #expect(track.artist == "The Examples")
        #expect(track.album == "Coastline Hours")
        #expect(track.duration == 200)
    }

    /// Heard somewhere else, or imported without an ID, it can only be
    /// looked for in Find.
    @Test func otherListensAreLookedForInFind() {
        let library = library()
        #expect(ListenMenu.track(for: listen(source: .musicApp, trackID: "music:1"), library: library) == nil)
        #expect(ListenMenu.track(for: listen(source: .demo, trackID: ""), library: library) == nil)
    }
}

@Suite("History caption")
struct HistoryCaptionTests {
    @Test func aCutShortListSaysHowManyThereAre() {
        #expect(HistoryListView.count(shown: 400, of: 512, isFiltered: false) == "The latest 400 of 512 listens")
        #expect(HistoryListView.count(shown: 400, of: 512, isFiltered: true) == "The latest 400 of 512 matching listens")
    }

    @Test func aWholeListIsCounted() {
        #expect(HistoryListView.count(shown: 12, of: 12, isFiltered: false) == "12 listens")
        #expect(HistoryListView.count(shown: 12, of: 12, isFiltered: true) == "12 listens match")
        #expect(HistoryListView.count(shown: 1, of: 1, isFiltered: true) == "1 listen matches")
        #expect(HistoryListView.count(shown: 0, of: 0, isFiltered: true) == "0 listens match")
    }
}
