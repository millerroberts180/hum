import Foundation

/// How the player behaves. Kept apart from how it looks so the two can change
/// independently (a style never changes behavior, and vice versa).
public struct BehaviorSettings: Codable, Equatable, Sendable {
    public var visibility: PlayerVisibility = .pinned
    public var alwaysOnTop = true
    public var showOnAllSpaces = true
    /// Throw the window and it settles in the nearest corner or at top center.
    /// Off, it stays exactly where it's dropped.
    public var snapToCorners = true
    /// A two-finger horizontal swipe moves between Now, Echo, and Status.
    public var swipeBetweenSurfaces = true
    /// On the Now artwork, a two-finger horizontal swipe skips to the next or
    /// previous track instead (DESIGN.md §4.2). Off by default.
    public var swipeToSkip = false
    /// What the time at the trailing end of the seek bar shows. Clicking it
    /// switches, and the choice is kept.
    public var trailingTime: TrailingTime = .remaining

    /// The seek bar's trailing time: what's left of the song, or its length.
    public enum TrailingTime: String, Codable, Sendable, CaseIterable {
        case remaining, total

        public var toggled: TrailingTime {
            self == .remaining ? .total : .remaining
        }
    }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case visibility, alwaysOnTop, showOnAllSpaces, snapToCorners
        case swipeBetweenSurfaces, swipeToSkip, trailingTime
    }

    /// Keys no longer kept, such as the old track-change delay, are ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BehaviorSettings()
        visibility = container.lenient(.visibility, default: defaults.visibility)
        alwaysOnTop = container.lenient(.alwaysOnTop, default: defaults.alwaysOnTop)
        showOnAllSpaces = container.lenient(.showOnAllSpaces, default: defaults.showOnAllSpaces)
        snapToCorners = container.lenient(.snapToCorners, default: defaults.snapToCorners)
        swipeBetweenSurfaces = container.lenient(.swipeBetweenSurfaces, default: defaults.swipeBetweenSurfaces)
        swipeToSkip = container.lenient(.swipeToSkip, default: defaults.swipeToSkip)
        trailingTime = container.lenient(.trailingTime, default: defaults.trailingTime)
    }
}
