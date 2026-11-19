import Foundation
import HumCore
import HumSources
import Testing

@MainActor
@Suite("Demo source")
struct DemoSourceTests {
    let clock = TestClock()

    func makeSource(playing: Bool = false) -> DemoSource {
        let clock = clock
        return DemoSource(startsPlaying: playing, startPosition: 10, latency: .zero, now: { clock.now })
    }

    @Test func startsWithEverythingAndNoPermissionNeeded() {
        let source = makeSource()
        #expect(source.state.availability == .running)
        #expect(source.state.permission == .notRequired)
        #expect(source.state.effectiveCapabilities == DemoSource.capabilities)
        #expect(source.state.snapshot.status == .paused)
        #expect(source.state.snapshot.position == 10)
        #expect(source.appBundleIdentifier == nil)
    }

    @Test func playsAndKeepsTime() async throws {
        let source = makeSource()
        try await source.perform(.play)
        clock.advance(5)
        try await source.perform(.pause)
        #expect(source.state.snapshot.position == 15)
        #expect(source.state.snapshot.status == .paused)
    }

    @Test func skipsAndWraps() async throws {
        let source = makeSource()
        let first = try #require(source.state.snapshot.track)
        try await source.perform(.next)
        #expect(source.state.snapshot.track != first)
        #expect(source.state.snapshot.position == 0)
        try await source.perform(.previous)
        #expect(source.state.snapshot.track == first)
        try await source.perform(.previous)
        #expect(source.state.snapshot.track == DemoPlaylist.tracks.last?.track)
    }

    @Test func previousRestartsATrackThatsUnderway() async throws {
        let source = makeSource()
        let first = source.state.snapshot.track
        try await source.perform(.previous)
        #expect(source.state.snapshot.track == first)
        #expect(source.state.snapshot.position == 0)
    }

    @Test func reportsEveryChange() async throws {
        let source = makeSource()
        var reports = 0
        source.onStateChange = { _ in reports += 1 }
        try await source.perform(.setVolume(0.3))
        try await source.perform(.setShuffle(true))
        try await source.perform(.setRepeat(.one))
        try await source.perform(.setFavorite(false))
        #expect(reports == 4)
        let snapshot = source.state.snapshot
        #expect(snapshot.volume == 0.3)
        #expect(snapshot.shuffle == true)
        #expect(snapshot.repeatMode == .one)
        #expect(snapshot.isFavorite == false)
    }

    @Test func drawsArtworkForEveryTrack() async throws {
        let source = makeSource()
        for item in DemoPlaylist.tracks {
            let data = try #require(await source.artwork(for: item.track))
            #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        }
    }
}
