import AppKit
import HumCore

/// Appearance › Corners: three tiles for the corner radius scale (DESIGN.md §8).
nonisolated enum CornerChoice: CaseIterable, Identifiable, Sendable {
    case square
    case standard
    case round

    var id: Self { self }

    var title: String {
        switch self {
        case .square: "Square"
        case .standard: "Standard"
        case .round: "Round"
        }
    }

    /// The `StyleLook.cornerRadiusScale` the tile sets.
    var scale: Double {
        switch self {
        case .square: 0.5
        case .standard: 1
        case .round: 1.5
        }
    }

    /// The tile a saved scale marks: the nearest one.
    static func nearest(to scale: Double) -> CornerChoice {
        nearestChoice(allCases, to: scale, by: \.scale)
    }
}

/// Appearance › Opacity at rest: three tiles for the player's resting opacity
/// (DESIGN.md §8).
nonisolated enum OpacityChoice: CaseIterable, Identifiable, Sendable {
    case full
    case high
    case low

    var id: Self { self }

    /// The `StyleLook.opacity` the tile sets.
    var opacity: Double {
        switch self {
        case .full: 1
        case .high: 0.85
        case .low: 0.7
        }
    }

    var title: String {
        "\(Int((opacity * 100).rounded()))%"
    }

    /// The tile a saved opacity marks: the nearest one.
    static func nearest(to opacity: Double) -> OpacityChoice {
        nearestChoice(allCases, to: opacity, by: \.opacity)
    }
}

/// The choice whose value is nearest `value`; halfway between two goes to the
/// larger, as the size presets do. `nil`-free: an empty list isn't asked for.
nonisolated func nearestChoice<Choice>(_ choices: [Choice], to value: Double, by key: (Choice) -> Double) -> Choice {
    let value = value.isFinite ? value : choices.map(key).max() ?? 0
    var best = choices[0]
    for choice in choices.dropFirst() {
        let distance = abs(key(choice) - value)
        let bestDistance = abs(key(best) - value)
        if distance < bestDistance || (distance == bestDistance && key(choice) > key(best)) {
            best = choice
        }
    }
    return best
}

/// The rows of Settings › Appearance, in order, and which ones a style shows.
nonisolated enum AppearanceRow: Equatable, Sendable {
    case style
    case appearance
    /// Liquid Glass or Frosted. Only where macOS has Liquid Glass (§3.6.1):
    /// on macOS 15 the row doesn't exist at all.
    case material
    case accent
    case corners
    case opacity
    /// Art Only's resting progress.
    case progress
    /// Text's album tint.
    case albumTint

    /// The rows Appearance shows while `style` is chosen. Menu Bar has no
    /// window, so it has no corners or resting opacity to set, and Text's
    /// capsule stays a capsule whatever the corner setting.
    static func rows(
        for style: PlayerStyleID,
        liquidGlassAvailable: Bool = GlassMaterial.isLiquidGlassAvailable
    ) -> [AppearanceRow] {
        var rows: [AppearanceRow] = [.style, .appearance]
        if liquidGlassAvailable { rows.append(.material) }
        rows.append(.accent)
        if style.hasWindow, style != .text { rows.append(.corners) }
        if style.hasWindow { rows.append(.opacity) }
        if style.offersProgressChoice { rows.append(.progress) }
        if style.offersAlbumTint { rows.append(.albumTint) }
        return rows
    }
}

/// The rows of Settings › Player, in order, and which ones a style shows.
nonisolated enum PlayerRow: Equatable, Sendable {
    /// "Always show controls", at the top of the Controls section.
    case alwaysShowControls
    /// The hover controls' switches.
    case controls
    case size
    case position
    case visibility
    case window
    case gestures

    /// The rows Player shows while `style` is chosen. Menu Bar has no window
    /// to size, place or show, its popover always shows its controls, and it
    /// has Now only, so it never pages (§7.1): those rows hide.
    static func rows(for style: PlayerStyleID) -> [PlayerRow] {
        style.hasWindow
            ? [.alwaysShowControls, .controls, .size, .position, .visibility, .window, .gestures]
            : [.controls, .window]
    }
}

