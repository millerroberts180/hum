import AppKit
import HumCore
import QuartzCore
import SwiftUI

/// Owns the player window and everything about how it appears: where it's
/// pinned on each display, when it shows and hides, its keyboard commands, and
/// swipe paging (DESIGN.md §4.5).
///
/// The app creates one, calls `start()`, and drives it from the menu and global
/// shortcut through the public methods here. In Menu Bar (§7.1) the window
/// stays hidden and the menu-bar item is the player.
public final class PlayerWindowController: NSObject, NSWindowDelegate {
    public let pager: SurfacePager
    public let interaction: PlayerInteraction
    /// The current style's size, for Settings to show and change.
    public let sizing = PlayerSizing()
    /// Called when the window is shown or hidden, for menu titles.
    public var onVisibilityChange: ((Bool) -> Void)?
    /// Show or Toggle Player while in Menu Bar: the app opens or closes the
    /// menu-bar popover instead.
    public var onSummonInMenuBar: ((Summon) -> Void)?

    /// What summoning the player asks of the menu-bar popover in Menu Bar.
    public enum Summon: Equatable, Sendable {
        /// Show (a widget's link, the Dock, Show ▸): open it, or leave it open.
        case show
        /// The Toggle Player shortcut: open it, or close it if it's open.
        case toggle

        /// Whether the popover should open or close, given whether it's open.
        public func togglesPopover(isShown: Bool) -> Bool {
            self == .toggle || !isShown
        }
    }
    /// The menu-bar item's frame on screen, which the window materializes
    /// toward going into Menu Bar and from coming out of it.
    public var statusItemFrame: (() -> CGRect?)?

    private let store: NowPlayingStore
    private let settings: SettingsStore
    private let actions: PlayerActions
    private let launchOptions: LaunchOptions
    private let panel: PlayerPanel
    private let hostingView: PlayerHostingView<PlayerWindowContent>
    private let visibility: PlayerVisibilityController
    private let mover: WindowMover
    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var trackObservation: NowPlayingObservation?
    private var screenObserver: (any NSObjectProtocol)?
    private var appearanceObservation: NSKeyValueObservation?
    private var isHiding = false
    private var presentGeneration = 0
    private var hasBeenPlaced = false
    /// The style whose shape and size the window has.
    private var appliedStyle: PlayerStyleID?
    /// Grown to a square for Echo or Status in Title, Text or Strip.
    private var expansion: PlayerExpansion?
    /// Where the player is pinned on the display it's on, or `nil` once it's
    /// been dropped somewhere with snapping off.
    private var pin: PinPosition? = .initial {
        didSet { sizing.pin = pin }
    }
    /// A screen point the content materializes toward or from, in place of
    /// its pin: the menu-bar item, going into Menu Bar and out of it.
    private var materializeOrigin: CGPoint?
    private var swipeSkip = SwipeSkipTracker()
    private var swipeVolume = SwipeVolumeTracker()
    private var pinch = PinchResizeTracker()
    private var contentView: PlayerContentView? { panel.contentView as? PlayerContentView }

    /// How far one ⌘↑ or ⌘↓ moves the volume.
    static let volumeStep = 0.05
    /// How long Show on Track Change keeps the player up after a new song
    /// (DESIGN.md §4.5). Fixed; the pointer over the window holds it longer.
    static let trackChangeDisplaySeconds: Double = 4
    /// How long the window's opacity takes to arrive or leave, alongside the
    /// content's materialize spring.
    static let fadeDuration = Motion.materializeSpring.response
    /// The shortest any shape gets: Text's capsule.
    static let shortestSide: CGFloat = 44
    /// How long Settings' reveal keeps the controls up (`revealControls`).
    static let settingsRevealSeconds = 1.5

