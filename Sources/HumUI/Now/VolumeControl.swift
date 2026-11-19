import HumCore
import SwiftUI

/// The source app's volume, at L: a speaker, the track, and a louder speaker.
/// The store coalesces changes while dragging. Two-finger scrolling over it
/// adjusts the volume too.
struct VolumeControl: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics
    @State private var isHovered = false

    static let step = 0.05
    /// Points of scrolling per full sweep of the slider.
    static let scrollSpan: CGFloat = 400
    /// The speakers are a size below the tertiary glyphs, so the track leads.
    static let speakerGlyph: CGFloat = 11
    /// Each speaker's slot, as wide as its widest symbol, so the track doesn't
    /// shift when the quiet speaker turns to muted.
    static let quietSpeakerWidth: CGFloat = 16
    static let loudSpeakerWidth: CGFloat = 20

    /// VoiceOver's value: "40 percent".
    nonisolated static func spoken(_ volume: Double) -> String {
        "\(Int((volume * 100).rounded())) percent"
    }

    /// The volume slider, as VoiceOver hears it, wherever it's shown.
    static func accessibility(_ volume: Double, set: @escaping @MainActor (Double) -> Void) -> SliderAccessibility {
        SliderAccessibility(label: "Volume", value: volume, range: 0...1, step: step, spokenValue: spoken(volume), set: set)
    }

    var body: some View {
        let volume = store.snapshot.volume ?? 0.5
        HStack(spacing: Spacing.s) {
            // The speakers are decoration: the slider between them is the control.
            Image(systemName: volume <= 0 ? HumIcon.volumeMuted : HumIcon.volumeLow)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.quietSpeakerWidth)
                .accessibilityHidden(true)
            HumSlider(
                value: volume,
                keyStep: { _ in Self.step },
                onChange: { store.setVolume($0) },
                onCommit: { store.setVolume($0) },
                accessibility: Self.accessibility(volume) { store.setVolume($0) }
            )
            Image(systemName: HumIcon.volumeHigh)
                .frame(width: Self.loudSpeakerWidth)
                .accessibilityHidden(true)
        }
        .font(.system(size: Self.speakerGlyph, weight: .semibold))
        .foregroundStyle(isHovered ? HumColor.secondaryLabel : HumColor.tertiaryLabel)
        .animation(Motion.snappy, value: isHovered)
        .overlay {
            ScrollWheelCatcher { delta in
                store.setVolume(volume + Double(delta / Self.scrollSpan))
            }
            .accessibilityHidden(true)
        }
        .onHover { isHovered = $0 }
        .help("Volume (⌘↑ / ⌘↓)")
    }
}

/// At S the volume is a speaker that opens a vertical slider in a system
/// popover pointing at it (DESIGN.md §5.2, §5.11). The popover is attached by
/// `volumePopover(isOpen:)` on a view outside the artwork's color context, so
/// it takes the window's real appearance.
///
/// To VoiceOver it's a plain button, so one press (VO-Space) opens the
/// popover; the slider inside takes the VoiceOver cursor and the arrow keys,
/// and Escape hands both back here.
struct VolumeButton: View {
    @Binding var isOpen: Bool

    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.volumeFocusReturn) private var focusReturn
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        let volume = store.snapshot.volume ?? 0.5
        Button {
            isOpen.toggle()
        } label: {
            // The waves fill with the level; only muting swaps the symbol.
            Image(systemName: volume <= 0 ? HumIcon.volumeMuted : HumIcon.volumeHigh, variableValue: volume)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PlayerButtonStyle(.icon, size: metrics.tertiary, isOn: isOpen, focusRequest: focusReturn))
        .anchorPreference(key: VolumeTriggerKey.self, value: .bounds) { $0 }
        .accessibilityLabel("Volume")
        .accessibilityValue(VolumeControl.spoken(volume))
        .accessibilityHint(isOpen ? "Closes the volume slider." : "Opens the volume slider.")
        // Not adjustable here: an adjustable element reads as a slider, and
        // VoiceOver's press would no longer open the popover.
        .accessibilityAction { isOpen.toggle() }
        .accessibilityFocused($isAccessibilityFocused)
        .onChange(of: focusReturn) { isAccessibilityFocused = true }
        .help("Volume (⌘↑ / ⌘↓)")
    }
}

