import Foundation

/// Waits until `condition` holds, letting main-actor work that was started
/// but not awaited run in the meantime. Gives up after 2,000 turns of about a
/// millisecond each, so the test's own expectation reports what never
/// happened. It counts turns rather than time: when other tests keep the main
/// actor busy, the work being waited for slows down too, and a clock would
/// give up on it early.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    var turns = 0
    while !condition(), turns < 2_000 {
        turns += 1
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}
