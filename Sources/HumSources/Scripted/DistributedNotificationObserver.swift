import Foundation
import HumCore

/// Observes one distributed notification and delivers the parsed snapshot on the main actor.
///
/// Uses the selector API so it can ask for `.deliverImmediately`: Hum is a
/// background agent that is almost never the active app, and the default behavior
/// would hold notifications until it activates.
@MainActor
final class DistributedNotificationObserver: NSObject {
    private let parse: @Sendable ([AnyHashable: Any]) -> PlaybackSnapshot
    private let deliver: @MainActor (PlaybackSnapshot) -> Void
    private let center = DistributedNotificationCenter.default()

    init(
        name: Notification.Name,
        parse: @escaping @Sendable ([AnyHashable: Any]) -> PlaybackSnapshot,
        deliver: @escaping @MainActor (PlaybackSnapshot) -> Void
    ) {
        self.parse = parse
        self.deliver = deliver
        super.init()
        center.addObserver(
            self,
            selector: #selector(receive(_:)),
            name: name,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    func invalidate() {
        center.removeObserver(self)
    }

    @objc private nonisolated func receive(_ notification: Notification) {
        let value = parse(notification.userInfo ?? [:])
        if Thread.isMainThread {
            MainActor.assumeIsolated { deliver(value) }
        } else {
            Task { @MainActor in self.deliver(value) }
        }
    }
}
