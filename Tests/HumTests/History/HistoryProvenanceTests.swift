import Foundation
@testable import HumCore
import Testing

@Suite("History provenance")
struct HistoryProvenanceTests {
    let start = HistoryFixtures.date(2025, 11, 4, 14)

    func listen(_ title: String, source: SourceID, origin: ListenOrigin = .tracked, at offset: TimeInterval = 0) -> Listen {
        var listen = HistoryFixtures.listen(title, at: start.addingTimeInterval(offset), source: source)
        listen.origin = origin
        return listen
    }

    @Test func listensNameOnlyTheirOwnSources() {
        let provenance = HistoryProvenance([
            listen("A", source: .musicApp),
            listen("B", source: .musicApp, at: 210),
        ])
        #expect(provenance.tracked == [.musicApp])
        #expect(provenance.imported.isEmpty)
        #expect(provenance.service.isEmpty)
    }

    @Test func eachListenCountsUnderItsOrigin() {
        let provenance = HistoryProvenance([
            listen("A", source: .musicApp),
            listen("B", source: .spotifyApp, origin: .imported),
            listen("C", source: .spotifyApp, origin: .service),
        ])
        #expect(provenance == HistoryProvenance(tracked: [.musicApp], imported: [.spotifyApp], service: [.spotifyApp]))
    }

    @Test func noListensNameNoSources() {
        #expect(HistoryProvenance([Listen]()).isEmpty)
    }

    @Test func anEmptyQueryIsNotFiltered() {
        #expect(!HistoryQuery().isFiltered)
        #expect(!HistoryQuery(search: "  \n").isFiltered)
        // How many it shows isn't a filter.
        #expect(!HistoryQuery(limit: 10).isFiltered)
    }

    @Test func aSearchOrAnyFilterIsFiltered() {
        #expect(HistoryQuery(search: "blue").isFiltered)
        #expect(HistoryQuery(artist: "Artist").isFiltered)
        #expect(HistoryQuery(album: "Album").isFiltered)
        #expect(HistoryQuery(playlist: "Mix").isFiltered)
        #expect(HistoryQuery(timeOfDay: .night).isFiltered)
    }

    @Test func aTrailStopKeepsTheSourceOfItsCover() {
        let listens = [
            listen("One", source: .spotifyApp),
            listen("Two", source: .musicApp, at: 210),
        ]
        let session = SessionBuilder.session(
            listens.map { var listen = $0; listen.album = $0.title; return listen },
            firstHeard: [:],
            calendar: HistoryFixtures.calendar
        )
        #expect(session.trail.map(\.source) == [.spotifyApp, .musicApp])
    }

    @Test func aFoldedStopKeepsTheSourceOfItsFirstListen() {
        // Two songs from one album fold into one stop, drawn with the first's cover.
        let listens = [
            listen("One", source: .spotifyApp),
            listen("Two", source: .musicApp, at: 210),
        ]
        let session = SessionBuilder.session(listens, firstHeard: [:], calendar: HistoryFixtures.calendar)
        #expect(session.trail.count == 1)
        #expect(session.trail.first?.source == .spotifyApp)
        #expect(session.trail.first?.artworkKey == listens[0].artworkKey)
    }
}
