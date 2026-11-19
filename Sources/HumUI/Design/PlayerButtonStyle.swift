import HumCore
import SwiftUI

/// Hum's own button families (DESIGN.md §5.9). Every button in Hum uses one of
/// these or a system text style.
///
/// Press feedback starts on mouse-down, holds for at least `Motion.minimumPress`,
/// and survives the pointer drifting `Motion.pressHysteresis` outside the hit
/// target. The action commits on mouse-up inside, never on the way down. A focused
/// button responds to Space and Return with the same press sequence.
struct PlayerButtonStyle: PrimitiveButtonStyle {
    enum Family: Hashable, Sendable {
        /// A bare glyph over artwork: previous, next, play/pause.
        case transport
        /// A bare glyph that turns accent with a dot under it when on: shuffle, repeat.
        case toggle
        /// A bare glyph with a backing on hover: more, volume, devices, dismiss,
        /// Pop Out Player.
        case icon
        /// The accent circle that rises into a card's artwork on hover.
        case cardPlay
        /// A capsule with a text label: the History window's filters. `isOn` is
        /// the selected chip.
        case chip
        /// The whole card is the button, with no backing: insight cards. The
        /// label reads `\.playerCard` for its hover and focus, and marks its
        /// artwork with `cardFocusRing(_:)`.
        case card
    }

    /// What happens when a press is held past `holdDelay` (skip buttons scan).
    struct Hold {
        var begin: @MainActor () -> Void
        var end: @MainActor () -> Void
    }

    static let holdDelay: Duration = .milliseconds(500)

    var family: Family
    var size: ControlSizing
    /// The size class a chip is drawn at.
    var sizeClass: PlayerSizeClass = .medium
    /// The on state, for toggles; the selected chip.
    var isOn = false
    /// Mark the on state with a dot under the glyph. Save uses its filled glyph instead.
    var showsOnBacking = true
    /// What the glyph shows, for a toggle with more states than on and off:
    /// repeat's mode. A change moves with the on state's own animation, so a
    /// label with `.contentTransition(.opacity)` cross-fades in step with the
    /// color and the dot (§13.34).
    var glyphState: AnyHashable?
    /// The source is still loading: the glyph dims to `quaternaryLabel`.
    var isWaiting = false
    /// The chip is pinned over content that scrolls under it, so it floats.
    var floatsOverContent = false
    /// How far the hit target reaches past the backing on each side, after
    /// splitting the space with neighbors. Defaults to `size.outset`.
    var hitExtents: (leading: CGFloat, trailing: CGFloat)?
    var hold: Hold?
    /// Each change gives the button keyboard focus, for focus coming back from
    /// a popover it opened.
    var focusRequest = 0

    init(
        _ family: Family,
        size: ControlSizing,
        isOn: Bool = false,
        showsOnBacking: Bool = true,
        glyphState: AnyHashable? = nil,
        isWaiting: Bool = false,
        hitExtents: (leading: CGFloat, trailing: CGFloat)? = nil,
        hold: Hold? = nil,
        focusRequest: Int = 0
    ) {
        self.family = family
        self.size = size
        self.isOn = isOn
        self.showsOnBacking = showsOnBacking
        self.glyphState = glyphState
        self.isWaiting = isWaiting
        self.hitExtents = hitExtents
        self.hold = hold
        self.focusRequest = focusRequest
    }

    /// A chip or a card, which size to their label.
    ///
    /// `PlayerButtonStyle(.chip, isOn: isSelected)` for a filter chip, with
    /// `floatsOverContent` for one pinned over scrolling content;
    /// `PlayerButtonStyle(.card)` for a card.
    init(_ family: Family, sizeClass: PlayerSizeClass = .medium, isOn: Bool = false, floatsOverContent: Bool = false) {
        self.family = family
        self.size = .icon
        self.sizeClass = sizeClass
        self.isOn = isOn
        self.floatsOverContent = floatsOverContent
    }

    func makeBody(configuration: Configuration) -> some View {
        PlayerButtonBody(configuration: configuration, style: self)
    }

    /// How far the button shrinks while pressed. Chips don't scale.
    static func pressedScale(_ family: Family) -> CGFloat {
        switch family {
        case .transport, .toggle, .icon: 0.88
        case .cardPlay: 0.92
        case .card: 0.98
        case .chip: 1
        }
    }

    /// The accent dot under an active toggle.
    static let onDot: CGFloat = 4
    /// From the glyph's bottom edge to the dot.
    static let onDotGap = Spacing.xxs
}