    public init(
        store: NowPlayingStore,
        settings: SettingsStore,
        launchOptions: LaunchOptions,
        actions: PlayerActions,
        services: AppServices = AppServices()
    ) {
        // Views reach the window (menus, dragging) through these, once it exists.
        let relay = ActionRelay()
        var actions = actions
        actions.popUpMenu = { menu, rect in relay.controller?.popUp(menu, below: rect) }
        actions.windowDrag = { phase in relay.controller?.mover.handle(phase) }
        self.store = store
        self.settings = settings
        self.actions = actions
        self.launchOptions = launchOptions
        if launchOptions.resetWindow {
            settings.window = WindowMemory()
        }
        #if DEBUG
        if let factor = launchOptions.slowMotion {
            Motion.slowMotion = factor
        }
        #endif
        pager = SurfacePager(surface: launchOptions.surface ?? settings.window.lastSurface)
        interaction = PlayerInteraction()
        hostingView = PlayerHostingView(rootView: PlayerWindowContent(
            store: store,
            settings: settings,
            pager: pager,
            interaction: interaction,
            actions: actions,
            services: services,
            onWindowGlassChange: { relay.controller?.contentView?.showsWindowGlass = $0 },
            onWindowOpacityChange: { relay.controller?.contentView?.setGlassOpacity($0) }
        ))
        let side = PlayerMetrics.defaultSide
        panel = PlayerPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side))
        panel.contentView = PlayerContentView(hostingView: hostingView)
        // Roomy enough for every shape; the resize handles hold each style to
        // its own limits.
        panel.contentMinSize = NSSize(width: Self.shortestSide, height: Self.shortestSide)
        panel.contentMaxSize = NSSize(width: PlayerMetrics.maximumSide, height: PlayerMetrics.maximumSide)
        visibility = PlayerVisibilityController(
            mode: settings.behavior.visibility,
            displaySeconds: Self.trackChangeDisplaySeconds
        )
        mover = WindowMover(window: panel, frameDriver: DisplayLinkFrameDriver(view: hostingView))
        super.init()
        relay.controller = self
        panel.delegate = self
        wire()
    }

    isolated deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let magnifyMonitor { NSEvent.removeMonitor(magnifyMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    // MARK: Public

    /// Show the player now if the visibility setting says so. In Menu Bar
    /// there's no window to show.
    public func start() {
        appliedStyle = settings.appearance.style
        guard !isInMenuBar else { return }
        visibility.launch()
    }

    public var isVisible: Bool { panel.isVisible && !isHiding }

    /// Whether the player lives in the menu bar rather than a window (§7.1).
    public var isInMenuBar: Bool { !settings.appearance.style.hasWindow }

    /// Show the player for the user (menu, shortcut), optionally on a surface, and
    /// give it the keyboard. In Menu Bar, the app opens its popover instead.
    public func show(surface: Surface? = nil) {
        guard !isInMenuBar else {
            onSummonInMenuBar?(.show)
            return
        }
        present(.user, surface: surface, makeKey: true)
        visibility.userDidShow()
    }

    public func hide(animated: Bool = false) {
        guard panel.isVisible, !isHiding else { return }
        visibility.userDidHide()
        conceal(animated: animated)
    }

    public func toggle() {
        guard !isInMenuBar else {
            onSummonInMenuBar?(.toggle)
            return
        }
        if isVisible { hide() } else { show() }
    }

    public func go(to surface: Surface) {
        if !isVisible {
            show(surface: surface)
        } else {
            pager.go(to: surface, animated: true)
            // Chosen from the menu bar or another window: the keyboard follows,
            // so Esc reaches the player.
            takeKeyboard()
        }
    }

    /// Write the window's placement into settings (call before quitting).
    public func saveState() {
        savePlacement()
    }

    // MARK: Showing and hiding

    private var isTucked: Bool { settings.behavior.visibility == .tucked }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Bring the window in: it fades up while the content scales and sharpens
    /// into place from its anchor. Tucked, it slides down from under the menu
    /// bar instead. Showing again mid-hide turns around from where it is.
    private func present(_ reason: PlayerVisibilityController.ShowReason, surface: Surface?, makeKey: Bool) {
        presentGeneration += 1
        let wasHiding = isHiding
        isHiding = false
        if !panel.isVisible {
            place(for: reason)
            beginExpansionIfNeeded(for: surface ?? pager.current, animated: false)
            updatePresentationAnchor()
            let slides = isTucked && !reduceMotion
            panel.alphaValue = slides ? 1 : 0
            if slides {
                let rest = panel.frame.origin
                panel.setFrameOrigin(tuckedHiddenOrigin(for: panel.frame))
                mover.settle(to: rest, parameters: Motion.materializeSpring)
            }
            panel.orderFrontRegardless()
            // Draw the starting state once so the content has somewhere to
            // animate from.
            panel.displayIfNeeded()
            if !slides { fade(to: 1, completion: nil) }
        } else {
            if wasHiding, isTucked, !reduceMotion {
                mover.settle(to: tuckedFrame(on: panel.screen ?? NSScreen.main).origin, parameters: Motion.materializeSpring)
            }
            fade(to: 1, completion: nil)
            panel.orderFrontRegardless()
        }
        interaction.isPresented = true
        if let surface {
            pager.go(to: surface, animated: true)
        }
        beginExpansionIfNeeded(for: pager.current, animated: true)
        if makeKey {
            takeKeyboard()
        }
        if hostingView.containsPointer {
            interaction.pointerEntered()
        }
        interaction.isWindowVisible = true
        store.refresh()
        onVisibilityChange?(true)
    }

    /// Give the player the keyboard when the user asks for it. The panel takes
    /// keys without activating Hum, but VoiceOver stays with the active app,
    /// so while it's running Hum comes forward too.
    private func takeKeyboard() {
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSApp.activate()
        }
        panel.allowKeyboard()
        panel.makeKey()
    }

    /// Take the window away along the path it came in on.
    private func conceal(animated: Bool) {
        savePlacement()
        presentGeneration += 1
        let generation = presentGeneration
        guard animated else {
            finishHiding()
            return
        }
        isHiding = true
        updatePresentationAnchor()
        interaction.isPresented = false
        let done: @MainActor () -> Void = { [weak self] in
            guard let self, self.presentGeneration == generation else { return }
            self.finishHiding()
        }
        if isTucked, !reduceMotion {
            mover.settle(to: tuckedHiddenOrigin(for: panel.frame), parameters: Motion.materializeSpring, completion: done)
        } else {
            fade(to: 0, completion: done)
        }
    }

    private func finishHiding() {
        isHiding = false
        mover.stop()
        panel.orderOut(nil)
        endExpansion(animated: false)
        materializeOrigin = nil
        panel.alphaValue = 1
        interaction.isPresented = false
        interaction.isWindowVisible = false
        interaction.setKeyboardEngaged(false)
        interaction.pointerExited()
        onVisibilityChange?(false)
    }

    private func fade(to alpha: CGFloat, completion: (@MainActor @Sendable () -> Void)?) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    /// The content materializes from its pinned point: a window pinned Top
    /// Right grows from its top-right corner, a Center one from its center.
    /// Unpinned, from the side against a screen edge. Into and out of Menu
    /// Bar, from the side facing the menu-bar item.
    private func updatePresentationAnchor() {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame, visible.width > 0, visible.height > 0 else {
            interaction.presentationAnchor = .center
            return
        }
        if let origin = materializeOrigin {
            interaction.presentationAnchor = Self.presentationAnchor(toward: origin, from: panel.frame)
            return
        }
        if isTucked {
            interaction.presentationAnchor = .top
            return
        }
        let anchor = pin.map(PlacementResolver.anchor(of:)) ?? PlacementResolver.anchor(of: panel.frame, in: visible)
        // Screen y runs up; UnitPoint y runs down.
        interaction.presentationAnchor = UnitPoint(x: anchor.x, y: 1 - anchor.y)
    }

    /// The point of `frame` nearest `point`, as a `UnitPoint` (y down).
    nonisolated static func presentationAnchor(toward point: CGPoint, from frame: CGRect) -> UnitPoint {
        guard frame.width > 0, frame.height > 0 else { return .center }
        let x = min(max((point.x - frame.minX) / frame.width, 0), 1)
        let y = min(max((point.y - frame.minY) / frame.height, 0), 1)
        return UnitPoint(x: x, y: 1 - y)
    }

    /// Under Menu Bar, the player hangs at the top of its pin's column: a
    /// Center or Bottom pin tucks at Top (DESIGN.md §4.5).
    private func tuckedFrame(on screen: NSScreen?, size: CGSize? = nil) -> CGRect {
        let size = size ?? panel.frame.size
        guard let screen else { return panel.frame }
        return PlacementResolver.frame(for: (pin ?? .initial).tuckPosition, size: size, in: screen.visibleFrame)
    }

    /// Fully behind the menu bar, straight above where it rests.
    private func tuckedHiddenOrigin(for frame: CGRect) -> CGPoint {
        let top = (panel.screen ?? NSScreen.main)?.visibleFrame.maxY ?? frame.maxY
        return CGPoint(x: frame.minX, y: top)
    }

    // MARK: Menus

    /// Pop up a menu just below a control, given its frame in SwiftUI's global
    /// coordinates (top-left origin).
    private func popUp(_ menu: NSMenu, below rect: CGRect) {
        let view = hostingView
        let y = view.isFlipped ? rect.maxY : view.bounds.height - rect.maxY
        menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: y + Spacing.xxs), in: view)
    }

    // MARK: Placement

    /// Put the window where it belongs before it appears: on the display under the
    /// pointer when the user summoned it, otherwise where it was last; at that
    /// display's pin, or where it was dropped.
    private func place(for reason: PlayerVisibilityController.ShowReason) {
        let screen: NSScreen? = switch reason {
        case .user:
            NSScreen.withPointer
        case .launch, .trackChange:
            screen(withKey: settings.window.lastDisplay) ?? NSScreen.withPointer
        }
        guard let screen = screen ?? NSScreen.main else { return }
        let display = screen.displayInfo
        let placement = settings.window.placements[display.id]
        let style = settings.appearance.style
        appliedStyle = style
        expansion = nil
        updateShape()
        var size = settings.window.size(for: style, on: display.id)
            // Before sizes were kept per style, the square's side was all there was.
            ?? (settings.window.styleSizes[display.id] == nil && style.isSquare ? placement.map { PlayerSize(side: $0.side) } : nil)
            ?? StyleGeometry.defaultSize(for: style)
        if !hasBeenPlaced, let side = launchOptions.playerSize {
            size = PlayerSize(side: side)
        }
        let fitted = CGSize(StyleGeometry.clamp(size, for: style))
        sizing.size = PlayerSize(fitted)
        pin = PlacementResolver.pin(for: placement, size: fitted, on: display)
        if !hasBeenPlaced, let launchPin = launchOptions.pin {
            pin = launchPin
        }
        var frame = pin.map { PlacementResolver.frame(for: $0, size: fitted, in: display.visibleFrame) }
            ?? PlacementResolver.frame(for: placement, size: fitted, on: display)
        panel.setFrame(frame, display: false)
        if isTucked {
            frame = tuckedFrame(on: screen)
            panel.setFrame(frame, display: false)
        }
        // Each display remembers its own surface; an explicit launch surface wins
        // the first time.
        if let placement, hasBeenPlaced || launchOptions.surface == nil {
            pager.go(to: placement.surface, animated: false)
        }
        hasBeenPlaced = true
    }

    private func savePlacement() {
        guard hasBeenPlaced, !isInMenuBar, let screen = panel.screen else { return }
        settings.window.lastSurface = pager.current
        let display = screen.displayInfo
        let style = settings.appearance.style
        // Grown for Echo or Status, the window is remembered at the size it
        // goes back to.
        var frame = panel.frame
        if let expansion {
            frame = expansion.restoredFrame(from: frame, pin: pin, in: display.visibleFrame)
        }
        // Each style keeps its own size on each display. Mid-resize sizes are
        // on their way somewhere else, so they're not kept.
        if !mover.isResizing, appliedStyle == style {
            settings.window.setSize(PlayerSize(frame.size), for: style, on: display.id)
            sizing.size = PlayerSize(frame.size)
        }
        // Tucked hangs under the menu bar at its pin's column; the pin itself
        // is still the display's.
        if isTucked, let pin {
            frame = PlacementResolver.frame(for: pin, size: frame.size, in: display.visibleFrame)
        }
        rememberPlacement(of: frame, on: display)
    }

    /// Keep `frame` and the pin as `display`'s placement, and `display` as
    /// the one the player was last on. The frame is `style`'s, the current
    /// style unless given.
    private func rememberPlacement(of frame: CGRect, on display: DisplayInfo, style: PlayerStyleID? = nil) {
        // Bars and Big Art leave the square side as it was, for the square styles.
        let squareSide = (style ?? settings.appearance.style).isSquare
            ? nil
            : settings.window.placements[display.id].map { CGFloat($0.side) } ?? PlayerMetrics.defaultSide
        settings.window.placements[display.id] = PlacementResolver.placement(
            for: frame,
            on: display,
            surface: pager.current,
            side: squareSide,
            pin: pin
        )
        settings.window.lastDisplay = display.id
        settings.window.lastSurface = pager.current
    }

    /// A throw or a drop let go: pin where it settles, or unpin where it was
    /// dropped with snapping off. Under Menu Bar a drop keeps the pin, and
    /// the player rises back under the menu bar.
    private func moverDidRelease(_ snap: SnapProjection.Snap?) {
        if let snap {
            pin = snap.pin
        } else if !isTucked {
            pin = nil
        }
    }

    /// After a drag or a spring comes to rest. Tucked, a player let go away
    /// from its spot under the menu bar rises back to it.
    private func moverDidSettle() {
        if isTucked, !isHiding, panel.isVisible, let screen = panel.screen {
            let home = tuckedFrame(on: screen)
            if abs(home.minX - panel.frame.minX) > 0.5 || abs(home.minY - panel.frame.minY) > 0.5 {
                mover.settle(to: home.origin, parameters: Motion.smoothSpring)
                return
            }
        }
        savePlacement()
    }

    // MARK: Pins

    /// Pin to ▸ and Settings › Player › Position: move there with
    /// `Motion.throw` from where the player is. Hidden, or in Menu Bar, it
    /// opens there next time.
    private func repin(to position: PinPosition) {
        pin = position
        let screen = panel.isVisible ? panel.screen : screen(withKey: settings.window.lastDisplay) ?? NSScreen.main
        guard let screen else { return }
        let display = screen.displayInfo
        let size = mover.destination?.size ?? panel.frame.size
        let target = isTucked
            ? tuckedFrame(on: screen, size: size)
            : PlacementResolver.frame(for: position, size: size, in: display.visibleFrame)
        guard hasBeenPlaced, isVisible else {
            let restSize = sizing.size.map(CGSize.init) ?? size
            rememberPlacement(of: PlacementResolver.frame(for: position, size: restSize, in: display.visibleFrame), on: display)
            return
        }
        if target.size == panel.frame.size {
            mover.settle(to: target.origin, parameters: Motion.throwSpring)
        } else {
            mover.settle(to: target, parameters: Motion.throwSpring)
        }
    }

    // MARK: Shape and size

    /// Where the window goes for a new `size`: holding its pinned point, under
    /// the menu bar when tucked, or, unpinned, holding the corner nearest the
    /// screen's edges.
    private func resizedFrame(_ current: CGRect, to size: CGSize, on screen: NSScreen) -> CGRect {
        if isTucked {
            return tuckedFrame(on: screen, size: size)
        }
        return PlacementResolver.frame(resizing: current, to: size, pin: pin, in: screen.visibleFrame)
    }

    /// The part of an unpinned window to hold still while its size changes.
    private func resizeAnchor(for frame: CGRect, in visible: CGRect) -> CGPoint {
        if isTucked { return CGPoint(x: 0.5, y: 1) }
        return pin.map(PlacementResolver.anchor(of:)) ?? PlacementResolver.anchor(of: frame, in: visible)
    }

    /// Move to `frame` with `Motion.smooth` (or `parameters`), size and position
    /// in one spring, or straight there while hidden.
    private func move(to frame: CGRect, animated: Bool, parameters: SpringParameters = Motion.smoothSpring) {
        if animated, panel.isVisible {
            mover.settle(to: frame, parameters: parameters)
        } else {
            mover.stop()
            panel.setFrame(frame, display: false)
        }
    }

    /// The shape the window has right now: the style's, or a square while
    /// it's grown for Echo or Status.
    private var currentShape: StyleShape {
        let style = settings.appearance.style
        return expansion == nil ? style.shape : .square(sides: StyleGeometry.surfaceSide...StyleGeometry.surfaceSide)
    }

    /// Make the window resize like its shape: a square keeps its aspect
    /// ratio; a bar or Big Art's portrait resizes by width, its height
    /// following.
    private func updateShape() {
        let shape = currentShape
        if case .square = shape {
            panel.contentAspectRatio = NSSize(width: 1, height: 1)
        } else {
            // Any increments clear the square aspect ratio.
            panel.contentResizeIncrements = NSSize(width: 1, height: 1)
        }
        contentView?.shape = shape
        contentView?.cornerShape = expansion == nil ? PlayerContentView.CornerShape(settings.appearance.style) : .panel
    }

    /// A new style: spring to its shape and remembered size, holding the pin.
    /// A bar chosen while Echo or Status is showing stays square until Now.
    /// Into Menu Bar the window leaves toward the menu-bar item; out of it,
    /// it comes back at its pin.
    private func applyStyleGeometry(_ style: PlayerStyleID) {
        guard appliedStyle != style else { return }
        let previous = appliedStyle
        appliedStyle = style
        if !style.hasWindow {
            enterMenuBar(from: previous)
            return
        }
        if let previous, !previous.hasWindow {
            leaveMenuBar()
            return
        }
        expansion = nil
        updateShape()
        guard previous != nil, hasBeenPlaced, let screen = panel.screen ?? NSScreen.main else { return }
        let display = screen.displayInfo
        let visible = display.visibleFrame
        let size = CGSize(StyleGeometry.clamp(
            settings.window.size(for: style, on: display.id) ?? StyleGeometry.defaultSize(for: style),
            for: style
        ))
        sizing.size = PlayerSize(size)
        let current = panel.frame
        let anchor = resizeAnchor(for: current, in: visible)
        var target = resizedFrame(current, to: size, on: screen)
        if panel.isVisible, PlayerExpansion.isNeeded(for: pager.current, style: style) {
            let session = PlayerExpansion(restoreSize: size, anchor: anchor)
            expansion = session
            updateShape()
            target = isTucked ? tuckedFrame(on: screen, size: PlayerExpansion.expandedSize) : session.expandedFrame(from: target, pin: pin, in: visible)
        }
        move(to: target, animated: true, parameters: Motion.styleSwitchSpring)
    }

    /// Settings picked a size: spring to it, holding the pin. Grown for Echo
    /// or Status, the player goes back to it afterwards; hidden, it opens at it.
    private func resize(to preset: PlayerSizePreset) {
        let style = settings.appearance.style
        guard style.hasWindow else { return }
        let size = preset.size(for: style)
        sizing.size = size
        guard let screen = panel.screen ?? screen(withKey: settings.window.lastDisplay) ?? NSScreen.main else { return }
        let display = screen.displayInfo
        settings.window.setSize(size, for: style, on: display.id)
        guard hasBeenPlaced, appliedStyle == style else { return }
        if var session = expansion {
            session.restoreSize = CGSize(size)
            expansion = session
            return
        }
        move(to: resizedFrame(panel.frame, to: CGSize(size), on: screen), animated: true)
    }

    /// Grow a bar to the surface square for Echo or Status (DESIGN.md §7.2).
    private func beginExpansionIfNeeded(for surface: Surface, animated: Bool) {
        guard expansion == nil, hasBeenPlaced, let screen = panel.screen ?? NSScreen.main else { return }
        guard PlayerExpansion.isNeeded(for: surface, style: settings.appearance.style) else { return }
        let frame = panel.frame
        let visible = screen.visibleFrame
        let size = PlayerExpansion.restoreSize(frame: frame, heading: mover.resizeDestination)
        let session = PlayerExpansion(restoreSize: size, anchor: resizeAnchor(for: frame, in: visible))
        expansion = session
        updateShape()
        let target = isTucked
            ? tuckedFrame(on: screen, size: PlayerExpansion.expandedSize)
            : session.expandedFrame(from: frame, pin: pin, in: visible)
        move(to: target, animated: animated)
    }

    /// Back to the size and shape from before the expansion.
    private func endExpansion(animated: Bool) {
        guard let session = expansion else { return }
        expansion = nil
        updateShape()
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let target = isTucked
            ? tuckedFrame(on: screen, size: session.restoreSize)
            : session.restoredFrame(from: panel.frame, pin: pin, in: screen.visibleFrame)
        move(to: target, animated: animated)
    }

    private func surfaceDidChange(_ surface: Surface) {
        if let expansion, !expansion.holds(on: surface) {
            endExpansion(animated: isVisible)
        }
        if isVisible {
            beginExpansionIfNeeded(for: surface, animated: true)
        }
        savePlacement()
    }

    private func screen(withKey key: String?) -> NSScreen? {
        guard let key else { return nil }
        return NSScreen.screens.first { $0.displayKey == key }
    }

    /// A display, the Dock, or the menu bar changed: a pinned player moves
    /// to its pin on the new visible frame; an unpinned one stays on screen.
    private func screenParametersDidChange() {
        guard panel.isVisible, !mover.isMoving, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = isTucked
            ? tuckedFrame(on: screen)
            : pin.map { PlacementResolver.frame(for: $0, size: panel.frame.size, in: visible) }
                ?? PlacementResolver.clamp(panel.frame, to: visible)
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: Menu Bar

    /// Going into Menu Bar from `previous`: the window leaves toward the
    /// menu-bar item with `Motion.materialize`, and stays hidden (DESIGN.md
    /// §7.1). Its size and pin are kept for `previous`, for Pop Out.
    private func enterMenuBar(from previous: PlayerStyleID?) {
        savePlacementForStyle(previous)
        expansion = nil
        guard panel.isVisible else { return }
        visibility.userDidHide()
        materializeOrigin = statusItemCenter
        conceal(animated: true)
    }

    /// Pop Out Player: the window comes back at its pin in the style it had,
    /// materializing from the menu-bar item. Popping out summons the player,
    /// so it takes the keyboard, unless another of Hum's windows has it: a
    /// style picked in Settings leaves the keyboard in Settings.
    private func leaveMenuBar() {
        expansion = nil
        updateShape()
        materializeOrigin = statusItemCenter
        let otherWindowIsKey = NSApp.keyWindow.map { $0 !== panel && $0.canBecomeMain } ?? false
        present(.user, surface: .now, makeKey: !otherWindowIsKey)
        visibility.userDidShow()
    }

    /// The size the window had, kept for its style before going into Menu
    /// Bar, which has no size of its own.
    private func savePlacementForStyle(_ style: PlayerStyleID?) {
        guard hasBeenPlaced, panel.isVisible, let style, style.hasWindow, let screen = panel.screen else { return }
        let display = screen.displayInfo
        var frame = mover.destination ?? panel.frame
        if let expansion {
            frame = expansion.restoredFrame(from: frame, pin: pin, in: display.visibleFrame)
        }
        settings.window.setSize(PlayerSize(frame.size), for: style, on: display.id)
        rememberPlacement(of: isTucked && pin != nil ? PlacementResolver.frame(for: pin!, size: frame.size, in: display.visibleFrame) : frame, on: display, style: style)
    }

    private var statusItemCenter: CGPoint? {
        statusItemFrame?().map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    /// Settings' look at the hover controls: up for a moment, as if pointed
    /// at, then away unless the pointer is really there.
    private func revealControlsBriefly() {
        guard isVisible, !isInMenuBar else { return }
        interaction.pointerEntered()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.settingsRevealSeconds))
            guard let self, !self.hostingView.containsPointer else { return }
            self.interaction.pointerExited()
        }
    }

    // MARK: Wiring

    private func wire() {
        sizing.resize = { [weak self] preset in self?.resize(to: preset) }
        sizing.repin = { [weak self] position in self?.repin(to: position) }
        sizing.reveal = { [weak self] in self?.revealControlsBriefly() }
        hostingView.onPointerInsideChange = { [weak self] inside in
            guard let self else { return }
            if inside {
                self.interaction.pointerEntered()
                // The controls about to show read the app afresh, for a
                // shuffle or repeat changed there unannounced (§13.34).
                self.store.refresh()
            } else {
                self.interaction.pointerExited()
            }
        }
        interaction.onEngagementChange = { [weak self] in
            self?.visibility.engagementDidChange()
        }
        panel.onKeyStatusChange = { [weak self] isKey in
            guard let self else { return }
            if isKey {
                // A borderless panel keeps the keyboard itself, and Tab then
                // walks AppKit's loop, which skips the player's controls.
                // Hand it to the SwiftUI content so Tab moves between them.
                if self.panel.firstResponder === self.panel {
                    self.panel.makeFirstResponder(self.hostingView)
                }
                return
            }
            self.interaction.setKeyboardEngaged(false)
            self.visibility.playerDidResignKey()
        }
        panel.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }

        visibility.show = { [weak self] reason in
            // Visibility modes don't apply in Menu Bar (DESIGN.md §7.1).
            guard let self, !self.isInMenuBar else { return }
            self.present(reason, surface: nil, makeKey: false)
        }
        visibility.hide = { [weak self] in
            self?.conceal(animated: true)
        }
        visibility.isVisible = { [weak self] in
            self?.isVisible ?? false
        }
        visibility.isEngaged = { [weak self] in
            guard let self else { return false }
            return self.interaction.isEngaged || self.panel.isKeyWindow
        }

        pager.frameDriver = DisplayLinkFrameDriver(view: hostingView)
        pager.onGestureSettle = {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        mover.snapsToCorners = { [weak self] in
            self?.settings.behavior.snapToCorners ?? true
        }
        mover.snapPins = { [weak self] in
            // Under Menu Bar, only the top row is under the menu bar.
            self?.isTucked == true ? PinPosition.rows[0] : PinPosition.allCases
        }
        mover.onRelease = { [weak self] snap in
            self?.moverDidRelease(snap)
        }
        mover.onSettle = { [weak self] in
            self?.moverDidSettle()
        }
        pager.onSurfaceChange = { [weak self] surface in
            self?.surfaceDidChange(surface)
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleScroll(ScrollSample(event), at: self.contentPoint(of: event)) ? nil : event
        }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handlePinch(event) ? nil : event
        }
        appearanceObservation = panel.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applyLookToWindow() }
        }

        if let handles = (panel.contentView as? PlayerContentView)?.handles {
            for handle in handles {
                handle.onResize = { [weak self] frame in
                    self?.resizeDragged(to: frame)
                }
                handle.onResizeEnd = { [weak self] in
                    self?.panel.invalidateShadow()
                    self?.savePlacement()
                }
            }
        }

        trackObservation = store.addObserver { [weak self] event in
            // The same song starting over under repeat one isn't a new track.
            guard case .trackChanged(let previous, let current, _, _) = event,
                  let previous, let current, previous.id != current.id
            else { return }
            self?.visibility.trackDidChange()
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersDidChange() }
        }

        observeChanges { [weak self] in
            guard let self else { return }
            self.apply(self.settings.behavior, self.settings.appearance)
        }
    }

    /// A resize handle's drag: the size it asks for, held at the pin.
    private func resizeDragged(to frame: CGRect) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let target = isTucked
            ? tuckedFrame(on: screen, size: frame.size)
            : pin.map { PlacementResolver.frame(for: $0, size: frame.size, in: screen.visibleFrame) } ?? frame
        panel.setFrame(target, display: true)
    }

    private func apply(_ behavior: BehaviorSettings, _ appearance: AppearanceSettings) {
        panel.level = behavior.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = behavior.showOnAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
        visibility.mode = behavior.visibility
        interaction.alwaysReveal = launchOptions.revealControls || appearance.alwaysShowControls
        panel.appearance = switch launchOptions.appearance ?? appearance.mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        applyLookToWindow()
        // Outside this observation pass: the geometry reads the pager and the
        // window, which shouldn't re-run `apply`.
        let style = appearance.style
        Task { @MainActor [weak self] in self?.applyStyleGeometry(style) }
    }

    /// The parts of the look the window itself draws: its corner radius.
    private func applyLookToWindow() {
        let appearance = LookAppearance(panel.effectiveAppearance)
        let look = settings.appearance.look(in: appearance)
        (panel.contentView as? PlayerContentView)?.cornerRadiusScale = CGFloat(look.cornerRadiusScale)
    }

    // MARK: Gestures

    /// Two-finger swipes: across surfaces, skipping tracks on Now when "Swipe to
    /// skip" is on, or up and down over Now's cover for the volume. Returns
    /// whether the event was used.
    private func handleScroll(_ sample: ScrollSample, at point: CGPoint) -> Bool {
        let behavior = settings.behavior
        if behavior.swipeToSkip, pager.current == .now, !pager.isMoving {
            let outcome = swipeSkip.handle(sample)
            if outcome.claimed {
                // The pager saw the start; let it go before it moves.
                let cancel = ScrollSample(
                    phase: .cancelled,
                    isMomentum: false,
                    fingerDeltaX: 0,
                    deltaY: 0,
                    isPrecise: true,
                    timestamp: sample.timestamp
                )
                _ = pager.handle(cancel)
            }
            if let skip = outcome.skip {
                send(skip == .next ? .next : .previous)
            }
            if outcome.consumed { return true }
        }
        if behavior.swipeBetweenSurfaces, pager.handle(sample) == .consumed {
            return true
        }
        return handleVolumeSwipe(sample, at: point)
    }

    private func handleVolumeSwipe(_ sample: ScrollSample, at point: CGPoint) -> Bool {
        let canSwipe = pager.current == .now && !pager.isMoving && store.capabilities.contains(.volume)
        let isOverArtwork = canSwipe && interaction.volumeSwipeArea?.contains(point) == true
        let outcome = swipeVolume.handle(sample, isOverArtwork: isOverArtwork, volume: store.snapshot.volume ?? 0.5)
        if let level = outcome.level {
            setVolume(level)
        }
        return outcome.consumed
    }

    /// A pinch steps the player between size classes, in any shape, through
    /// the same spring as picking a size in Settings. Not while it's grown for
    /// Echo or Status.
    private func handlePinch(_ event: NSEvent) -> Bool {
        guard let phase = PinchResizeTracker.Phase(event.phase) else { return false }
        guard let step = pinch.handle(phase, magnification: Double(event.magnification)),
              expansion == nil
        else { return true }
        let style = settings.appearance.style
        // The size it's heading for, so a second step mid-spring counts from there.
        let size = sizing.size ?? PlayerSize(panel.frame.size)
        if let preset = PlayerSizePreset(size, style: style).stepped(step) {
            resize(to: preset)
        }
        return true
    }

    /// Where an event happened in the content's coordinates: top-left origin, as
    /// SwiftUI lays it out.
    private func contentPoint(of event: NSEvent) -> CGPoint {
        let point = hostingView.convert(event.locationInWindow, from: nil)
        return hostingView.isFlipped ? point : CGPoint(x: point.x, y: hostingView.bounds.height - point.y)
    }

    /// Set the volume and show it in the HUD.
    private func setVolume(_ level: Double) {
        guard store.capabilities.contains(.volume) else { return }
        let level = min(1, max(0, level))
        store.setVolume(level)
        interaction.showVolumeHUD(level: level)
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let isEditingText = panel.firstResponder is NSText
        if event.keyCode == 48 {
            // Tab: moving focus between controls reveals them.
            interaction.setKeyboardEngaged(true)
            return false
        }
        guard let command = PlayerKeyCommand.resolve(
            PlayerKeyCommand.KeyPress(event),
            isEditingText: isEditingText,
            controlHasFocus: interaction.isControlFocused,
            popoverIsOpen: interaction.isPopoverOpen
        ) else {
            return false
        }
        interaction.setKeyboardEngaged(true)
        perform(command)
        return true
    }

    private func perform(_ command: PlayerKeyCommand) {
        switch command {
        case .showSurface(let surface):
            pager.go(to: surface, animated: true)
        case .nextSurface:
            pager.forward(animated: true)
        case .previousSurface:
            pager.back(animated: true)
        case .openSettings:
            actions.openSettings()
        case .closePopover:
            interaction.closePopover()
        case .dismiss:
            if pager.current != .now {
                pager.go(to: .now, animated: true)
            } else if settings.behavior.visibility == .pinned {
                interaction.setKeyboardEngaged(false)
            } else {
                hide()
            }
        case .hidePlayer:
            hide()
        case .playPause:
            send(.togglePlayPause)
        case .nextTrack:
            send(.next)
        case .previousTrack:
            send(.previous)
        case .volumeUp:
            setVolume((store.snapshot.volume ?? 0.5) + Self.volumeStep)
        case .volumeDown:
            setVolume((store.snapshot.volume ?? 0.5) - Self.volumeStep)
        case .toggleFavorite:
            // Saved or removed, with the HUD to say so.
            store.toggleSaveAndConfirm()
        }
    }

    /// Send a command only if the source can do it, so a key press never fails.
    private func send(_ command: PlaybackCommand) {
        guard store.capabilities.supports(command) else { return }
        store.send(command)
    }

    // MARK: NSWindowDelegate

    public func windowDidMove(_ notification: Notification) {
        savePlacement()
    }

    public func windowDidResize(_ notification: Notification) {
        savePlacement()
    }

    /// The system's own resize, from the window's edge outside the handles,
    /// keeps the style's shape (§7). Everything Hum resizes itself goes
    /// through `setFrame(_:display:)`, which doesn't ask.
    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let current = PlayerSize(width: Double(sender.frame.width), height: Double(sender.frame.height))
        let size = currentShape.size(
            resizedTo: PlayerSize(width: Double(frameSize.width), height: Double(frameSize.height)),
            from: current
        )
        return NSSize(width: size.width, height: size.height)
    }

    public func windowDidChangeOcclusionState(_ notification: Notification) {
        interaction.isWindowVisible = panel.isVisible && panel.occlusionState.contains(.visible)
    }
}

private extension LookAppearance {
    init(_ appearance: NSAppearance) {
        self = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

/// Lets the actions handed to views reach the controller once it exists, without
/// keeping it alive.
private final class ActionRelay {
    weak var controller: PlayerWindowController?
}