/// Where the Position tile draws the screen and its nine targets, and which
/// target a click lands on (DESIGN.md §4.5, §8). Points are in the tile's own
/// top-left coordinates.
nonisolated enum PositionTileLayout {
    /// The drawn display's height in the tile.
    static let screenHeight: CGFloat = 132
    /// The menu bar across the top of the drawn display.
    static let menuBarHeight: CGFloat = 8
    /// The drawn display's corners.
    static let screenRadius: CGFloat = 6
    /// The targets' inset from the drawn display's edges, standing for the
    /// player's `Spacing.l` from the visible frame.
    static let inset: CGFloat = 12
    /// A target's diameter.
    static let target: CGFloat = 10
    /// The display's shape when there's no screen to measure: 16:10.
    static let fallbackAspect: CGFloat = 1.6

    /// The drawn display, centered in a tile of `size`, keeping `aspect`
    /// (width over height).
    static func screen(in size: CGSize, aspect: CGFloat = fallbackAspect) -> CGRect {
        let height = min(screenHeight, size.height - 2 * Spacing.m)
        let width = min(height * aspect, size.width - 2 * Spacing.m)
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// The part of the drawn display a player may use: below its menu bar.
    static func visibleArea(in size: CGSize, aspect: CGFloat = fallbackAspect) -> CGRect {
        let screen = screen(in: size, aspect: aspect)
        return CGRect(x: screen.minX, y: screen.minY + menuBarHeight, width: screen.width, height: screen.height - menuBarHeight)
    }

    /// The center of `position`'s target.
    static func target(_ position: PinPosition, in size: CGSize, aspect: CGFloat = fallbackAspect) -> CGPoint {
        let area = visibleArea(in: size, aspect: aspect).insetBy(dx: inset, dy: inset)
        let x = area.midX + CGFloat(position.column) * area.width / 2
        let y = area.midY - CGFloat(position.row) * area.height / 2
        return CGPoint(x: x, y: y)
    }

    /// The target nearest `point`, or `nil` for a point outside the drawn
    /// display.
    static func position(at point: CGPoint, in size: CGSize, aspect: CGFloat = fallbackAspect) -> PinPosition? {
        guard screen(in: size, aspect: aspect).contains(point) else { return nil }
        return PinPosition.allCases.min { first, second in
            distance(target(first, in: size, aspect: aspect), point) < distance(target(second, in: size, aspect: aspect), point)
        }
    }

    /// Where a player of `playerSize` (already scaled to the drawing) sits
    /// when pinned at `position`: against its corner or edge target, as the
    /// real window sits against the inset visible frame.
    static func playerFrame(
        _ playerSize: CGSize,
        at position: PinPosition,
        in size: CGSize,
        aspect: CGFloat = fallbackAspect
    ) -> CGRect {
        let area = visibleArea(in: size, aspect: aspect).insetBy(dx: inset / 2, dy: inset / 2)
        let x: CGFloat = switch position.column {
        case -1: area.minX
        case 0: area.midX - playerSize.width / 2
        default: area.maxX - playerSize.width
        }
        let y: CGFloat = switch position.row {
        case 1: area.minY
        case 0: area.midY - playerSize.height / 2
        default: area.maxY - playerSize.height
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: playerSize)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

/// Sources › Control: the three tiles (DESIGN.md §8). Automatic follows
/// whichever app is playing; the others prefer one app.
nonisolated enum SourceChoice: CaseIterable, Identifiable, Sendable {
    case automatic
    case music
    case spotify

    var id: Self { self }

    /// Settings › Sources may name the apps (§10).
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// The preferred source the tile stores; Automatic stores none.
    var sourceID: SourceID? {
        switch self {
        case .automatic: nil
        case .music: .musicApp
        case .spotify: .spotifyApp
        }
    }

    /// The app the tile stands for.
    var bundleIdentifier: String? {
        switch self {
        case .automatic: nil
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// The tile a stored preference marks. A source this pane doesn't offer
    /// (the demo's) marks Automatic.
    init(preferred: SourceID?) {
        self = Self.allCases.first { $0.sourceID == preferred && $0 != .automatic } ?? .automatic
    }
}
