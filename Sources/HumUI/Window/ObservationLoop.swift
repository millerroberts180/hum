import Observation

/// Run `body` now and again whenever any observable value it read changes.
///
/// `body` should hold its owner weakly; once it stops reading anything (because
/// the owner is gone), it stops being called.
@MainActor
public func observeChanges(_ body: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking {
        body()
    } onChange: {
        Task { @MainActor in observeChanges(body) }
    }
}
