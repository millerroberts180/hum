import SwiftUI

/// Shared objects the composition root puts in every window's environment beyond
/// the store and settings, such as the library or the listening history. A feature
/// registers its object here once instead of widening each window's initializer.
public final class AppServices {
    private var injectors: [(AnyView) -> AnyView] = []

    public init() {}

    /// Adds `object` to the environment of every window. Call it before the app
    /// starts: a window that has already rendered doesn't pick up later objects.
    public func provide<Object: AnyObject & Observable>(_ object: Object) {
        injectors.append { AnyView($0.environment(object)) }
    }

    /// Sets `keyPath` to `value` in the environment of every window, with the
    /// same timing rule as objects.
    public func provide<Value>(_ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value) {
        injectors.append { AnyView($0.environment(keyPath, value)) }
    }

    /// `content` with every provided object in its environment.
    public func inject(_ content: some View) -> AnyView {
        injectors.reduce(AnyView(content)) { view, inject in inject(view) }
    }
}
