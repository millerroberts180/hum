import Foundation
import HumCore
import Testing

/// Rediscover's Play plays the song or isn't there: Find, which it used to
/// open otherwise, is gone (DESIGN.md §6.5).
@Suite("Rediscover Play")
struct RediscoverPlayTests {
    private func entry(source: SourceID = .musicApp, trackID: String = "4F2A", title: String = "Harvest Moon", artist: String = "Neil Young") -> TopEntry {
        TopEntry(
            id: "song",
            title: title,
            subtitle: artist,
            plays: 9,
            listened: 2_000,
            sampleTrackID: TrackID(trackID),
            sampleSource: source
        )
    }

    @Test func aSongFromTheActiveSourcePlays() {
        let track = RediscoverPlay.track(for: entry(), activeSource: .musicApp, canPlayItems: true)
        #expect(track == LibraryTrack(id: TrackID("4F2A"), title: "Harvest Moon", artist: "Neil Young"))
    }

    @Test func aSongFromAnotherSourceHasNoPlay() {
        #expect(RediscoverPlay.track(for: entry(source: .spotifyApp), activeSource: .musicApp, canPlayItems: true) == nil)
    }

    @Test func aSourceThatCantPlayFromAListHasNoPlay() {
        #expect(RediscoverPlay.track(for: entry(), activeSource: .musicApp, canPlayItems: false) == nil)
    }

    @Test func noActiveSourceHasNoPlay() {
        #expect(RediscoverPlay.track(for: entry(), activeSource: nil, canPlayItems: true) == nil)
    }

    @Test func aListenWithoutAnIDHasNoPlay() {
        #expect(RediscoverPlay.track(for: entry(trackID: ""), activeSource: .musicApp, canPlayItems: true) == nil)
    }
}
