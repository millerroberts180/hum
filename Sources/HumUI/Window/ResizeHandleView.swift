import AppKit
import HumCore

/// An invisible strip along one edge or corner of the player that resizes it.
///
/// The player is a borderless window, so it draws its own handles: dragging any
/// edge or corner grows or shrinks it in its style's shape (DESIGN.md §7) while
/// the opposite side stays put. A square keeps square; a bar changes only its
/// width, from its sides; Wide's landscape card takes its width from its sides
/// and its height follows; Big Art's portrait takes its width from any edge and
/// its height follows.
final class ResizeHandleView: NSView {
    nonisolated enum Position: CaseIterable, Sendable {
        case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

        var isCorner: Bool {
            switch self {
            case .topLeft, .topRight, .bottomLeft, .bottomRight: true
            case .top, .bottom, .left, .right: false
            }
        }
    }

    let position: Position
    /// The shape and range to resize within.
    var shape: StyleShape = PlayerStyleID.artOnly.shape
    var onResize: ((NSRect) -> Void)?
    var onResizeEnd: (() -> Void)?

    private var startFrame: NSRect = .zero
    private var startPointer: NSPoint = .zero

    init(position: Position) {
        self.position = position
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    private var cursor: NSCursor {
        let width = Double(window?.frame.width ?? 0)
        let limits = shape.widths
        let directions: NSCursor.FrameResizeDirection.Set = if width <= limits.lowerBound + 0.5 {
            .outward
        } else if width >= limits.upperBound - 0.5 {
            .inward
        } else {
            .all
        }
        return NSCursor.frameResize(position: cursorPosition, directions: directions)
    }

    private var cursorPosition: NSCursor.FrameResizePosition {
        if shape.resizesSideways {
            return [.left, .topLeft, .bottomLeft].contains(position) ? .left : .right
        }
        return switch position {
        case .top: .top
        case .bottom: .bottom
        case .left: .left
        case .right: .right
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        }
    }

    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame ?? .zero
        startPointer = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        let frame = Self.resizedFrame(
            from: startFrame,
            position: position,
            dragX: pointer.x - startPointer.x,
            dragY: pointer.y - startPointer.y,
            shape: shape
        )
        onResize?(frame)
    }

    override func mouseUp(with event: NSEvent) {
        window?.invalidateCursorRects(for: self)
        onResizeEnd?()
    }

    /// The frame that results from dragging `position` by the given amount,
    /// in `shape` and within its range, keeping the opposite edge (or corner)
    /// where it was. Screen coordinates, y up.
    ///
    /// A square or a portrait grows by the drag along its edge, or by the
    /// longer of the two at a corner. A bar and a landscape card only grow
    /// sideways, so only the horizontal drag counts. A bar's top edge stays
    /// put; a landscape card's height follows its width, away from the corner
    /// dragged, or down from its top for a side.
    nonisolated static func resizedFrame(
        from start: NSRect,
        position: Position,
        dragX: CGFloat,
        dragY: CGFloat,
        shape: StyleShape
    ) -> NSRect {
        let growX: CGFloat = switch position {
        case .right, .topRight, .bottomRight: dragX
        case .left, .topLeft, .bottomLeft: -dragX
        case .top, .bottom: 0
        }
        let growY: CGFloat = switch position {
        case .top, .topLeft, .topRight: dragY
        case .bottom, .bottomLeft, .bottomRight: -dragY
        case .left, .right: 0
        }
        let growth: CGFloat = if shape.resizesSideways {
            growX
        } else if position.isCorner {
            abs(growX) >= abs(growY) ? growX : growY
        } else {
            growX + growY
        }
        let size = shape.size(width: Double((start.width + growth).rounded()))
        let width = CGFloat(size.width)
        let height = CGFloat(size.height)

        let anchorsRight = [.left, .topLeft, .bottomLeft].contains(position)
        let anchorsBottom: Bool = if case .bar = shape {
            false
        } else {
            [.top, .topLeft, .topRight].contains(position)
        }
        let x = anchorsRight ? start.maxX - width : start.minX
        let y = anchorsBottom ? start.minY : start.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
