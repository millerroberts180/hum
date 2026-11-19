import Foundation
import HumCore
import Testing

@Suite("Capabilities")
struct CapabilityTests {
    @Test func commandsMapToCapabilities() {
        let transport = SourceCapabilities.transport
        #expect(transport.supports(.togglePlayPause))
        #expect(transport.supports(.next))
        #expect(!transport.supports(.seek(to: 10)))
        #expect(!transport.supports(.setVolume(0.5)))
        #expect(!transport.supports(.setFavorite(true)))
        #expect(!transport.supports(.setRepeat(.off)))
    }

    @Test func repeatCyclesThroughWhatTheSourceOffers() {
        let onOff: SourceCapabilities = [.repeatAll]
        #expect(onOff.repeatCycle == [.off, .all])
        #expect(onOff.nextRepeatMode(after: .all) == .off)
        #expect(!onOff.supports(.setRepeat(.one)))

        let full: SourceCapabilities = [.repeatAll, .repeatOne]
        #expect(full.nextRepeatMode(after: .off) == .all)
        #expect(full.nextRepeatMode(after: .all) == .one)
        #expect(full.nextRepeatMode(after: .one) == .off)

        // Hum's repeat one, for an app that repeats only on or off, cycles as
        // an app's own would (DESIGN.md §5.2).
        let restarting: SourceCapabilities = [.repeatAll, .repeatOne, .repeatOneByRestart]
        #expect(restarting.repeatCycle == [.off, .all, .one])
        #expect(restarting.supports(.setRepeat(.one)))

        #expect(SourceCapabilities.transport.nextRepeatMode(after: .off) == nil)
    }

    @Test func effectiveCapabilitiesFollowAvailabilityAndPermission() {
        let date = Date()
        let all = Fixtures.everything.union(.launch)
        #expect(Fixtures.state(at: date, capabilities: all).effectiveCapabilities == all)
        #expect(Fixtures.state(at: date, permission: .denied, capabilities: all).effectiveCapabilities.isEmpty)
        // A closed app can only be started, and only by play.
        #expect(Fixtures.state(at: date, availability: .notRunning, capabilities: all).effectiveCapabilities == [.playPause, .launch])
        #expect(Fixtures.state(at: date, availability: .notRunning, capabilities: Fixtures.everything).effectiveCapabilities.isEmpty)
        #expect(Fixtures.state(at: date, availability: .notInstalled, capabilities: all).effectiveCapabilities.isEmpty)
    }
}
