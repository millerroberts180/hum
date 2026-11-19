import Foundation
@testable import HumCore
import HumSources
import Testing

@Suite("Demo history")
struct DemoHistoryTests {
    let calendar = HistoryFixtures.calendar
    let end = HistoryFixtures.now
    let catalog = DemoPlaylist.tracks.map(\.track)

    func generate(seed: UInt64 = DemoHistory.defaultSeed) -> [Listen] {
        DemoHistory.generate(catalog: catalog, endingAt: end, calendar: calendar, seed: seed)
    }

    @Test func theSameSeedGivesTheSameHistory() {
        let first = generate()
        #expect(!first.isEmpty)
        #expect(first == generate())
        #expect(first != generate(seed: 7))
    }

    @Test func itCoversAboutSixMonths() throws {
        let listens = generate()
        let oldest = try #require(listens.first?.startedAt)
        let newest = try #require(listens.last?.startedAt)
        let days = end.timeIntervalSince(oldest) / 86_400
        #expect((170 ... 183).contains(days))
        #expect(newest < end)
        #expect(end.timeIntervalSince(newest) < 30 * 60, "a session is still warm")
        #expect(listens.count > 500)
        #expect(listens == listens.sorted { $0.startedAt < $1.startedAt })
    }

    @Test func everyListenFollowsThePlayRules() {
        for listen in generate() {
            #expect(listen.source == .demo)
            #expect(listen.counts == PlayRules.counts(listened: listen.listened, duration: listen.duration))
            #expect(listen.listened <= (listen.duration ?? .infinity) + 0.001)
            #expect(listen.endedAt >= listen.startedAt.addingTimeInterval(listen.listened - 0.001))
        }
    }

    @Test func eachRoleGivesItsInsight() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(contentsOf: generate())

        func relationship(_ index: Int) async throws -> String? {
            let snapshot = try await store.echo(track: catalog[index], inProgress: nil, now: end, calendar: calendar)
            return snapshot.songInsights.first { $0.kind == .relationship }?.sentence
        }
        #expect(try await relationship(1) == "On repeat lately")
        #expect(try await relationship(2) == "Often skipped lately")
        #expect(try await relationship(3)?.hasPrefix("Rediscovered after") == true)

        let quiet = try await store.rediscover(quietSince: end.addingTimeInterval(-60 * 86_400))
        #expect(quiet.contains { $0.sampleTrackID == catalog[4].id })

        let single = try #require(DemoHistory.extraTracks(for: catalog).first { $0.id == TrackID("demo:northbound") })
        let fresh = try await store.echo(track: single, inProgress: nil, now: end, calendar: calendar)
        #expect(fresh.songInsights.contains { $0.sentence == "New to Hum this week" })

        let now = try await store.echo(track: catalog[0], inProgress: nil, now: end, calendar: calendar)
        #expect(now.session != nil)
        #expect(!now.sessionInsights.isEmpty)
    }

    /// The session the demo opens on, on Echo and in the Session style, is
    /// the playlist's songs, without the two singles.
    @Test func theWarmSessionLeavesOutTheSingles() throws {
        let warm = generate().filter { end.timeIntervalSince($0.startedAt) < 30 * 60 }
        #expect(!warm.isEmpty)
        #expect(warm.allSatisfy { $0.trackID != TrackID("demo:northbound") && $0.trackID != TrackID("demo:paper-boats") })
    }

    @Test func asSpotifyNoListenNamesWhatItPlayedFrom() {
        let named = generate()
        #expect(named.contains { $0.context?.kind == .playlist })
        let unnamed = DemoHistory.generate(catalog: catalog, endingAt: end, calendar: calendar, namesContexts: false)
        #expect(unnamed.allSatisfy { $0.context == nil })
        // The same listening otherwise.
        #expect(unnamed.count == named.count)
        #expect(unnamed.map(\.trackID) == named.map(\.trackID))
        #expect(unnamed.map(\.startedAt) == named.map(\.startedAt))
    }

    @Test func theNewSingleIsThisWeeksDiscovery() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(contentsOf: generate())
        let week = try await store.weekReceipt(now: end, calendar: calendar)
        #expect(week.discovery?.name == "Northbound")
    }

    @Test func theSeededHistoryHasNoStreakLanguage() async throws {
        let store = try HistoryStore(url: nil)
        try await store.insert(contentsOf: generate())
        for track in catalog + DemoHistory.extraTracks(for: catalog) {
            let snapshot = try await store.echo(track: track, inProgress: nil, now: end, calendar: calendar)
            for insight in snapshot.songInsights + snapshot.sessionInsights {
                let text = [insight.title, insight.label, insight.sentence ?? "", insight.explanation].joined(separator: " ").lowercased()
                #expect(!text.contains("streak"))
                #expect(insight.explanation.localizedCaseInsensitiveContains("hum"))
            }
        }
    }
}
