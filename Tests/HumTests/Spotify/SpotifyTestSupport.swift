import Foundation
@testable import HumCore
@testable import HumSources

/// Spotify's app as Hum puts it together: its source (a stand-in here that
/// starts the songs Spotify's app would, its track URIs) under a player and a
/// library store, which gives it the built-in one-song provider. Nothing
/// reaches Spotify.
@MainActor
struct SpotifyFixture {
    nonisolated static let uri = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"

    let clock = TestClock()
    let source: FakeSource
    let nowPlaying: NowPlayingStore
    let library: LibraryStore

    /// - Parameters:
    ///   - availability: Whether Spotify is installed and open.
    ///   - permission: What macOS has decided about Hum controlling Spotify.
    ///   - bundleID: The app the stand-in names, which Open Spotify looks for.
    ///   - others: Further sources, such as Music, alongside Spotify.
    ///   - otherProviders: Their libraries.
    init(
        availability: SourceAvailability = .running,
        permission: AutomationPermission = .granted,
        playing: Bool = true,
        bundleID: String? = SpotifyApp.bundleIdentifier,
        others: [FakeSource] = [],
        otherProviders: [any LibraryProvider] = [],
        preferredSourceID: SourceID? = nil
    ) {
        let clock = clock
        let state = availability == .notInstalled
            ? SourceState.notInstalled
            : Fixtures.state(
                track: Fixtures.track(Self.uri),
                status: playing ? .playing : .paused,
                at: clock.now,
                availability: availability,
                permission: permission,
                capabilities: SpotifyApp.capabilities
            )
        source = FakeSource(id: .spotifyApp, displayName: SpotifyApp.displayName, appBundleIdentifier: bundleID, state: state)
        source.links = (SpotifyApp.shareLink(for:), SpotifyApp.revealURL(for:))
        source.playableSong = { SpotifyApp.playScript(forTrack: $0) != nil }
        nowPlaying = NowPlayingStore(sources: [source] + others, preferredSourceID: preferredSourceID, now: { clock.now })
        nowPlaying.start()
        library = LibraryStore(
            nowPlaying: nowPlaying,
            providers: otherProviders,
            now: { clock.now },
            sleep: { _ in }
        )
    }

    /// A Spotify song as Echo and Listening History hand it to Play Now.
    nonisolated static func song(_ uri: String = uri) -> LibraryTrack {
        LibraryTrack(id: TrackID(uri), title: "Undertow", artist: "Low Tide", album: "Harbor")
    }
}
