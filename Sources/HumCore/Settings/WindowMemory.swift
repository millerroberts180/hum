/// Per-display window placements.
public struct WindowMemory: Codable, Equatable, Sendable {
    /// Keyed by a stable display identifier (the display's UUID when available).
    public var placements: [String: WindowPlacement] = [:]
    /// The display the player was last on.
    public var lastDisplay: String?
    /// The last surface shown anywhere, used for displays without a placement.
    public var lastSurface: Surface = .now
    /// The size each style was left at on each display: display identifier, then
    /// style identifier.
    public var styleSizes: [String: [String: PlayerSize]] = [:]
    /// Where the player hung under the menu bar in Tucked mode on each display:
    /// the distance from the visible frame's left edge to the window's center.
    public var tuckedCenters: [String: Double] = [:]

    public init() {}

    /// The size `style` was left at on `display`, if it has one there.
    public func size(for style: PlayerStyleID, on display: String) -> PlayerSize? {
        styleSizes[display]?[style.rawValue]
    }

    public mutating func setSize(_ size: PlayerSize, for style: PlayerStyleID, on display: String) {
        styleSizes[display, default: [:]][style.rawValue] = size
    }

    private enum CodingKeys: String, CodingKey {
        case placements, lastDisplay, lastSurface
        case styleSizes, tuckedCenters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placements = container.lenient(.placements, default: [:])
        lastDisplay = container.lenient(.lastDisplay, default: nil)
        lastSurface = container.lenient(.lastSurface, default: .now)
        // Entry by entry, so a size that can't be read, or one saved for a
        // style Hum no longer has (Glass, Data and Session, retired
        // 2026-11-08, DESIGN.md §13.19), drops only itself.
        let sizes: [String: LenientValue<[String: LenientValue<PlayerSize>]>] = container.lenient(.styleSizes, default: [:])
        styleSizes = sizes.compactMapValues { display in
            display.value.map { entries in
                entries.filter { PlayerStyleID(rawValue: $0.key) != nil }.compactMapValues(\.value)
            }
        }
        tuckedCenters = container.lenient(.tuckedCenters, default: [:])
    }
}
