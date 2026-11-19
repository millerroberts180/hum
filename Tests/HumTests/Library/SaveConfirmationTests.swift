import Foundation
@testable import HumCore
@testable import HumUI
import Testing

@MainActor
@Suite("Saving the playing song from the keyboard or a menu")
struct SaveConfirmationTests {
    let clock = TestClock()

    /// A player and the library attached to it, whose HUD the notice reaches.
    func make(favorite: Bool?, capabilities: SourceCapabilities = Fixtures.everything) -> (NowPlayingStore, LibraryStore, FakeSource) {
        let clock = clock
        var state = Fixtures.state(at: clock.now, capabilities: capabilities)
        state.snapshot.isFavorite = favorite
        let source = FakeSource(id: .musicApp, displayName: "Music", state: state)
        // The source reports the new state, as Music does once it has it.
        source.stateAfterCommand = { command, state in
            var state = state
            if case .setFavorite(let value) = command { state.snapshot.isFavorite = value }
            return state
        }
        let nowPlaying = NowPlayingStore(sources: [source], now: { clock.now })
        nowPlaying.start()
        let library = LibraryStore(
            nowPlaying: nowPlaying,
            providers: [],
            now: { clock.now },
            // The HUD stays up for as long as the test looks at it.
            sleep: { _ in try await Task.sleep(for: .seconds(30)) }
        )
        return (nowPlaying, library, source)
    }

    @Test func aSaveIsSentAndConfirmedInTheSourcesWords() async throws {
        let (nowPlaying, library, source) = make(favorite: false)
        let work = try #require(nowPlaying.toggleSaveAndConfirm())
        await work.value
        #expect(source.performed == [.setFavorite(true)])
        #expect(library.notice?.kind == .saved)
        #expect(library.notice?.source == .musicApp)
        #expect(LibraryHUD.title(for: try #require(library.notice)) == "Added to Favorites")
        #expect(nowPlaying.snapshot.isFavorite == true)
    }

    @Test func anUnsaveIsConfirmedToo() async throws {
        let (nowPlaying, library, source) = make(favorite: true)
        await nowPlaying.toggleSaveAndConfirm()?.value
        #expect(source.performed == [.setFavorite(false)])
        #expect(library.notice?.kind == .unsaved)
    }

    @Test func anUnknownStateCountsAsUnsaved() async {
        let (nowPlaying, library, source) = make(favorite: nil)
        await nowPlaying.toggleSaveAndConfirm()?.value
        #expect(source.performed == [.setFavorite(true)])
        #expect(library.notice?.kind == .saved)
    }

    @Test func aRefusalIsNotConfirmed() async {
        let (nowPlaying, library, source) = make(favorite: false)
        source.failure = .timedOut
        await nowPlaying.toggleSaveAndConfirm()?.value
        #expect(source.performed == [.setFavorite(true)])
        #expect(library.notice == nil)
        #expect(nowPlaying.snapshot.isFavorite == false)
    }

    @Test func aSourceThatCantSaveIsLeftAlone() {
        let (nowPlaying, library, source) = make(favorite: false, capabilities: .transport)
        #expect(nowPlaying.toggleSaveAndConfirm() == nil)
        #expect(source.performed.isEmpty)
        #expect(library.notice == nil)
    }

    @Test func nowsMenuSavesThroughIt() async {
        let (nowPlaying, library, source) = make(favorite: false)
        TrackMenuPerformer.perform(.toggleSave, store: nowPlaying)
        await waitUntil { library.notice != nil }
        #expect(source.performed == [.setFavorite(true)])
        #expect(library.notice?.kind == .saved)
    }
}

@Suite("The explicit mark on the playing song")
struct TrackExplicitTests {
    @Test func isOffUnlessTheSourceSaysSo() {
        #expect(!Track(id: TrackID("a"), title: "A", artist: "B").isExplicit)
        #expect(Track(id: TrackID("a"), title: "A", artist: "B", isExplicit: true).isExplicit)
    }

    @Test func travelsBetweenTheNowAndListModels() {
        let song = Track(id: TrackID("spotify:track:1"), title: "A", artist: "B", isExplicit: true)
        #expect(LibraryTrack(song).isExplicit)
        #expect(Track(LibraryTrack(song)).isExplicit)
        #expect(!Track(LibraryTrack(Track(id: TrackID("x"), title: "A", artist: "B"))).isExplicit)
    }
}
