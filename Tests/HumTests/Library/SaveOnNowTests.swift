import Foundation
@testable import HumCore
@testable import HumSources
@testable import HumUI
import Testing

/// Spotify's app has no way to save a song, so Hum offers no Save for it
/// anywhere; Music's Favorite is its own (DESIGN.md §1.3).
@MainActor
@Suite("Save on Now")
struct SaveOnNowTests {
    let clock = TestClock()

    /// A player playing a song from one app, with Hum's library for it attached.
    func playing(
        _ id: SourceID,
        _ name: String,
        capabilities: SourceCapabilities,
        providers: [any LibraryProvider] = [],
        playsSongs: Bool = false
    ) -> (NowPlayingStore, LibraryStore, FakeSource) {
        let clock = clock
        var state = Fixtures.state(track: Fixtures.track("spotify:track:4uLU6hMCjMI75M1A2tKUQC"), at: clock.now, capabilities: capabilities)
        state.snapshot.isFavorite = false
        let source = FakeSource(id: id, displayName: name, state: state)
        source.stateAfterCommand = { command, state in
            var state = state
            if case .setFavorite(let value) = command { state.snapshot.isFavorite = value }
            return state
        }
        if playsSongs { source.playableSong = { SpotifyApp.playScript(forTrack: $0) != nil } }
        let nowPlaying = NowPlayingStore(sources: [source], now: { clock.now })
        nowPlaying.start()
        let library = LibraryStore(
            nowPlaying: nowPlaying,
            providers: providers,
            now: { clock.now },
            sleep: { _ in try await Task.sleep(for: .seconds(30)) }
        )
        return (nowPlaying, library, source)
    }

    func spotify() -> (NowPlayingStore, LibraryStore, FakeSource) {
        playing(.spotifyApp, "Spotify", capabilities: SpotifyApp.capabilities, playsSongs: true)
    }

    @Test func spotifyCantSaveAndMusicCan() {
        #expect(!SpotifyApp.capabilities.contains(.favorite))
        let (_, library, _) = spotify()
        #expect(library.provider is SourceSongProvider)
        #expect(!library.capabilities.contains(.saveItems))
        #expect(MusicApp.capabilities.contains(.favorite))
    }

    @Test func spotifysShortcutDoesNothingAndShowsNoHUD() async {
        let (nowPlaying, library, source) = spotify()
        #expect(!nowPlaying.capabilities.contains(.favorite))
        #expect(nowPlaying.toggleSaveAndConfirm() == nil)
        await drainMainActor()
        #expect(source.performed.isEmpty)
        #expect(library.notice == nil)
        #expect(nowPlaying.snapshot.isFavorite == false)
    }

    @Test func spotifysNowMenuHasNoSave() throws {
        let (nowPlaying, library, _) = spotify()
        let menu = try #require(TrackMenu.current(nowPlaying))
        #expect(!menu.actions.contains(.toggleSave))
        withExtendedLifetime(library) {}
    }

    @Test func musicsShortcutFavoritesAndSaysSo() async throws {
        let (nowPlaying, library, source) = playing(.musicApp, "Music", capabilities: MusicApp.capabilities)
        await nowPlaying.toggleSaveAndConfirm()?.value
        #expect(source.performed == [.setFavorite(true)])
        #expect(LibraryHUD.title(for: try #require(library.notice)) == "Added to Favorites")
        let menu = try #require(TrackMenu.current(nowPlaying))
        #expect(menu.actions.contains(.toggleSave))
        #expect(menu.title(for: .toggleSave) == "Remove from Favorites")
    }
}

@MainActor
@Suite("Save on Now in the demo")
struct DemoSaveOnNowTests {
    @Test func savingOnNowShowsInTheLists() async {
        let clock = TestClock()
        let source = DemoSource(startsPlaying: false, startPosition: 0, latency: .zero, now: { clock.now })
        let library = DemoLibrary(source: source, listLatency: .zero)
        let nowPlaying = NowPlayingStore(sources: [source], preferredSourceID: .demo, now: { clock.now })
        let store = LibraryStore(nowPlaying: nowPlaying, providers: [library], now: { clock.now }, sleep: { _ in })
        nowPlaying.start()
        await drainMainActor()
        let track = try! #require(nowPlaying.track)
        let wasSaved = nowPlaying.snapshot.isFavorite ?? false
        await nowPlaying.perform(.setFavorite(!wasSaved))
        await waitUntil { store.savedTrackIDs[track.id] == !wasSaved }
        #expect(store.isSaved(LibraryTrack(track, artwork: nil)) == !wasSaved)
    }
}
