import Foundation
import HumCore
import Testing

@Suite("Source selection")
struct SourceSelectorTests {
    let spotify = SourceID.spotifyApp
    let music = SourceID.musicApp
    let date = Date(timeIntervalSinceReferenceDate: 0)

    func candidate(
        _ id: SourceID,
        _ availability: SourceAvailability = .running,
        status: PlaybackStatus = .paused,
        track: Bool = true,
        startedAt: TimeInterval? = nil
    ) -> SourceSelector.Candidate {
        SourceSelector.Candidate(
            id: id,
            state: Fixtures.state(track: track ? Fixtures.track() : nil, status: status, at: date, availability: availability),
            startedPlayingAt: startedAt.map { date.addingTimeInterval($0) }
        )
    }

    @Test func anInstalledPreferredSourceAlwaysWins() {
        let candidates = [candidate(spotify, status: .playing), candidate(music, .notRunning)]
        #expect(SourceSelector.select(from: candidates, current: spotify, preferred: music, lastActive: nil) == music)
    }

    @Test func aMissingPreferredSourceIsIgnored() {
        let candidates = [candidate(spotify, status: .playing), candidate(music, .notInstalled)]
        #expect(SourceSelector.select(from: candidates, current: nil, preferred: music, lastActive: nil) == spotify)
    }

    @Test func followsWhateverIsPlaying() {
        let candidates = [candidate(spotify), candidate(music, status: .playing)]
        #expect(SourceSelector.select(from: candidates, current: spotify, preferred: nil, lastActive: spotify) == music)
    }

    @Test func keepsTheCurrentSourceWhenBothPlay() {
        let candidates = [candidate(spotify, status: .playing, startedAt: 1), candidate(music, status: .playing, startedAt: 5)]
        #expect(SourceSelector.select(from: candidates, current: spotify, preferred: nil, lastActive: nil) == spotify)
        #expect(SourceSelector.select(from: candidates, current: nil, preferred: nil, lastActive: nil) == music)
    }

    @Test func aPausedTrackStaysPut() {
        // Music launching with a track loaded doesn't steal a paused Spotify track.
        let candidates = [candidate(spotify), candidate(music)]
        #expect(SourceSelector.select(from: candidates, current: spotify, preferred: nil, lastActive: music) == spotify)
    }

    @Test func fallsBackToTheLastActiveThenTheFirstInstalled() {
        let idle = [candidate(spotify, .notRunning, track: false), candidate(music, .notRunning, track: false)]
        #expect(SourceSelector.select(from: idle, current: nil, preferred: nil, lastActive: music) == music)
        #expect(SourceSelector.select(from: idle, current: nil, preferred: nil, lastActive: nil) == spotify)
        #expect(SourceSelector.select(from: [candidate(spotify, .notInstalled)], current: nil, preferred: nil, lastActive: nil) == nil)
    }
}