/// The Chip family's sizes (DESIGN.md §3.8).
nonisolated enum ChipMetrics {
    /// The capsule's height: 24 at S and M, 28 at L.
    static func height(_ sizeClass: PlayerSizeClass) -> CGFloat {
        sizeClass == .large ? 28 : 24
    }

    /// Between the capsule's ends and its text: 10 at S and M, 12 at L.
    static func padding(_ sizeClass: PlayerSizeClass) -> CGFloat {
        sizeClass == .large ? 12 : 10
    }

    /// A chip shorter than the 28-pt minimum target reaches past its capsule,
    /// above and below, to make it up.
    static func verticalOutset(_ sizeClass: PlayerSizeClass) -> CGFloat {
        max(0, (ControlSizing.minimumHit(sizeClass, isTertiary: false) - height(sizeClass)) / 2)
    }

    static let font = Font.callout.weight(.medium)
}

/// What a card's label needs to know about its button: the floating play
/// rises and standard art dims while hovered, and the artwork carries the
/// focus ring.
nonisolated struct PlayerCardState: Equatable, Sendable {
    var isHovered = false
    var isFocused = false
    var isPressed = false
}

private nonisolated struct PlayerCardKey: EnvironmentKey {
    static let defaultValue = PlayerCardState()
}

extension EnvironmentValues {
    /// The state of the `PlayerButtonStyle(.card)` this view is the label of.
    nonisolated var playerCard: PlayerCardState {
        get { self[PlayerCardKey.self] }
        set { self[PlayerCardKey.self] = newValue }
    }
}

extension View {
    /// The card's keyboard focus ring, drawn on `shape`: the card's own on an
    /// insight card (DESIGN.md §5.9). It takes the system's focus-indicator
    /// color and sits just outside the shape, as the system ring does around a
    /// native control.
    func cardFocusRing<S: InsettableShape>(_ shape: S) -> some View {
        modifier(CardFocusRing(shape: shape))
    }
}

private struct CardFocusRing<S: InsettableShape>: ViewModifier {
    var shape: S

    @Environment(\.playerCard) private var card

    static var width: CGFloat { 3 }

