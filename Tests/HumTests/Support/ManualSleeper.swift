import Foundation

/// A stand-in for `Task.sleep` that a test ends by hand: each sleep waits
/// until `elapse()`, or throws once its task is cancelled.
@MainActor
final class ManualSleeper {
    /// Every duration asked for, in order.
    private(set) var requested: [Duration] = []
    private var pending: [(id: Int, continuation: CheckedContinuation<Void, any Error>)] = []
    private var nextID = 0

    /// How many sleeps are waiting now.
    var waiting: Int { pending.count }

    func sleep(_ duration: Duration) async throws {
        requested.append(duration)
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append((id, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    /// Ends every sleep waiting now.
    func elapse() {
        let ended = pending
        pending = []
        for sleep in ended { sleep.continuation.resume() }
    }

    private func cancel(_ id: Int) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
