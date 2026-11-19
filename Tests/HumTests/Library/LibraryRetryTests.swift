import Foundation
import HumCore
@testable import HumSources
@testable import HumUI
import Testing

/// Fails each Play Now with the errors it’s given, in order, then succeeds.
@MainActor
final class RetryingLibrary: LibraryProvider {
    let sourceID = SourceID.demo
    let displayName = "Stub"
    var onChange: (@MainActor () -> Void)?
    let capabilities: SourceCapabilities = [.playItems]
    var errors: [LibraryError]
    private(set) var played: [TrackID] = []
    private(set) var attempts = 0

    init(errors: [LibraryError]) {
        self.errors = errors
    }

    func play(_ request: PlayRequest) async throws(LibraryError) {
        attempts += 1
        if !errors.isEmpty { throw errors.removeFirst() }
        guard case .track(let track, _) = request else { return }
        played.append(track.id)
    }
}

/// A failed Play Now says what to do next, and one that may pass offers Try
/// Again with the same request (DESIGN.md §4.6).
@MainActor
@Suite("Trying a failed action again")
struct LibraryRetryTests {
    let clock = TestClock()
    let song = LibraryTrack(id: TrackID("demo:night-bus"), title: "Night Bus", artist: "Juniper & Vale")

    func store(_ provider: RetryingLibrary) -> LibraryStore {
        let clock = clock
        let source = DemoSource(startsPlaying: false, startPosition: 0, latency: .zero, now: { clock.now })
        return LibraryStore(
            nowPlaying: NowPlayingStore(sources: [source], preferredSourceID: .demo, now: { clock.now }),
            providers: [provider],
            now: { clock.now },
            sleep: { _ in try await Task.sleep(for: .seconds(30)) }
        )
    }

    @Test func aTimeoutOffersTryAgainWhichRepeatsTheRequest() async throws {
        let provider = RetryingLibrary(errors: [.transient("Spotify took too long to answer.")])
        let library = store(provider)
        library.play(.track(song, in: nil))
        await waitUntil { library.failure != nil }
        let failure = try #require(library.failure)
        #expect(failure.canRetry)
        #expect(LibraryFailureBanner.actionTitle(failure) == "Try Again")

        library.retryFailure()
        #expect(library.failure == nil)
        await waitUntil { !provider.played.isEmpty }
        #expect(provider.played == [song.id])
        // Nothing failed the second time, so there's nothing to try again.
        library.retryFailure()
        await drainMainActor()
        #expect(provider.attempts == 2)
    }

    @Test func aFailureThatWontPassOffersNoTryAgain() async throws {
        let provider = RetryingLibrary(errors: [.failed("That song isn’t in the demo.")])
        let library = store(provider)
        library.play(.track(song, in: nil))
        await waitUntil { library.failure != nil }
        let failure = try #require(library.failure)
        #expect(!failure.canRetry)
        #expect(LibraryFailureBanner.actionTitle(failure) == nil)
    }

    @Test func aFixComesBeforeTryAgain() {
        let failure = LibraryFailure(message: "Open Spotify, then try again.", fix: .openApp(.spotifyApp, name: "Spotify"), canRetry: true)
        #expect(LibraryFailureBanner.actionTitle(failure) == "Open Spotify")
    }

    @Test func transientSourceErrorsOfferTryAgain() {
        #expect(LibraryError(.timedOut, app: "Music", source: .musicApp) == .transient("Music took too long to answer."))
        #expect(LibraryError(.timedOut, app: "Spotify", source: .spotifyApp) == .transient("Spotify took too long to answer."))
        #expect(LibraryError(.scriptFailed(code: -1708, message: ""), app: "Spotify", source: .spotifyApp) == .transient("Spotify couldn’t do that."))
    }
}