    func body(content: Content) -> some View {
        content.overlay {
            if card.isFocused {
                shape.inset(by: -Self.width)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: Self.width)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct PlayerButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let style: PlayerButtonStyle

    @Environment(PlayerInteraction.self) private var interaction: PlayerInteraction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isInWindowGlass) private var isInWindowGlass
    @Environment(\.humColorContext) private var colorContext
    @Environment(\.isInControlsPlatter) private var isInControlsPlatter
    @Environment(\.transportHitExtent) private var transportHitExtent
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var press = PressTracker()
    @State private var holdTask: Task<Void, Never>?
    @State private var releaseTask: Task<Void, Never>?
    @State private var focusToken = UUID()
    /// When this button last committed, so a change to `isOn` that didn't come
    /// from it (an optimistic state reverting) can be told apart.
    @State private var lastCommit: ContinuousClock.Instant?
    /// The chip's or card's own size, for the press hysteresis.
    @State private var labelSize: CGSize = .zero
    @FocusState private var isFocused: Bool

    /// A change to `isOn` this soon after a commit is the commit's own.
    static var ownChangeWindow: Duration { .milliseconds(500) }

    var body: some View {
        switch style.family {
        case .transport, .toggle, .icon, .cardPlay:
            glyphButton
        case .chip:
            chipButton
        case .card:
            cardButton
        }
    }

    // MARK: Glyph families

    private var glyphButton: some View {
        let extents = style.hitExtents
            ?? transportHitExtent.map { ($0, $0) }
            ?? (style.size.outset, style.size.outset)
        let backing = style.size.backing
        return ZStack {
            backingShape
            configuration.label
                .font(.system(size: style.size.glyph, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(glyphColor)
                .modifier(GlyphLegibility(isOn: castsShadow))
            if style.family == .toggle, style.isOn, style.showsOnBacking {
                Circle()
                    .fill(HumColor.accent)
                    .frame(width: PlayerButtonStyle.onDot, height: PlayerButtonStyle.onDot)
                    .offset(y: style.size.glyph / 2 + PlayerButtonStyle.onDotGap + PlayerButtonStyle.onDot / 2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: backing, height: backing)
        .compositingGroup()
        .modifier(PressFeedback(isPressed: isPressed, scale: PlayerButtonStyle.pressedScale(style.family), reduceMotion: reduceMotion))
        .animation(Motion.snappy, value: isHovered)
        .animation(isOnAnimation, value: style.isOn)
        .animation(isOnAnimation, value: style.glyphState)
        // The system draws the focus ring in the backing's circle. Like a native
        // button, it takes focus from keyboard navigation, never from a click.
        .contentShape(.focusEffect, Circle())
        .modifier(keyboard)
        .padding(.leading, extents.leading)
        .padding(.trailing, extents.trailing)
        .padding(.vertical, style.size.outset)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering && isEnabled
        }
        .gesture(pressGesture(size: CGSize(
            width: extents.leading + backing + extents.trailing,
            height: backing + style.size.outset * 2
        )))
        .modifier(lifecycle)
    }

    @ViewBuilder
    private var backingShape: some View {
        switch style.family {
        case .cardPlay:
            Circle()
                .fill(HumColor.accent)
                .humShadow(.cardPlay)
        default:
            Circle()
                .fill(isPressed ? HumColor.fillTertiary : HumColor.fillQuaternary)
                .opacity(isPressed || isHovered ? 1 : 0)
        }
    }

    private var glyphColor: HumColor {
        if style.isWaiting { return .quaternaryLabel }
        switch style.family {
        case .transport: return .label
        case .cardPlay: return .onAccent
        // Hover brings up the backing only; the glyph stays as it was.
        case .toggle: return style.isOn ? .accent : .secondaryLabel
        default: return isHovered || isPressed ? .label : .secondaryLabel
        }
    }

    /// Transport and toggle glyphs over artwork take a soft shadow for
    /// legibility (DESIGN.md §3.6). In the controls platter its dimming carries
    /// them, and on material the glyph needs none.
    private var castsShadow: Bool {
        (style.family == .transport || style.family == .toggle)
            && colorContext == .artwork
            && !isInControlsPlatter
    }

    // MARK: Chip

    private var chipButton: some View {
        let sizeClass = style.sizeClass
        let outset = ChipMetrics.verticalOutset(sizeClass)
        return configuration.label
            .font(ChipMetrics.font)
            .lineLimit(1)
            .foregroundStyle(style.isOn ? HumColor.onLabel : HumColor.label)
            .padding(.horizontal, ChipMetrics.padding(sizeClass))
            .frame(height: ChipMetrics.height(sizeClass))
            .modifier(ChipBacking(
                isSelected: style.isOn,
                isHighlighted: isHovered || isPressed,
                usesGlass: style.floatsOverContent && !style.isOn && !reduceTransparency && !isInWindowGlass
                    && LiquidGlass.isOn(settings)
            ))
            .animation(Motion.snappy, value: isHovered)
            .animation(isOnAnimation, value: style.isOn)
            .contentShape(.focusEffect, Capsule())
            .modifier(keyboard)
            .padding(.vertical, outset)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGSize.self) { $0.size } action: { labelSize = $0 }
            .onHover { hovering in
                isHovered = hovering && isEnabled
            }
            .gesture(pressGesture(size: labelSize))
            .modifier(lifecycle)
    }

    // MARK: Card

    private var cardButton: some View {
        configuration.label
            .environment(\.playerCard, PlayerCardState(isHovered: isHovered, isFocused: isFocused, isPressed: isPressed))
            .modifier(PressFeedback(isPressed: isPressed, scale: PlayerButtonStyle.pressedScale(.card), reduceMotion: reduceMotion))
            .animation(Motion.snappy, value: isHovered)
            // The label draws the ring on its artwork (`cardFocusRing`).
            .focusEffectDisabled()
            .modifier(keyboard)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGSize.self) { $0.size } action: { labelSize = $0 }
            .onHover { hovering in
                isHovered = hovering && isEnabled
            }
            .gesture(pressGesture(size: labelSize))
            .modifier(lifecycle)
    }

    // MARK: Shared

    /// A change to `isOn` (or `glyphState`) from this button's own commit
    /// moves with the toggle (`snappy`). One that came from elsewhere, such as
    /// an optimistic state the source never confirmed reverting, moves with
    /// `smooth` (§4.6).
    private var isOnAnimation: Animation {
        let isOwn = lastCommit.map { ContinuousClock.now - $0 < Self.ownChangeWindow } ?? false
        return isOwn ? Motion.snappy : Motion.smooth
    }

    private var keyboard: KeyboardActivation {
        KeyboardActivation(isEnabled: isEnabled, isFocused: $isFocused, activate: keyboardActivate)
    }

    private var lifecycle: ButtonLifecycle {
        ButtonLifecycle(
            isFocused: isFocused,
            focusRequest: style.focusRequest,
            onFocusChange: { focused in interaction?.setControlFocused(focused, token: focusToken) },
            onFocusRequest: { isFocused = true },
            onDisappear: {
                interaction?.setControlFocused(false, token: focusToken)
                holdTask?.cancel()
                releaseTask?.cancel()
            }
        )
    }

    // MARK: Pressing

    private func pressGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard isEnabled else { return }
                if !press.isTracking {
                    begin()
                }
                let bounds = CGRect(origin: .zero, size: size)
                    .insetBy(dx: -Motion.pressHysteresis, dy: -Motion.pressHysteresis)
                let inside = bounds.contains(value.location)
                press.isInside = inside
                // Drifting out cancels the press look; coming back re-arms it.
                if !press.didHold { setPressed(inside) }
            }
            .onEnded { value in
                guard press.isTracking else { return }
                let bounds = CGRect(origin: .zero, size: size)
                    .insetBy(dx: -Motion.pressHysteresis, dy: -Motion.pressHysteresis)
                finish(commit: bounds.contains(value.location))
            }
    }

