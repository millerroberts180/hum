import Foundation

/// Where the player sat on one display.
///
/// The offset is measured from the display's visible frame (the area below the menu
/// bar and clear of the Dock), so a placement survives resolution and Dock changes.
public struct WindowPlacement: Codable, Equatable, Sendable {
    /// Distance from the visible frame's left edge to the window's left edge.
    public var offsetX: Double
    /// Distance from the visible frame's bottom edge to the window's bottom edge.
    public var offsetY: Double
    /// Side length of the square player, in points.
    public var side: Double
    public var surface: Surface
    /// Where the player is pinned on this display (DESIGN.md §4.5), or `nil` when
    /// it was dropped somewhere with snapping off.
    public var pin: PinPosition?

    public init(offsetX: Double, offsetY: Double, side: Double, surface: Surface = .now, pin: PinPosition? = nil) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.side = side
        self.surface = surface
        self.pin = pin
    }

    private enum CodingKeys: String, CodingKey {
        case offsetX, offsetY, side, surface, pin
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offsetX = try container.decode(Double.self, forKey: .offsetX)
        offsetY = try container.decode(Double.self, forKey: .offsetY)
        side = try container.decode(Double.self, forKey: .side)
        surface = container.lenient(.surface, default: .now)
        pin = container.lenient(.pin, default: nil)
    }
}
