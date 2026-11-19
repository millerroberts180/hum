import AppKit
import SwiftUI

/// A slider’s track and fill: 4 pt at rest, 7 pt when active, in Apple's white
/// scrubber colors (`scrubberFill` over `scrubberTrack`, DESIGN.md §5.2),
/// never the accent. There's no knob: the end of the fill is the playhead.
/// Standing on end (`.vertical`) it fills from the bottom.
struct CapsuleTrack: View {
    var fraction: Double
    var isActive: Bool
    var axis: Axis = .horizontal

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let thickness = isActive ? SliderMetrics.activeThickness : SliderMetrics.restThickness
        let fill = min(1, max(0, fraction))
        GeometryReader { proxy in
            ZStack(alignment: axis == .horizontal ? .leading : .bottom) {
                Rectangle().fill(HumColor.scrubberTrack)
                Rectangle()
                    .fill(HumColor.scrubberFill)
                    .frame(
                        width: axis == .horizontal ? proxy.size.width * fill : nil,
                        height: axis == .vertical ? proxy.size.height * fill : nil
                    )
            }
        }
        .frame(width: axis == .vertical ? thickness : nil, height: axis == .horizontal ? thickness : nil)
        .clipShape(Capsule())
        .animation(Motion.spatial(Motion.snappy, reduceMotion: reduceMotion), value: isActive)
    }
}

/// What a slider reports, in order.
nonisolated enum SliderEvent: Equatable, Sendable {
    case editingChanged(Bool)
    case changed(Double)
    case committed(Double)

    /// One arrow-key step from `value`: a complete edit, begun, changed,
    /// committed, and ended, so nothing waits for a release that never comes.
    static func keyStep(from value: Double, by delta: Double) -> [SliderEvent] {
        let next = min(1, max(0, value + delta))
        return [.editingChanged(true), .changed(next), .committed(next), .editingChanged(false)]
    }
}