    private func begin() {
        releaseTask?.cancel()
        press = PressTracker(isTracking: true, isInside: true, start: .now)
        setPressed(true)
        guard let hold = style.hold else { return }
        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(for: PlayerButtonStyle.holdDelay)
            guard !Task.isCancelled, press.isTracking, press.isInside else { return }
            press.didHold = true
            hold.begin()
        }
    }

    private func finish(commit: Bool) {
        holdTask?.cancel()
        holdTask = nil
        let tracker = press
        press = PressTracker()
        if tracker.didHold {
            style.hold?.end()
        } else if commit {
            lastCommit = .now
            configuration.trigger()
        }
        release(after: tracker.start)
    }

    private func keyboardActivate() {
        guard isEnabled else { return }
        releaseTask?.cancel()
        let start = ContinuousClock.now
        setPressed(true)
        lastCommit = start
        configuration.trigger()
        release(after: start)
    }

    /// Spring back once the press has shown for at least `Motion.minimumPress`.
    private func release(after start: ContinuousClock.Instant?) {
        let remaining = start.map { Motion.minimumPress - (ContinuousClock.now - $0) } ?? .zero
        guard remaining > .zero else {
            setPressed(false)
            return
        }
        releaseTask = Task {
            try? await Task.sleep(for: remaining)
            guard !Task.isCancelled else { return }
            setPressed(false)
        }
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
    }
}

/// The pressed scale, eased in on mouse-down (`Motion.press`) and sprung back
/// on release (`Motion.snappy`). Under Reduce Motion nothing scales; the
/// backing still shows the press.
private struct PressFeedback: ViewModifier {
    var isPressed: Bool
    var scale: CGFloat
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? scale : 1)
            .animation(isPressed ? Motion.press : Motion.snappy, value: isPressed)
    }
}

/// `HumShadow.glyphOnArt` on a glyph over artwork.
private struct GlyphLegibility: ViewModifier {
    var isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.humShadow(.glyphOnArt)
        } else {
            content
        }
    }
}

/// A chip's capsule. Selected, a `label` fill under inverted text. Otherwise
/// `fillQuaternary`, `fillTertiary` while hovered or pressed; or, pinned over
/// scrolling content on macOS 26, interactive Liquid Glass, which shows its
/// own hover and press (DESIGN.md §5.6).
private struct ChipBacking: ViewModifier {
    var isSelected: Bool
    var isHighlighted: Bool
    var usesGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), usesGlass {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(
                isSelected ? HumColor.label : (isHighlighted ? HumColor.fillTertiary : HumColor.fillQuaternary),
                in: Capsule()
            )
        }
    }
}

/// Focus from keyboard navigation, never from a click, as a native button's;
/// Space and Return press it.
private struct KeyboardActivation: ViewModifier {
    var isEnabled: Bool
    var isFocused: FocusState<Bool>.Binding
    var activate: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable(isEnabled, interactions: .activate)
            .focused(isFocused)
            .onKeyPress(keys: [.space, .return]) { _ in
                activate()
                return .handled
            }
    }
}

/// Reports focus to the player (so the controls stay revealed), takes focus
/// on request, and ends any press when the button goes away.
private struct ButtonLifecycle: ViewModifier {
    var isFocused: Bool
    var focusRequest: Int
    var onFocusChange: (Bool) -> Void
    var onFocusRequest: () -> Void
    var onDisappear: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: isFocused) { _, focused in onFocusChange(focused) }
            .onChange(of: focusRequest) { onFocusRequest() }
            .onDisappear(perform: onDisappear)
    }
}

/// One press, from mouse-down to mouse-up.
private struct PressTracker {
    var isTracking = false
    var isInside = false
    var start: ContinuousClock.Instant?
    /// The hold action started, so release ends it instead of triggering.
    var didHold = false
}
