import AppKit

/// Hum's mark, Vibrato: a flat line that breaks into two even ripples and
/// settles, a sustained hum. The menu-bar item draws it as a template image
/// (DESIGN.md §5.8), from the small-size cut in
/// `design/logo/hum-symbol-small.svg`: shorter tails and taller ripples, so the
/// ripples stay open at menu-bar sizes.
public enum HumMark {
    /// The logo's grid: 256 units square, y down, like the SVG masters.
    nonisolated static let grid: CGFloat = 256
    /// The small cut's line width, in grid units.
    nonisolated static let lineWidth: CGFloat = 32
    /// The menu-bar item's image side, in points.
    public static let menuBarSide: CGFloat = 18

    /// The mark's centerline on the 256-unit grid, y down. It's stroked
    /// `lineWidth` wide with round caps and joins.
    nonisolated static func centerline() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 40, y: 128))
        path.addLine(to: CGPoint(x: 58, y: 128))
        path.addCurve(to: CGPoint(x: 86, y: 96), control1: CGPoint(x: 72, y: 128), control2: CGPoint(x: 72, y: 96))
        path.addCurve(to: CGPoint(x: 114, y: 160), control1: CGPoint(x: 96, y: 96), control2: CGPoint(x: 104, y: 160))
        path.addCurve(to: CGPoint(x: 142, y: 96), control1: CGPoint(x: 124, y: 160), control2: CGPoint(x: 132, y: 96))
        path.addCurve(to: CGPoint(x: 170, y: 160), control1: CGPoint(x: 152, y: 96), control2: CGPoint(x: 160, y: 160))
        path.addCurve(to: CGPoint(x: 198, y: 128), control1: CGPoint(x: 184, y: 160), control2: CGPoint(x: 184, y: 128))
        path.addLine(to: CGPoint(x: 216, y: 128))
        return path
    }

    /// The mark's outline, filled, in a square of `side` points with y down:
    /// the centerline stroked the way the logo strokes it.
    nonisolated static func outline(side: CGFloat) -> CGPath {
        var scale = CGAffineTransform(scaleX: side / grid, y: side / grid)
        let line = centerline().copy(using: &scale) ?? centerline()
        return line.copy(
            strokingWithWidth: lineWidth * side / grid,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
    }

    /// The mark as a template image `side` points square, which the menu bar
    /// tints for its appearance and dims when the item appears disabled. It's
    /// drawn at whatever scale the screen asks for.
    public static func templateImage(side: CGFloat = menuBarSide, accessibilityDescription: String = "Hum") -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(outline(side: rect.width))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
