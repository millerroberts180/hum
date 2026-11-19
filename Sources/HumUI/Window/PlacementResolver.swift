import CoreGraphics
import HumCore

/// Converts between window frames, pin positions, and remembered per-display
/// placements (DESIGN.md §4.5).
nonisolated enum PlacementResolver {
    /// How far the corners and edge midpoints sit inside the visible frame.
    static let pinInset = Spacing.l
    /// How close a placement saved before pins existed has to be to one of the
    /// nine positions to be pinned there when the player opens. Wide enough
    /// for the old default spot, 24 pt in from the top-right corner.
    static let migrationTolerance: CGFloat = 8

    /// The frame of `size` pinned at `pin` on a display whose usable area is
    /// `visible`: corners and edge midpoints `pinInset` in from its edges,
    /// Center at its center. Kept on screen if the display is too small.
    static func frame(for pin: PinPosition, size: CGSize, in visible: CGRect) -> CGRect {
        let size = fitted(size, in: visible)
        let x: CGFloat = switch pin.column {
        case -1: visible.minX + pinInset
        case 0: visible.midX - size.width / 2
        default: visible.maxX - pinInset - size.width
        }
        let y: CGFloat = switch pin.row {
        case 1: visible.maxY - pinInset - size.height
        case 0: visible.midY - size.height / 2
        default: visible.minY + pinInset
        }
        return clamp(CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), to: visible)
    }

    /// The point of the window a pin holds still while it changes size, in
    /// unit coordinates with y up: a Top Right pin holds the top-right corner,
    /// Center the center, Bottom the middle of the bottom edge.
    static func anchor(of pin: PinPosition) -> CGPoint {
        CGPoint(x: CGFloat(pin.column + 1) / 2, y: CGFloat(pin.row + 1) / 2)
    }

    /// A frame of `size` for a window now at `current`: at its pin when it has
    /// one, so the pinned point stays put, or else holding the nearest-third
    /// anchor still (`anchor(of:in:)`).
    static func frame(resizing current: CGRect, to size: CGSize, pin: PinPosition?, in visible: CGRect) -> CGRect {
        if let pin {
            return frame(for: pin, size: size, in: visible)
        }
        return frame(resizing: current, to: size, anchor: anchor(of: current, in: visible), in: visible)
    }

    /// The pin a frame sits at, if it's within `tolerance` of one of the nine
    /// positions for its size. For placements saved before pins existed.
    static func nearestPin(to frame: CGRect, in visible: CGRect, tolerance: CGFloat = migrationTolerance) -> PinPosition? {
        let distances = PinPosition.allCases.map { pin in
            let target = self.frame(for: pin, size: frame.size, in: visible)
            return (pin, max(abs(target.minX - frame.minX), abs(target.minY - frame.minY)))
        }
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= tolerance else { return nil }
        return nearest.0
    }

    /// The pin for `display` with its remembered `placement`: the
    /// placement's own; `PinPosition.initial` when there's none yet; and for
    /// a placement kept before pins existed, the position it sits within
    /// `migrationTolerance` of, if any. `nil` for a player dropped elsewhere.
    static func pin(for placement: WindowPlacement?, size: CGSize, on display: DisplayInfo) -> PinPosition? {
        guard let placement else { return .initial }
        if let pin = placement.pin { return pin }
        return nearestPin(to: frame(for: placement, size: size, on: display), in: display.visibleFrame)
    }

    /// The frame of `size` at `placement` on `display`, kept fully on screen:
    /// at its pin when it has one, at its offset otherwise. Without a
    /// placement, the player sits at `PinPosition.initial`.
    static func frame(for placement: WindowPlacement?, size: CGSize, on display: DisplayInfo) -> CGRect {
        let visible = display.visibleFrame
        let size = fitted(size, in: visible)
        guard let placement else {
            return frame(for: .initial, size: size, in: visible)
        }
        if let pin = placement.pin {
            return frame(for: pin, size: size, in: visible)
        }
        let frame = CGRect(
            x: visible.minX + CGFloat(placement.offsetX),
            y: visible.minY + CGFloat(placement.offsetY),
            width: size.width,
            height: size.height
        )
        return clamp(frame, to: visible)
    }

    /// `side` is the square size to come back to; for another shape it's
    /// whatever the square styles last used, passed through unchanged.
    static func placement(
        for frame: CGRect,
        on display: DisplayInfo,
        surface: Surface,
        side: CGFloat? = nil,
        pin: PinPosition? = nil
    ) -> WindowPlacement {
        WindowPlacement(
            offsetX: Double(frame.minX - display.visibleFrame.minX),
            offsetY: Double(frame.minY - display.visibleFrame.minY),
            side: Double(side ?? frame.width),
            surface: surface,
            pin: pin
        )
    }

    /// Slide `frame` so it's entirely inside `visible`, shrinking it only if the
    /// display is too small to hold it.
    static func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
        let size = fitted(frame.size, in: visible)
        let x = min(max(frame.minX, visible.minX), visible.maxX - size.width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A frame of `size` that keeps `anchor` of `frame` where it is: the
    /// top-right corner of a window in the top-right corner of the screen stays
    /// put while it grows or shrinks. Then kept on screen.
    static func frame(resizing frame: CGRect, to size: CGSize, anchor: CGPoint, in visible: CGRect) -> CGRect {
        let x = frame.minX + (frame.width - size.width) * anchor.x
        let y = frame.minY + (frame.height - size.height) * anchor.y
        return clamp(CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), to: visible)
    }

    /// Which part of `frame` to hold still while it changes size, in unit
    /// coordinates with y up: 0 for the left or bottom third of the screen, 1
    /// for the right or top third, 0.5 between.
    static func anchor(of frame: CGRect, in visible: CGRect) -> CGPoint {
        guard visible.width > 0, visible.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        func third(_ fraction: CGFloat) -> CGFloat {
            fraction < 1.0 / 3 ? 0 : (fraction > 2.0 / 3 ? 1 : 0.5)
        }
        return CGPoint(
            x: third((frame.midX - visible.minX) / visible.width),
            y: third((frame.midY - visible.minY) / visible.height)
        )
    }

    /// The display holding most of `frame`.
    static func display(containing frame: CGRect, among displays: [DisplayInfo]) -> DisplayInfo? {
        displays.max { lhs, rhs in
            area(lhs.visibleFrame.intersection(frame)) < area(rhs.visibleFrame.intersection(frame))
        }
    }

    /// Shrink `size` to fit `visible`, keeping a square square.
    static func fitted(_ size: CGSize, in visible: CGRect) -> CGSize {
        if size.width == size.height {
            let side = min(size.width, visible.width, visible.height)
            return CGSize(width: side, height: side)
        }
        return CGSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
