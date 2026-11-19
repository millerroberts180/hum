import CoreGraphics

/// Sizes that depend on how big the player is.
///
/// Control sizes change by size class only, never continuously while the window
/// resizes, so glyphs don't shimmer mid-resize.
nonisolated struct PlayerMetrics: Equatable, Sendable {
    static let minimumSide: CGFloat = 168
    static let defaultSide: CGFloat = 280
    static let maximumSide: CGFloat = 640

    var side: CGFloat
    /// The look's corner-radius setting (DESIGN.md §8), already clamped by
    /// `StyleLook`.
    var cornerRadiusScale: CGFloat = 1

    /// Sizes the controls by this class rather than by `side`: the bars
    /// (Title, Text, Strip), whose glyphs follow their height while the rest
    /// follows their width (DESIGN.md §7).
    var controlClass: PlayerSizeClass?
    /// Play/pause at the previous/next size: Title's and Text's transport, set
    /// at the secondary glyph sizes (§7).
    var playsAtSecondarySize = false

    var sizeClass: PlayerSizeClass { PlayerSizeClass(side: side) }

    var cornerRadius: CGFloat { Radius.panel(side: side) * cornerRadiusScale }

    /// Inset from the player edge to its content.
    var contentInset: CGFloat {
        switch sizeClass {
        case .small: Spacing.s
        case .medium: Spacing.m
        case .large: Spacing.l
        }
    }

    var play: ControlSizing { playsAtSecondarySize ? skip : ControlSizing.play(controlSizeClass) }
    var skip: ControlSizing { ControlSizing.skip(controlSizeClass) }
    /// Shuffle, repeat, save, and more.
    var tertiary: ControlSizing { ControlSizing.tertiary(controlSizeClass) }

    /// The class the controls are sized by.
    var controlSizeClass: PlayerSizeClass { controlClass ?? sizeClass }

    /// Space between neighboring transport hit targets.
    var transportGap: CGFloat {
        switch controlSizeClass {
        case .small: 4
        case .medium: 8
        case .large: 12
        }
    }

    static func clampedSide(_ side: CGFloat) -> CGFloat {
        min(maximumSide, max(minimumSide, side))
    }
}

/// The player's three size classes. Each decides what appears on hover.
nonisolated enum PlayerSizeClass: Equatable, Hashable, Sendable {
    /// 168–239 pt: the transport, shuffle and repeat, the seek bar, and save.
    case small
    /// 240–379 pt (the default 280): adds title and artist, and times.
    case medium
    /// 380–640 pt: adds album and volume.
    case large

    init(side: CGFloat) {
        switch side {
        case ..<240: self = .small
        case ..<380: self = .medium
        default: self = .large
        }
    }
}

/// A control's three sizes: the symbol, the circle or capsule shown on hover,
/// press, or when on, and the invisible hit target around it.
nonisolated struct ControlSizing: Equatable, Sendable {
    var glyph: CGFloat
    var backing: CGFloat
    var hit: CGFloat

    /// How far the hit target reaches past the backing on each side.
    var outset: CGFloat { (hit - backing) / 2 }

    static func play(_ sizeClass: PlayerSizeClass) -> ControlSizing {
        switch sizeClass {
        case .small: ControlSizing(glyph: 18, backing: 32, hit: 36)
        case .medium: ControlSizing(glyph: 22, backing: 40, hit: 44)
        case .large: ControlSizing(glyph: 28, backing: 52, hit: 56)
        }
    }

    static func skip(_ sizeClass: PlayerSizeClass) -> ControlSizing {
        switch sizeClass {
        case .small: ControlSizing(glyph: 14, backing: 28, hit: 32)
        case .medium: ControlSizing(glyph: 16, backing: 32, hit: 36)
        case .large: ControlSizing(glyph: 20, backing: 40, hit: 44)
        }
    }

    static func tertiary(_ sizeClass: PlayerSizeClass) -> ControlSizing {
        switch sizeClass {
        case .small: ControlSizing(glyph: 12, backing: 24, hit: 28)
        case .medium: ControlSizing(glyph: 13, backing: 28, hit: 32)
        case .large: ControlSizing(glyph: 15, backing: 32, hit: 36)
        }
    }

    /// Devices beside the volume, and a banner's dismiss.
    static let icon = ControlSizing(glyph: 13, backing: 24, hit: 28)

    /// The floating play button on cards (DESIGN.md §3.8). S uses the M size.
    static func cardPlay(_ sizeClass: PlayerSizeClass) -> ControlSizing {
        switch sizeClass {
        case .small, .medium: ControlSizing(glyph: 12, backing: 28, hit: 32)
        case .large: ControlSizing(glyph: 14, backing: 32, hit: 36)
        }
    }

    /// The smallest hit target allowed: 28 pt, or 24 pt for tertiary controls at S.
    static func minimumHit(_ sizeClass: PlayerSizeClass, isTertiary: Bool) -> CGFloat {
        sizeClass == .small && isTertiary ? 24 : 28
    }
}

/// Seek and volume tracks.
nonisolated enum SliderMetrics {
    static let restThickness: CGFloat = 4
    /// Hovered, dragged or focused (DESIGN.md §5.10).
    static let activeThickness: CGFloat = 7
    /// The invisible strip that takes clicks and drags, across the full width.
    static let hitHeight: CGFloat = 20
    /// The resting progress line along the bottom of the cover.
    static let hairline: CGFloat = 2
}

/// Where neighboring hit targets meet.
nonisolated enum HitTargets {
    /// How far each control in a row reaches past its backing toward its
    /// neighbors.
    ///
    /// Each control would like `outsets[i]` on both sides. Where two neighbors'
    /// targets would overlap across `gaps[i]` (the space between backing `i` and
    /// backing `i + 1`), the gap is split at its midpoint instead.
    static func extents(outsets: [CGFloat], gaps: [CGFloat]) -> [(leading: CGFloat, trailing: CGFloat)] {
        precondition(gaps.count == max(0, outsets.count - 1), "One gap between each pair of controls.")
        var result = outsets.map { (leading: $0, trailing: $0) }
        for (index, gap) in gaps.enumerated() {
            let gap = max(0, gap)
            if outsets[index] + outsets[index + 1] > gap {
                result[index].trailing = gap / 2
                result[index + 1].leading = gap / 2
            }
        }
        return result
    }
}
