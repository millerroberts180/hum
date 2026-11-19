import CoreGraphics
import HumCore

/// Corner radii. All corners in Hum use the continuous (squircle) curve.
nonisolated enum Radius {
    /// The player's own corners. On macOS 15 they're the system window radius.
    /// On macOS 26 they scale with its size, within limits, so a small player
    /// doesn't look like a pill and a large one doesn't look like a slab.
    static func panel(side: CGFloat) -> CGFloat {
        if #available(macOS 26, *) {
            return min(26, max(12, (side * 0.075).rounded()))
        }
        return systemWindow
    }

    /// The system window radius on macOS 15.
    static let systemWindow: CGFloat = 10

    /// Cards, popovers, Strip's window.
    static let card: CGFloat = 12
    /// Buttons with a backing, text fields, chips.
    static let control: CGFloat = 8
    /// Artwork up to 40 pt (list rows).
    static let artSmall: CGFloat = 4
    /// Artwork 41–120 pt (cards, Title's cover).
    static let artMedium: CGFloat = 6
}
