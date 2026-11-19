import HumCore
import SwiftUI

private nonisolated struct DemoAttributionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The service the demo names (`--demo-attribution`), or `nil`. The app
    /// provides it to every window, so a demo that names Spotify does what
    /// Spotify can and can't.
    public nonisolated var demoAttribution: String? {
        get { self[DemoAttributionKey.self] }
        set { self[DemoAttributionKey.self] = newValue }
    }
}
