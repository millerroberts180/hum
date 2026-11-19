import Foundation
import HumCore
import Testing

@Suite("Pacing widget reloads")
struct WidgetReloadThrottleTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func theFirstChangeReloadsAtOnce() {
        var throttle = WidgetReloadThrottle()
        #expect(throttle.interval == 2)
        #expect(throttle.change(at: at(0)) == .reloadNow)
        #expect(throttle.lastReload == at(0))
        #expect(throttle.pendingAt == nil)
    }

    @Test func changesInsideTheIntervalFoldIntoOneReloadAtItsEnd() {
        var throttle = WidgetReloadThrottle()
        _ = throttle.change(at: at(0))
        #expect(throttle.change(at: at(0.5)) == .reload(at: at(2)))
        #expect(throttle.change(at: at(1)) == .alreadyPending)
        #expect(throttle.change(at: at(1.9)) == .alreadyPending)
        #expect(throttle.pendingAt == at(2))
        throttle.didReload(at: at(2))
        #expect(throttle.pendingAt == nil)
        #expect(throttle.lastReload == at(2))
        // The next change inside the new interval waits for its end.
        #expect(throttle.change(at: at(2.5)) == .reload(at: at(4)))
    }

    @Test func aChangeAfterAQuietSpellReloadsAtOnce() {
        var throttle = WidgetReloadThrottle()
        _ = throttle.change(at: at(0))
        #expect(throttle.change(at: at(2)) == .reloadNow)
        #expect(throttle.change(at: at(60)) == .reloadNow)
        #expect(throttle.lastReload == at(60))
    }

    @Test func neverMoreThanOneReloadPerInterval() {
        var throttle = WidgetReloadThrottle()
        var reloads: [Date] = []
        // A change every 0.3 s for 10 s, with each waiting reload run when due.
        for step in 0...33 {
            let now = at(Double(step) * 0.3)
            if let due = throttle.pendingAt, due <= now {
                throttle.didReload(at: due)
                reloads.append(due)
            }
            switch throttle.change(at: now) {
            case .reloadNow: reloads.append(now)
            case .reload, .alreadyPending: break
            }
        }
        for (earlier, later) in zip(reloads, reloads.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) >= 2 - 1e-9)
        }
        #expect(reloads.count >= 5)
        // The last change is still waiting to land.
        #expect(throttle.pendingAt != nil)
    }

    @Test func flushingClearsTheWaitingReload() {
        var throttle = WidgetReloadThrottle()
        _ = throttle.change(at: at(0))
        _ = throttle.change(at: at(1))
        throttle.flush(at: at(1.5))
        #expect(throttle.pendingAt == nil)
        #expect(throttle.lastReload == at(1.5))
    }
}
