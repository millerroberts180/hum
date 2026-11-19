import Foundation
import HumCore
import HumSources
import Testing

@Suite("Polling")
struct PollPolicyTests {
    @Test func neverPollsWhilePausedOrWithoutPermission() {
        let policy = PollPolicy()
        #expect(policy.interval(isPlaying: false, canQuery: true, remaining: 10) == nil)
        #expect(policy.interval(isPlaying: true, canQuery: false, remaining: 10) == nil)
    }

    @Test func whileTrustedPollsJustAfterTheTrackShouldEnd() {
        let policy = PollPolicy()
        #expect(policy.interval(isPlaying: true, canQuery: true, remaining: 8) == 8 + PollPolicy.endOfTrackSlack)
        #expect(policy.interval(isPlaying: true, canQuery: true, remaining: 600) == PollPolicy.driftInterval)
        #expect(policy.interval(isPlaying: true, canQuery: true, remaining: nil) == PollPolicy.driftInterval)
        #expect(policy.interval(isPlaying: true, canQuery: true, remaining: -5) == PollPolicy.minimumInterval)
    }

    @Test func anUnannouncedChangeTightensPollingUntilTheNextNotification() {
        var policy = PollPolicy()
        policy.pollFoundUnannouncedChange()
        #expect(policy.interval(isPlaying: true, canQuery: true, remaining: 100) == PollPolicy.untrustedInterval)
        #expect(policy.interval(isPlaying: true, canQuery: true, remaining: 2) == PollPolicy.untrustedInterval)
        policy.notificationReceived()
        #expect(policy.notificationsTrusted)
        // Back to the usual pace: drift checks, and just after the song ends.
        #expect(policy.interval(isPlaying: true, canQuery: true, remaining: 100) == 20)
        #expect(policy.interval(isPlaying: true, canQuery: true, remaining: 2) == 3.5)
    }

    /// In front, the app's shuffle and repeat change without a notification,
    /// so Hum reads it every second, paused or not (§13.34).
    @Test func whileTheAppIsInFrontPollsEverySecond() {
        var policy = PollPolicy()
        #expect(policy.interval(isPlaying: false, isAppFrontmost: true, canQuery: true, remaining: 10) == PollPolicy.frontmostInterval)
        #expect(policy.interval(isPlaying: true, isAppFrontmost: true, canQuery: true, remaining: 600) == PollPolicy.frontmostInterval)
        #expect(policy.interval(isPlaying: false, isAppFrontmost: true, canQuery: false, remaining: 10) == nil)
        policy.pollFoundUnannouncedChange()
        #expect(policy.interval(isPlaying: true, isAppFrontmost: true, canQuery: true, remaining: 100) == PollPolicy.frontmostInterval)
        #expect(PollPolicy.frontmostInterval == 1)
    }

    @Test func onlyTrackAndPlayStateCountAsUnannounced() {
        let date = Date()
        let known = PlaybackSnapshot(track: Fixtures.track("a"), status: .playing, timestamp: date, volume: 0.2)
        var volumeOnly = known
        volumeOnly.volume = 0.9
        #expect(!PollPolicy.isUnannouncedChange(polled: volumeOnly, known: known))
        var skipped = known
        skipped.track = Fixtures.track("b")
        #expect(PollPolicy.isUnannouncedChange(polled: skipped, known: known))
        var paused = known
        paused.status = .paused
        #expect(PollPolicy.isUnannouncedChange(polled: paused, known: known))
    }
}