private nonisolated struct VolumeFocusReturnKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Goes up each time the S volume popover closes from the keyboard, so the
    /// button that opened it takes focus back.
    nonisolated var volumeFocusReturn: Int {
        get { self[VolumeFocusReturnKey.self] }
        set { self[VolumeFocusReturnKey.self] = newValue }
    }
}

private nonisolated struct VolumeTriggerKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Presents the S volume popover from the `VolumeButton` inside this view
    /// while `isOpen`.
    func volumePopover(isOpen: Binding<Bool>) -> some View {
        modifier(VolumePopoverHost(isOpen: isOpen))
    }
}

private struct VolumePopoverHost: ViewModifier {
    @Binding var isOpen: Bool

    @Environment(PlayerInteraction.self) private var interaction: PlayerInteraction?
    @State private var holdToken = UUID()
    @State private var focusReturn = 0

    /// The slider's room inside the popover.
    static let size = CGSize(width: 40, height: 120)

    func body(content: Content) -> some View {
        content
            .environment(\.volumeFocusReturn, focusReturn)
            .overlayPreferenceValue(VolumeTriggerKey.self) { anchor in
                GeometryReader { proxy in
                    Color.clear
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .popover(
                            isPresented: $isOpen,
                            attachmentAnchor: .rect(.rect(anchor.map { proxy[$0] } ?? .zero)),
                            arrowEdge: .top
                        ) {
                            VerticalVolumeSlider {
                                isOpen = false
                                focusReturn += 1
                            }
                            .padding(.vertical, Spacing.m)
                            .frame(width: Self.size.width, height: Self.size.height)
                            .environment(\.humColorContext, .material)
                        }
                }
            }
            .onChange(of: isOpen) { _, open in
                // Keep the controls up while the slider is open: it's a window
                // of its own, so pointing at it leaves the player.
                interaction?.setControlFocused(open, token: holdToken)
                interaction?.setPopoverOpen(open, token: holdToken)
            }
            .onChange(of: interaction?.popoverCloseRequestCount) {
                // Escape reached the player first: close, and focus goes back
                // to the button.
                guard isOpen else { return }
                isOpen = false
                focusReturn += 1
            }
            .onChange(of: interaction?.isPresented) { _, presented in
                // Hiding the player puts the slider away, so it isn't waiting
                // there next time.
                if presented == false { isOpen = false }
            }
            .onDisappear {
                interaction?.setControlFocused(false, token: holdToken)
                interaction?.setPopoverOpen(false, token: holdToken)
            }
    }
}

/// The popover's slider: `HumSlider` standing on end, louder at the top, so it
/// clicks, drags, scrubs with ⌥, and animates as the seek bar does. Scroll
/// over it, or use ↑ and ↓; Esc closes it.
private struct VerticalVolumeSlider: View {
    var close: () -> Void

    @Environment(NowPlayingStore.self) private var store
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        let volume = store.snapshot.volume ?? 0.5
        VStack(spacing: Spacing.s) {
            HumSlider(
                value: volume,
                axis: .vertical,
                focusesOnAppear: true,
                keyStep: { _ in VolumeControl.step },
                onChange: { store.setVolume($0) },
                onCommit: { store.setVolume($0) },
                accessibility: VolumeControl.accessibility(volume) { store.setVolume($0) }
            )
            .accessibilityAction(.escape) { close() }
            .accessibilityFocused($isAccessibilityFocused)
            Image(systemName: volume <= 0 ? HumIcon.volumeMuted : HumIcon.volumeLow)
                .font(.system(size: VolumeControl.speakerGlyph, weight: .semibold))
                .foregroundStyle(HumColor.secondaryLabel)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        }
        .overlay {
            ScrollWheelCatcher { delta in
                store.setVolume(volume + Double(delta / VolumeControl.scrollSpan))
            }
            .accessibilityHidden(true)
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onExitCommand(perform: close)
        .onAppear {
            isAccessibilityFocused = true
        }
    }
}

#if DEBUG
struct VolumeControl_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // The slider at L; the button that opens it at S and M.
            PreviewGallery(cases: [.largeLight, .largeDark], backdrop: .artwork, isSquare: false) {
                VolumeControl().padding(Spacing.l)
            }
            PreviewGallery(cases: [.smallLight, .smallDark], backdrop: .artwork, isSquare: false) {
                VolumeButton(isOpen: .constant(false)).padding(Spacing.s)
            }
        }
    }
}
#endif
