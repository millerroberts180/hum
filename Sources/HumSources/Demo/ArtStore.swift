import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// Encoded demo art, kept so each picture is painted once per size. The store
/// is bounded by bytes and lets the least recently used picture go first.
final class ArtStore: Sendable {
    static let shared = ArtStore(budget: 32 << 20)

    private struct State {
        var entries: [String: Data] = [:]
        /// Least recently used first.
        var order: [String] = []
        var bytes = 0
    }

    private let state = Mutex(State())
    private let budget: Int

    init(budget: Int) {
        self.budget = budget
    }

    /// The PNG for `key` at `side` pixels, painting it with `render` the first
    /// time. Two callers asking at once may both paint; the pictures are
    /// identical, so the second is simply dropped.
    func png(_ key: String, side: Int, render: () -> CGImage?) -> Data? {
        let id = "\(key)@\(side)"
        let hit = state.withLock { state -> Data? in
            guard let data = state.entries[id] else { return nil }
            if let index = state.order.firstIndex(of: id) {
                state.order.append(state.order.remove(at: index))
            }
            return data
        }
        if let hit { return hit }
        guard let image = render(), let data = Self.encode(image) else { return nil }
        state.withLock { state in
            guard state.entries[id] == nil else { return }
            state.entries[id] = data
            state.order.append(id)
            state.bytes += data.count
            while state.bytes > budget, state.order.count > 1 {
                let oldest = state.order.removeFirst()
                state.bytes -= state.entries.removeValue(forKey: oldest)?.count ?? 0
            }
        }
        return data
    }

    var count: Int {
        state.withLock { $0.entries.count }
    }

    static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
