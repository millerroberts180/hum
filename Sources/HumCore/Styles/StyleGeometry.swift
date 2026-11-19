/// A player window size, in points.
public struct PlayerSize: Codable, Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(side: Double) {
        self.init(width: side, height: side)
    }

    public var shortSide: Double { min(width, height) }
}

/// The shape a style's window takes (DESIGN.md §7). Only one dimension can be
/// dragged: the side of a square, or the width of the others, whose height
/// follows it.
public enum StyleShape: Equatable, Sendable {
    /// A square whose side stays within `sides`.
    case square(sides: ClosedRange<Double>)
    /// A short bar of a fixed `height`, `widths` wide.
    case bar(height: Double, widths: ClosedRange<Double>)
    /// A portrait card, `widths` wide: a square cover as wide as the window
    /// less its insets, with `controlsHeight` of controls under it, so the
    /// window is the width plus `controlsHeight` tall.
    case portrait(widths: ClosedRange<Double>, controlsHeight: Double)
    /// A landscape card, `widths` wide and `heightRatio` of its width tall.
    case landscape(widths: ClosedRange<Double>, heightRatio: Double)

    /// The range of the dimension that can be dragged: a square's side, or
    /// the other shapes' width.
    public var widths: ClosedRange<Double> {
        switch self {
        case .square(let sides): sides
        case .bar(_, let widths), .portrait(let widths, _), .landscape(let widths, _): widths
        }
    }

    /// Whether only a horizontal drag resizes it, from its sides or corners:
    /// a bar, whose height is fixed, and a landscape card, whose height
    /// follows its width. A square or a portrait takes a drag along any edge.
    public var resizesSideways: Bool {
        switch self {
        case .bar, .landscape: true
        case .square, .portrait: false
        }
    }

    /// The size of this shape at `width` (a square's side), clamped to its range.
    public func size(width: Double) -> PlayerSize {
        let width = StyleGeometry.clamp(width, to: widths)
        return switch self {
        case .square: PlayerSize(side: width)
        case .bar(let height, _): PlayerSize(width: width, height: height)
        case .portrait(_, let controlsHeight): PlayerSize(width: width, height: width + controlsHeight)
        case .landscape(_, let heightRatio): PlayerSize(width: width, height: width * heightRatio)
        }
    }

    /// `size` turned into this shape. A square from a bar or a landscape card
    /// takes its longer side, its width; a square from a portrait takes the
    /// portrait's width, so the cover keeps its size. The other shapes take
    /// the width of whatever they came from.
    public func clamp(_ size: PlayerSize) -> PlayerSize {
        guard size.width.isFinite, size.height.isFinite else { return self.size(width: .nan) }
        let isPortraitLike = size.height > size.width
        return switch self {
        case .square: self.size(width: isPortraitLike ? size.width : max(size.width, size.height))
        case .bar, .portrait, .landscape: self.size(width: size.width)
        }
    }

    /// Where a resize the system runs comes to, from the window's edge
    /// outside Hum's handles: `proposed`, from `current`, held to this shape
    /// and its range. The width counts, as with the handles, unless only the
    /// height moved: then a square's side, or a portrait's width, follows
    /// the height. A bar and a landscape card change only with the width.
    public func size(resizedTo proposed: PlayerSize, from current: PlayerSize) -> PlayerSize {
        let onlyHeightMoved = proposed.width == current.width && proposed.height != current.height
        let width = switch self {
        case .square where onlyHeightMoved: proposed.height
        case .portrait(_, let controlsHeight) where onlyHeightMoved: proposed.height - controlsHeight
        case .square, .bar, .portrait, .landscape: proposed.width
        }
        return size(width: width)
    }
}

/// The shapes and sizes each style's window can take (DESIGN.md §7).
public enum StyleGeometry {
    /// Art Only's range, the one square style.
    public static let squareSides: ClosedRange<Double> = 168...640
    /// Where the large size class begins (DESIGN.md §6.1).
    public static let largeSide: Double = 380
    /// The square Title, Text, Strip and Wide grow to for History and Status
    /// (DESIGN.md §7.2).
    public static let surfaceSide: Double = 300
    /// Big Art's room under the cover (DESIGN.md §7). The window is the width
    /// plus this; the cover's inset above it and its gap below take the same
    /// 12 (`Spacing.m`) the cover is narrower than the width by, so this is
    /// the card's stack and `Spacing.m` below it. The stack measures 149 where
    /// its type is at M or L (from 240 wide), with the album and every
    /// control, and 145 at S.
    public static let bigArtControlsHeight: Double = 161