/// Seek and volume.
///
/// - Click anywhere to jump there; the fill moves with `Motion.smooth`.
/// - Drag 1:1, keeping the grab offset; ⌥ scrubs at quarter speed. The fill
///   follows the pointer exactly while dragging, without animation.
/// - The value is reported live through `onChange` and once more through
///   `onCommit` on release. Ends clamp.
/// - When focused, ← and → (↑ and ↓ standing on end) step by
///   `keyStep(shift:)`. Each step is a whole edit (`SliderEvent.keyStep`).
/// - `.vertical` stands it on end, louder at the top: the S volume popover.
/// - With `accessibility`, the track itself reads to VoiceOver as a system
///   slider, so the element that takes keyboard focus is the one VoiceOver
///   lands on when Tab reaches it.
struct HumSlider<Tag: View>: View {
    /// 0...1, from the model.
    var value: Double
    var isEnabled = true
    var axis: Axis = .horizontal
    /// Take keyboard focus on appearing, as the slider in a popover does.
    var focusesOnAppear = false
    var keyStep: (_ shift: Bool) -> Double
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }
    var accessibility: SliderAccessibility?
    /// The hover tag above the track for the fraction under the pointer, if any.
    @ViewBuilder var hoverTag: (Double) -> Tag

    @Environment(PlayerInteraction.self) private var interaction: PlayerInteraction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: DragState?
    /// Where a click jumped to, shown until the model catches up.
    @State private var pending: Double?
    @State private var isHovered = false
    @State private var hoverX: CGFloat?
    @State private var tagSize: CGSize = .zero
    /// The track's length along its axis.
    @State private var width: CGFloat = 1
    @State private var focusToken = UUID()
    @FocusState private var isFocused: Bool

    /// How close to the end of the fill a press counts as grabbing it.
    static var grabRadius: CGFloat { 8 }
    static var fineScrubRate: Double { 0.25 }
    static var catchUpTolerance: Double { 0.01 }
    /// Matches the optimistic-state revert in §4.6.
    static var pendingTimeout: Duration { .milliseconds(1500) }

    private struct DragState {
        var value: Double
        /// The last pointer position along the axis, from the value's low end.
        var lastX: CGFloat
    }

    var body: some View {
        let shown = drag?.value ?? pending ?? value
        let isVertical = axis == .vertical
        CapsuleTrack(fraction: shown, isActive: isEnabled && (isHovered || drag != nil || isFocused), axis: axis)
            .frame(maxWidth: isVertical ? nil : .infinity, maxHeight: isVertical ? .infinity : nil)
            .frame(width: isVertical ? SliderMetrics.hitHeight : nil, height: isVertical ? nil : SliderMetrics.hitHeight)
            .contentShape(Rectangle())
            .contentShape(.focusEffect, TrackFocusShape(axis: axis))
            .overlay(alignment: .topLeading) {
                if isEnabled, !isVertical, drag == nil, let hoverX {
                    let origin = HoverTagPlacement.origin(pointer: hoverX, tagSize: tagSize, trackLength: width)
                    hoverTag(Double(hoverX / width))
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { tagSize = $0 }
                        .offset(x: origin.x, y: origin.y)
                        // Placed once it's been measured, so it never shows on the track.
                        .opacity(tagSize == .zero ? 0 : 1)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                max(1, isVertical ? proxy.size.height : proxy.size.width)
            } action: { newWidth in
                width = newWidth
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    isHovered = true
                    hoverX = min(width, max(0, along(location)))
                case .ended:
                    isHovered = false
                    hoverX = nil
                }
            }
            .gesture(isEnabled ? dragGesture : nil)
            .modifier(SliderAccessibilityModifier(accessibility: accessibility))
            // Like a native slider: focus comes from keyboard navigation, not a click.
            .focusable(isEnabled, interactions: .activate)
            .focused($isFocused)
            .onKeyPress(keys: isVertical ? [.downArrow, .upArrow] : [.leftArrow, .rightArrow]) { press in
                let step = keyStep(press.modifiers.contains(.shift))
                let forward = press.key == .rightArrow || press.key == .upArrow
                // From a click still on its way, so quick presses add up.
                let events = SliderEvent.keyStep(from: pending ?? value, by: forward ? step : -step)
                for event in events {
                    switch event {
                    case .editingChanged(let editing): onEditingChanged(editing)
                    case .changed(let next): onChange(next)
                    case .committed(let next):
                        pending = next
                        onCommit(next)
                    }
                }
                return .handled
            }
            .onChange(of: isFocused) { _, focused in
                interaction?.setControlFocused(focused, token: focusToken)
            }
            .onChange(of: value) {
                // The model caught up with the release.
                if drag == nil, let pending, abs(value - pending) < Self.catchUpTolerance {
                    self.pending = nil
                }
            }
            .task(id: pending) {
                // Or never will: show the model again rather than a stale target.
                guard pending != nil, drag == nil else { return }
                try? await Task.sleep(for: Self.pendingTimeout)
                if !Task.isCancelled, drag == nil { pending = nil }
            }
            .onAppear {
                if focusesOnAppear { isFocused = true }
            }
            .onDisappear {
                interaction?.setControlFocused(false, token: focusToken)
            }
    }

    /// How far along the track `point` is, from the low end: the leading edge,
    /// or the bottom standing on end.
    private func along(_ point: CGPoint) -> CGFloat {
        axis == .vertical ? width - point.y : point.x
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                let x = along(gesture.location)
                guard var state = drag else {
                    begin(at: along(gesture.startLocation))
                    return
                }
                guard x != state.lastX else { return }
                let fine = NSEvent.modifierFlags.contains(.option)
                let delta = Double(x - state.lastX) / Double(width) * (fine ? Self.fineScrubRate : 1)
                state.value = clamp(state.value + delta)
                state.lastX = x
                drag = state
                onChange(state.value)
            }
            .onEnded { _ in
                guard let state = drag else { return }
                pending = state.value
                drag = nil
                onCommit(state.value)
                onEditingChanged(false)
            }
    }

    private func begin(at x: CGFloat) {
        onEditingChanged(true)
        let current = pending ?? value
        let fillEnd = CGFloat(current) * width
        if abs(x - fillEnd) <= Self.grabRadius {
            // Grabbed the end of the fill: keep the offset, so nothing jumps.
            drag = DragState(value: current, lastX: x)
            return
        }
        // Jump to the click, then track from there. The next drag update lands
        // without animation and takes over from wherever the jump has reached.
        let target = clamp(Double(x / width))
        withAnimation(Motion.spatial(Motion.smooth, reduceMotion: reduceMotion)) {
            drag = DragState(value: target, lastX: x)
        }
        onChange(target)
    }

    private func clamp(_ fraction: Double) -> Double {
        min(1, max(0, fraction))
    }
}

