import HumCore
import SwiftUI

/// Where the song is, with scrubbing: Apple's white scrubber (DESIGN.md §5.2,
/// §5.10), with elapsed and remaining time at M and L. There's no knob; the end
/// of the fill is the playhead.
///
/// The seek is sent once, on release. Until then the elapsed label shows the time
/// under the pointer. Hovering shows a tag with the time at that spot, which is
/// how the bar alone (at S, Strip's notch) tells the time. Clicking the trailing
/// time switches it between remaining and total, and the choice is kept. A time
/// that isn't known yet reads "--:--".
struct SeekBar: View {
    /// Keep moving while the controls are hidden, for a bar that's always shown.
    var updatesAtRest = false
    /// The times either side of the bar rather than under it, so they take no
    /// height of their own.
    var timesBeside = false
    /// Whether the times show: by default at M and L only. A style that wants
    /// the bar alone (Strip's notch, Title under 300 pt) says no.
    var showsTimes: Bool?

    @Environment(NowPlayingStore.self) private var store
    @Environment(PlayerInteraction.self) private var interaction
    @Environment(\.surfaceIsActive) private var surfaceIsActive
    @Environment(\.playerMetrics) private var metrics
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @State private var scrub = SeekScrub()
    @State private var trailingFocusToken = UUID()
    @FocusState private var isTrailingFocused: Bool

    /// VoiceOver and the arrow keys move this far; ⇧ makes the keys go further.
    static let step: TimeInterval = 5
    static let largeStep: TimeInterval = 15

    var body: some View {
        let showsTimes = showsTimes ?? (metrics.sizeClass != .small)
        TimelineView(.animation(minimumInterval: interval, paused: isPaused)) { context in
            let position = scrub.fraction.map { $0 * duration } ?? store.position(at: context.date)
            Group {
                if showsTimes, timesBeside {
                    HStack(spacing: Spacing.s) {
                        time(elapsed(position), widest: elapsed(duration), alignment: .trailing)
                            .allowsHitTesting(false)
                        slider(position: position)
                        trailingButton {
                            time(trailing(position), widest: trailing(0), alignment: .leading)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        slider(position: position)
                        if showsTimes {
                            HStack {
                                Text(elapsed(position))
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                Spacer(minLength: Spacing.s)
                                trailingButton { Text(trailing(position)) }
                            }
                            .humText(.time, color: timeColor)
                            .padding(.top, -Spacing.xxs)
                        }
                    }
                }
            }
        }
    }

    private var timeColor: HumColor { .scrubberTime }

    private var trailingTime: BehaviorSettings.TrailingTime {
        settings?.behavior.trailingTime ?? .remaining
    }

    private func elapsed(_ position: TimeInterval) -> String {
        TimeFormatting.elapsed(position, duration: duration)
    }

    private func trailing(_ position: TimeInterval) -> String {
        TimeFormatting.trailing(position, duration: duration, showing: trailingTime)
    }

    /// The trailing time, which switches between remaining and total on a click.
    /// To VoiceOver it's a button of its own after the slider, named for what
    /// it does, since the slider already speaks the time. Focused, it takes
    /// Space and Return from the player's shortcuts, as the other controls do.
    private func trailingButton(@ViewBuilder label: () -> some View) -> some View {
        Button(action: toggleTrailingTime) {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isTrailingFocused)
        .onChange(of: isTrailingFocused) { _, focused in
            interaction.setControlFocused(focused, token: trailingFocusToken)
        }
        .onDisappear {
            interaction.setControlFocused(false, token: trailingFocusToken)
        }
        .accessibilityLabel(toggleTitle)
        .help(toggleTitle)
    }

    private var toggleTitle: String {
        trailingTime == .remaining ? "Show Total Time" : "Show Remaining Time"
    }

    private func toggleTrailingTime() {
        settings?.behavior.trailingTime = trailingTime.toggled
    }

    /// A time beside the bar, as wide as the longest this song can show, so the
    /// bar doesn't shift as the digits change.
    private func time(_ text: String, widest: String, alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            Text(widest).hidden()
            Text(text)
        }
        .humText(.time, color: timeColor)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func slider(position: TimeInterval) -> some View {
        HumSlider(
            value: duration > 0 ? position / duration : 0,
            isEnabled: canSeek,
            keyStep: { shift in (shift ? Self.largeStep : Self.step) / max(duration, 1) },
            onChange: { scrub.apply(.changed($0)) },
            onCommit: commit,
            onEditingChanged: { editing in
                interaction.isScrubbing = editing
                scrub.apply(.editingChanged(editing))
            },
            accessibility: SliderAccessibility(
                label: "Playback Position",
                value: position,
                range: 0...max(duration, Self.step),
                step: Self.step,
                spokenValue: TimeFormatting.spokenPosition(position, of: duration)
            ) { target in
                guard canSeek else { return }
                store.send(.seek(to: min(duration, max(0, target))))
            },
            hoverTag: { fraction in
                TimeTag(text: TimeFormatting.clock(fraction * duration))
            }
        )
    }

    private var duration: TimeInterval {
        store.clock.duration ?? store.track?.duration ?? 0
    }

    private var canSeek: Bool {
        store.capabilities.contains(.seek) && duration > 0
    }

    private var isPaused: Bool {
        scrub.isHolding || !store.isPlaying || !surfaceIsActive
            || (!interaction.isRevealed && !updatesAtRest) || !interaction.isWindowVisible
    }

    /// Fast enough for the fill to glide while revealed, and for the labels to
    /// change on the second.
    private var interval: Double {
        guard duration > 0 else { return 1 }
        let width = max(metrics.side - metrics.contentInset * 2, 1)
        return min(0.5, max(1.0 / 30, duration / width))
    }

    private func commit(_ fraction: Double) {
        guard canSeek else { return }
        store.send(.seek(to: fraction * duration))
    }
}

/// The time the seek bar shows in place of the playhead while the user
/// scrubs. The bar holds still until the edit ends, then follows the song
/// again; a key step is a whole edit of its own (`SliderEvent.keyStep`), so it
/// never leaves the bar frozen at the stepped time.
nonisolated struct SeekScrub: Equatable, Sendable {
    private(set) var fraction: Double?

    /// The bar is showing the scrub, not the song.
    var isHolding: Bool { fraction != nil }

    mutating func apply(_ event: SliderEvent) {
        switch event {
        case .changed(let value): fraction = value
        case .editingChanged(false): fraction = nil
        case .editingChanged(true), .committed: break
        }
    }
}

/// The time under the pointer, floating above the seek bar (DESIGN.md §5.10).
/// Over the cover it's on `popover` material (Liquid Glass on macOS 26); on a
/// card or a window that's already glass it's a fill, never glass on glass.
private struct TimeTag: View {
    var text: String

    @Environment(\.humColorContext) private var context

    var body: some View {
        let label = Text(text)
            .humText(.time, color: .label)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        Group {
            if context != .artwork {
                label.background(HumColor.fillTertiary, in: shape)
            } else {
                label.humMaterial(.popover, in: shape)
            }
        }
        .environment(\.humColorContext, context == .artwork ? .material : context)
    }
}

#if DEBUG
struct SeekBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery(backdrop: .artwork, isSquare: false) { bar }
            PreviewGallery(isSquare: false) { bar }
        }
    }

    static var bar: some View {
        SeekBar(updatesAtRest: true).padding(Spacing.m)
    }
}
#endif
