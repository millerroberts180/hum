import SwiftUI

// Written out by hand rather than with `@Entry`: the Command Line Tools don't ship
// SwiftUI's macro plugins.

private nonisolated struct SurfaceIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

private nonisolated struct PlayerMetricsKey: EnvironmentKey {
    static let defaultValue = PlayerMetrics(side: PlayerMetrics.defaultSide)
}

private nonisolated struct PlayerActionsKey: EnvironmentKey {
    static let defaultValue = PlayerActions()
}

private nonisolated struct HumColorContextKey: EnvironmentKey {
    static let defaultValue = HumColorContext.material
}

private nonisolated struct HumAccentKey: EnvironmentKey {
    static let defaultValue = AccentColors.fallback
}

extension EnvironmentValues {
    /// Whether this surface is the one on screen. Surfaces should pause timelines
    /// and other work when it's `false`.
    nonisolated var surfaceIsActive: Bool {
        get { self[SurfaceIsActiveKey.self] }
        set { self[SurfaceIsActiveKey.self] = newValue }
    }

    nonisolated var playerMetrics: PlayerMetrics {
        get { self[PlayerMetricsKey.self] }
        set { self[PlayerMetricsKey.self] = newValue }
    }

    nonisolated var playerActions: PlayerActions {
        get { self[PlayerActionsKey.self] }
        set { self[PlayerActionsKey.self] = newValue }
    }

    /// Whether views are drawn over artwork or on material. Decides how every
    /// `HumColor` role resolves.
    nonisolated var humColorContext: HumColorContext {
        get { self[HumColorContextKey.self] }
        set { self[HumColorContextKey.self] = newValue }
    }

    /// The current accent, adjusted for dark and light backdrops.
    nonisolated var humAccent: AccentColors {
        get { self[HumAccentKey.self] }
        set { self[HumAccentKey.self] = newValue }
    }
}
