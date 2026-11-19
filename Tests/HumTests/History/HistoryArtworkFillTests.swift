import Foundation
@testable import HumCore
import HumSources
import Testing

@MainActor
@Suite("History covers")
struct HistoryArtworkFillTests {
    func listen(_ track: String, daysAgo: Double) -> Listen {
        HistoryFixtures.listen(track, at: HistoryFixtures.daysAgo(daysAgo), trackID: track)
    }

    func makeHistory(store: HistoryStore, cache: ArtworkCache) -> ListeningHistory {
        ListeningHistory(
            store: store,
            nowPlaying: NowPlayingStore(sources: [], preferredSourceID: nil),
            settings: SettingsStore(fileURL: nil),
            artworkCache: cache,
            calendar: HistoryFixtures.calendar,
            now: { HistoryFixtures.now }
        )
    }

    func cover() async throws -> Data {
        try #require(await DemoArtwork.pngData(for: DemoCover.allCases[0], side: 8))
    }

    /// One listen per cover, the one heard most recently last.
    @Test func coversAreOrderedOldestFirstByTheirLatestListen() {
        let order = ListeningHistory.coverOrder([
            listen("a", daysAgo: 4),
            listen("c", daysAgo: 1),
            listen("b", daysAgo: 3),
            listen("a", daysAgo: 2),
        ])
        #expect(order.map(\.trackID.rawValue) == ["b", "a", "c"])
        #expect(order.first { $0.trackID.rawValue == "a" }?.startedAt == HistoryFixtures.daysAgo(2))
    }

    @Test func aLimitKeepsTheNewestCovers() {
        let order = ListeningHistory.coverOrder(
            [listen("a", daysAgo: 3), listen("b", daysAgo: 2), listen("c", daysAgo: 1)],
            limit: 2
        )
        #expect(order.map(\.trackID.rawValue) == ["b", "c"])
    }

    /// A cache that keeps fewer covers in memory than the history has keeps
    /// the newest, which the session trail shows.
    @Test func replacingHistoryLeavesTheNewestCoversInMemory() async throws {
        let cache = ArtworkCache(directory: nil, memoryLimit: 2)
        let history = makeHistory(store: try HistoryStore(url: nil), cache: cache)
        let data = try await cover()
        let listens = [listen("old", daysAgo: 3), listen("newer", daysAgo: 2), listen("newest", daysAgo: 1)]
        history.replaceAll(with: listens) { _ in data }
        await history.settle()
        #expect(await cache.image(forKey: listens[2].artworkKey) != nil)
        #expect(await cache.image(forKey: listens[1].artworkKey) != nil)
        #expect(await cache.image(forKey: listens[0].artworkKey) == nil)
    }

    /// History kept from an earlier run gets its recent covers back, and
    /// listens older than a week are left alone.
    @Test func fillingGivesRecentSongsTheirCovers() async throws {
        let store = try HistoryStore(url: nil)
        let listens = [listen("last month", daysAgo: 30), listen("monday", daysAgo: 1), listen("today", daysAgo: 0.1)]
        try await store.insert(contentsOf: listens)
        let cache = ArtworkCache(directory: nil)
        let history = makeHistory(store: store, cache: cache)
        let data = try await cover()
        history.fillArtwork { _ in data }
        await history.settle()
        #expect(await cache.image(forKey: listens[2].artworkKey) != nil)
        #expect(await cache.image(forKey: listens[1].artworkKey) != nil)
        #expect(await cache.image(forKey: listens[0].artworkKey) == nil)
    }

    @Test func fillingLeavesCoversAlreadyCached() async throws {
        let store = try HistoryStore(url: nil)
        let today = listen("today", daysAgo: 0.1)
        try await store.insert(contentsOf: [today])
        let cache = ArtworkCache(directory: nil)
        let data = try await cover()
        let cached = try #require(await cache.insert(data, forKey: today.artworkKey))
        let history = makeHistory(store: store, cache: cache)
        let other = try #require(await DemoArtwork.pngData(for: DemoCover.allCases[1], side: 8))
        history.fillArtwork { _ in other }
        await history.settle()
        #expect(await cache.image(forKey: today.artworkKey) == cached)
    }
}
