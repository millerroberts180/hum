import AppKit
import HumCore

/// The window's content: the hosting view clipped to the player's rounded
/// shape, with resize handles around the edge.
///
/// Rounding happens here, on the layer, rather than only in SwiftUI, so the window
/// server's shadow follows the rounded shape.
final class PlayerContentView: NSView {
    let hostingView: NSView
    private(set) var handles: [ResizeHandleView] = []
    /// On macOS 26, host the content in Liquid Glass that samples the desktop,
    /// for a style whose whole window is glass (Text, Strip).
    var showsWindowGlass = false {
        didSet { if showsWindowGlass != oldValue { updateWindowGlass() } }
    }
    private var glassView: NSView?
    /// The look's resting opacity for that glass. The content sits inside it,
    /// so the two fade as one.
    private(set) var glassOpacity: CGFloat = 1
    /// The look's corner-radius setting.
    var cornerRadiusScale: CGFloat = 1 {
        didSet { if cornerRadiusScale != oldValue { needsLayout = true } }
    }
    /// The window's shape and range, which the handles resize within. A bar
    /// and Wide's landscape card resize from their sides only.
    var shape: StyleShape = PlayerStyleID.artOnly.shape {
        didSet {
            guard shape != oldValue else { return }
            let sideways = shape.resizesSideways
            for handle in handles {
                handle.shape = shape
                handle.isHidden = sideways && (handle.position == .top || handle.position == .bottom)
                window?.invalidateCursorRects(for: handle)
            }
        }
    }
    /// How the window's corners round.
    var cornerShape: CornerShape = .panel {
        didSet { if cornerShape != oldValue { needsLayout = true } }
    }

    /// How a window's corners round, by its shape (DESIGN.md §7): Text is a
    /// capsule, Title, Strip, Wide and Big Art have a card's corners, and Art
    /// Only rounds with its size like a panel.
    nonisolated enum CornerShape: Equatable, Sendable {
        case panel
        case card
        case capsule

        init(_ style: PlayerStyleID) {
            self = switch style {
            case .text: .capsule
            case .title, .strip, .wide, .bigArt: .card
            case .artOnly, .menuBar: .panel
            }
        }

        /// The corner radius for a window of `size`, with the look's
        /// corner-radius setting `scale`. A capsule stays one at any scale.
        func radius(for size: CGSize, scale: CGFloat) -> CGFloat {
            let short = min(size.width, size.height)
            return switch self {
            case .panel: Radius.panel(side: short) * scale
            case .card: min(Radius.card * scale, short / 2)
            case .capsule: short / 2
            }
        }
    }

    static let edgeThickness: CGFloat = 6
    static let cornerSize: CGFloat = 16
    /// The system's hairline rim in dark appearance, one pixel inside the corners.
    static let rimColor = NSColor.white.withAlphaComponent(0.1)

    init(hostingView: NSView) {
        self.hostingView = hostingView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.borderColor = Self.rimColor.cgColor
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        // Edges first so corners, added later, sit on top where they overlap.
        let order: [ResizeHandleView.Position] = [.top, .bottom, .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight]
        for position in order {
            let handle = ResizeHandleView(position: position)
            addSubview(handle)
            handles.append(handle)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRim()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateRim()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateRim()
    }

    /// The layer's border is drawn above the hosting view and follows the
    /// rounded corners. Light appearance has none, and nothing is drawn over
    /// Liquid Glass.
    private func updateRim() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let pixel = 1 / (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        layer?.borderWidth = isDark && glassView == nil ? pixel : 0
    }

    override func layout() {
        super.layout()
        if let glassView {
            glassView.frame = bounds
            hostingView.frame = glassView.bounds
        } else {
            hostingView.frame = bounds
        }
        let radius = cornerShape.radius(for: bounds.size, scale: cornerRadiusScale)
        if layer?.cornerRadius != radius {
            layer?.cornerRadius = radius
            window?.invalidateShadow()
        }
        if #available(macOS 26, *), let glass = glassView as? NSGlassEffectView {
            glass.cornerRadius = radius
        }
        let w = bounds.width
        let h = bounds.height
        let e = Self.edgeThickness
        let c = Self.cornerSize
        for handle in handles {
            handle.frame = switch handle.position {
            case .top: NSRect(x: c, y: h - e, width: w - 2 * c, height: e)
            case .bottom: NSRect(x: c, y: 0, width: w - 2 * c, height: e)
            case .left: NSRect(x: 0, y: c, width: e, height: h - 2 * c)
            case .right: NSRect(x: w - e, y: c, width: e, height: h - 2 * c)
            case .topLeft: NSRect(x: 0, y: h - c, width: c, height: c)
            case .topRight: NSRect(x: w - c, y: h - c, width: c, height: c)
            case .bottomLeft: NSRect(x: 0, y: 0, width: c, height: c)
            case .bottomRight: NSRect(x: w - c, y: 0, width: c, height: c)
            }
        }
    }

    /// Fade the window's glass to `opacity`: up with the reveal's timing, back
    /// with the conceal's, on the same curve as the content.
    func setGlassOpacity(_ opacity: CGFloat) {
        guard opacity != glassOpacity else { return }
        let duration = opacity > glassOpacity ? Motion.revealDuration : Motion.concealDuration
        glassOpacity = opacity
        guard let glassView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = Motion.easeOutCurve
            glassView.animator().alphaValue = opacity
        }
    }

    /// The hosting view moves straight between this view and the glass, never
    /// leaving the window, so SwiftUI keeps its state and never sees it disappear.
    private func updateWindowGlass() {
        guard #available(macOS 26, *) else { return }
        if showsWindowGlass, glassView == nil {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular
            glass.cornerRadius = layer?.cornerRadius ?? 0
            glass.alphaValue = glassOpacity
            addSubview(glass, positioned: .below, relativeTo: handles.first)
            glass.contentView = hostingView
            glassView = glass
        } else if !showsWindowGlass, let glass = glassView {
            addSubview(hostingView, positioned: .below, relativeTo: handles.first)
            glass.removeFromSuperview()
            glassView = nil
        }
        updateRim()
        needsLayout = true
    }
}
