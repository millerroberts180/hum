/// Which surface is current, with edge-aware stepping.
public struct SurfaceNavigation: Equatable, Sendable {
    public private(set) var current: Surface

    public init(current: Surface = .now) {
        self.current = current
    }

    public var canGoForward: Bool { current.index < Surface.allCases.count - 1 }
    public var canGoBack: Bool { current.index > 0 }

    /// - Returns: `false` if `surface` was already current.
    @discardableResult
    public mutating func go(to surface: Surface) -> Bool {
        guard surface != current else { return false }
        current = surface
        return true
    }

    /// Step toward Status. Returns `false` at the last surface.
    @discardableResult
    public mutating func forward() -> Bool {
        guard let next = Surface(index: current.index + 1) else { return false }
        current = next
        return true
    }

    /// Step toward Now. Returns `false` at the first surface.
    @discardableResult
    public mutating func back() -> Bool {
        guard let previous = Surface(index: current.index - 1) else { return false }
        current = previous
        return true
    }
}
