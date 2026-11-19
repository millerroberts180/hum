import AppKit
import HumCore

/// Tells listening history when the Mac sleeps and wakes, so time asleep never
/// counts toward a listen.
@MainActor
public final class HistorySleepObserver {
    private let history: ListeningHistory
    private var observers: [any NSObjectProtocol] = []

    public init(history: ListeningHistory) {
        self.history = history
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.history.systemWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.history.systemDidWake() }
            },
        ]
    }

    isolated deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }
}
