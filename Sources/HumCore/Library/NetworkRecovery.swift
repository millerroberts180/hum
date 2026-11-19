import Foundation
import Network

/// Whether the Mac has a usable network path.
///
/// Play and Find retried their lists when the network came back; they're gone
/// (DESIGN.md §13.9), and nothing reads this any more. It stays until the app
/// stops passing `SystemNetworkPath()` to `LibraryStore`.
@MainActor
public protocol NetworkPathSource: AnyObject {
    /// Starts reporting: `update` gets the current state, then every change.
    func start(_ update: @escaping @MainActor (_ isSatisfied: Bool) -> Void)
    func stop()
}

/// The system's network path, from `NWPathMonitor`.
public final class SystemNetworkPath: NetworkPathSource {
    private var monitor: NWPathMonitor?

    public init() {}

    public func start(_ update: @escaping @MainActor (_ isSatisfied: Bool) -> Void) {
        stop()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let isSatisfied = path.status == .satisfied
            MainActor.assumeIsolated { update(isSatisfied) }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