    /// The size a style opens at before the user has resized it. Menu Bar has
    /// no window, so it answers with Art Only's.
    public static func defaultSize(for style: PlayerStyleID) -> PlayerSize {
        let width: Double = switch style {
        case .artOnly, .menuBar: 280
        case .title: 300
        case .text: 240
        case .strip: 320
        case .wide: 360
        case .bigArt: 280
        }
        return style.shape.size(width: width)
    }

    /// `size` brought into `style`'s shape and range (`StyleShape.clamp`).
    /// Anything that isn't a finite size opens at the style's default.
    public static func clamp(_ size: PlayerSize, for style: PlayerStyleID) -> PlayerSize {
        guard size.width.isFinite, size.height.isFinite else { return defaultSize(for: style) }
        return style.shape.clamp(size)
    }

    /// Whether showing `surface` in `style` grows the window to the
    /// `surfaceSide` square: History and Status in Title, Text, Strip and
    /// Wide, which are too short for them (DESIGN.md §7.2). Big Art and Art
    /// Only show every surface in their own frame.
    public static func needsExpansion(for surface: Surface, style: PlayerStyleID) -> Bool {
        (style.isBar || style.isLandscape) && surface != .now
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

extension PlayerStyleID {
    /// The window's shape and range (DESIGN.md §7). Menu Bar has no window; it
    /// answers with Art Only's square so anything that needs a size gets one.
    public var shape: StyleShape {
        switch self {
        case .artOnly, .menuBar: .square(sides: StyleGeometry.squareSides)
        case .title: .bar(height: 72, widths: 240...420)
        case .text: .bar(height: 44, widths: 180...360)
        case .strip: .bar(height: 48, widths: 260...440)
        case .wide: .landscape(widths: 320...520, heightRatio: 0.5)
        case .bigArt: .portrait(widths: 220...420, controlsHeight: StyleGeometry.bigArtControlsHeight)
        }
    }

    /// A square window: Art Only (and Menu Bar's stand-in).
    public var isSquare: Bool {
        if case .square = shape { true } else { false }
    }

    /// A short bar that resizes by width: Title, Text, Strip.
    public var isBar: Bool {
        if case .bar = shape { true } else { false }
    }

    /// Big Art's portrait card.
    public var isPortrait: Bool {
        if case .portrait = shape { true } else { false }
    }

    /// Wide's landscape card, which resizes by width.
    public var isLandscape: Bool {
        if case .landscape = shape { true } else { false }
    }
}

/// The three sizes Settings offers (DESIGN.md §7's presets): a side for the
/// square, a width for the other shapes.
public enum PlayerSizePreset: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The square's side or the bar's or portrait's width this preset gives
    /// `style`. Menu Bar answers with Art Only's (its Size row hides).
    public func width(for style: PlayerStyleID) -> Double {
        let widths: (small: Double, medium: Double, large: Double) = switch style {
        case .artOnly, .menuBar: (200, 280, 400)
        case .title: (260, 300, 380)
        case .text: (200, 240, 320)
        case .strip: (280, 320, 400)
        case .wide: (320, 360, 440)
        case .bigArt: (240, 280, 360)
        }
        return switch self {
        case .small: widths.small
        case .medium: widths.medium
        case .large: widths.large
        }
    }

    /// The window size this preset gives `style`.
    public func size(for style: PlayerStyleID) -> PlayerSize {
        style.shape.size(width: width(for: style))
    }

    /// The preset whose width is nearest a window of `size` in `style`; halfway
    /// between two goes to the larger.
    public init(_ size: PlayerSize, style: PlayerStyleID) {
        let width = StyleGeometry.clamp(size, for: style).width
        let distances = Self.allCases.map { abs($0.width(for: style) - width) }
        let nearest = distances.indices.reversed().min { distances[$0] < distances[$1] } ?? 1
        self = Self.allCases[nearest]
    }
}
