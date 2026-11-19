import Foundation

/// A clock for back-off tests, moved by hand.
@MainActor
final class ManualClock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Lets main-actor work that was started but not awaited, such as a store's
/// load tasks, run to its end.
@MainActor
func drainMainActor() async {
    for _ in 0..<20 { await Task.yield() }
}