/// Where the hover tag goes (DESIGN.md §5.10): centered on the pointer but
/// kept within the track's ends, and lifted clear of the track by `Spacing.xxs`.
nonisolated enum HoverTagPlacement {
    /// The tag's top-leading corner, from the top-leading corner of the
    /// slider's hit strip.
    static func origin(pointer: CGFloat, tagSize: CGSize, trackLength: CGFloat) -> CGPoint {
        let x = min(max(0, trackLength - tagSize.width), max(0, pointer - tagSize.width / 2))
        // From the top of the hovered track, which sits centered in the strip.
        let trackTop = (SliderMetrics.hitHeight - SliderMetrics.activeThickness) / 2
        return CGPoint(x: x, y: trackTop - Spacing.xxs - tagSize.height)
    }
}

extension HumSlider where Tag == EmptyView {
    init(
        value: Double,
        isEnabled: Bool = true,
        axis: Axis = .horizontal,
        focusesOnAppear: Bool = false,
        keyStep: @escaping (_ shift: Bool) -> Double,
        onChange: @escaping (Double) -> Void,
        onCommit: @escaping (Double) -> Void,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        accessibility: SliderAccessibility? = nil
    ) {
        self.init(
            value: value,
            isEnabled: isEnabled,
            axis: axis,
            focusesOnAppear: focusesOnAppear,
            keyStep: keyStep,
            onChange: onChange,
            onCommit: onCommit,
            onEditingChanged: onEditingChanged,
            accessibility: accessibility,
            hoverTag: { _ in EmptyView() }
        )
    }
}

/// The system focus ring's shape: the track's own capsule at its active
/// thickness, rather than the whole hit band, which reaches under the times
/// below the seek bar.
private struct TrackFocusShape: Shape {
    var axis: Axis

    func path(in rect: CGRect) -> Path {
        let inset = max(0, (SliderMetrics.hitHeight - SliderMetrics.activeThickness) / 2)
        let track = axis == .horizontal ? rect.insetBy(dx: 0, dy: inset) : rect.insetBy(dx: inset, dy: 0)
        return Capsule().path(in: track)
    }
}

/// What a slider says to VoiceOver: its name, its value in the model's own
/// units, and how VoiceOver's increment and decrement move it.
struct SliderAccessibility {
    var label: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var spokenValue: String
    var set: @MainActor (Double) -> Void
}

/// `accessibilitySlider`, on the track, when there's something to say.
private struct SliderAccessibilityModifier: ViewModifier {
    var accessibility: SliderAccessibility?

    func body(content: Content) -> some View {
        if let accessibility {
            content.accessibilitySlider(
                accessibility.label,
                value: accessibility.value,
                in: accessibility.range,
                step: accessibility.step,
                spokenValue: accessibility.spokenValue,
                set: accessibility.set
            )
        } else {
            content
        }
    }
}

extension View {
    /// Reads to VoiceOver as a system slider named `label` (DESIGN.md §9): it
    /// says "slider", speaks `spokenValue`, and speaks each change, however it's
    /// made. The drawing is unchanged. VoiceOver's increment and decrement move
    /// it by `step` within `range`, handing the new value to `set`.
    ///
    /// It replaces this view's whole subtree, so apply it to the element that
    /// takes keyboard focus, never to a container around it: VoiceOver can't
    /// follow focus onto an element the representation has replaced.
    func accessibilitySlider(
        _ label: String,
        value: Double,
        in range: ClosedRange<Double>,
        step: Double,
        spokenValue: String,
        set: @escaping @MainActor (Double) -> Void
    ) -> some View {
        accessibilityRepresentation {
            Slider(value: Binding(get: { value }, set: { set($0) }), in: range, step: step) {
                Text(label)
            }
            .accessibilityValue(spokenValue)
        }
    }
}

/// Catches two-finger scrolls over a view (the volume slider) and lets every
/// other event through to the views beneath.
struct ScrollWheelCatcher: NSViewRepresentable {
    /// Called with the vertical scroll delta in points; positive is the fingers
    /// (or the wheel) moving up, whatever the scroll-direction setting.
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .scrollWheel else { return nil }
            return super.hitTest(point)
        }

        override func scrollWheel(with event: NSEvent) {
            // Up is louder, the same as the swipe over Now's cover.
            let sample = ScrollSample(event)
            onScroll?(CGFloat(sample.isPrecise ? sample.fingerDeltaY : sample.fingerDeltaY * 8))
        }
    }
}
