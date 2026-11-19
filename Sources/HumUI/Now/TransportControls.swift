import HumCore
import SwiftUI

/// Shuffle · previous · play/pause · next · repeat, centered on play/pause, on
/// every style and at every size (DESIGN.md §5.2, §5.9).
///
/// Controls the source can't do are hidden, but keep their space so play/pause
/// stays centered. Every control the look shows stays at every size: where the
/// row is wider than its room (the smallest Art Only, a card at S or M), the
/// gaps close first and then the hit targets shrink toward their backings,
/// split at the midpoints (§3.8). The glyphs and backings keep their size.
struct TransportRow: View {
    /// A bare glyph, over the cover and on material alike, as in Apple's players.
    var playFamily: PlayerButtonStyle.Family = .transport
    /// The look can leave out shuffle and repeat (DESIGN.md §8).
    var showsShuffleRepeat = true
    var fit: Fit = .standard

    /// How the row takes its width.
    enum Fit: Equatable {
        /// `transportGap` between the hit targets, centered in the width
        /// offered, and fitted to it like `fitting` where it's narrower.
        case standard
        /// Spread evenly across `width`, at least `transportGap` apart, and
        /// fitted to it like `fitting` where even that is too wide: Text's
        /// capsule (§7).
        case spread(CGFloat)
        /// Every control kept, in `width`: where the standard row is wider,
        /// the backings close up and the hit targets split the space between
        /// them at the midpoints (§3.8), down to backings that touch. Title
        /// and Strip.
        case fitting(CGFloat)

        /// The width the row must fit, if any.
        var width: CGFloat? {
            switch self {
            case .standard: nil
            case .spread(let width), .fitting(let width): width
            }
        }
    }

    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics

    var body: some View {
        if let width = fit.width {
            fitted(to: width)
        } else {
            ViewThatFits(in: .horizontal) {
                row(extent: nil)
                // Narrower than the standard row: fitted to the room offered.
                GeometryReader { proxy in
                    fitted(to: proxy.size.width)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(height: metrics.play.hit)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The row in `width`: spread across it, or closed up to fit it.
    private func fitted(to width: CGFloat) -> some View {
        let extent = extent(fitting: width)
        return row(extent: extent)
            .environment(\.transportHitExtent, extent)
            .frame(width: extent == nil && spreads ? width : nil)
            .fixedSize()
    }

    private func extent(fitting width: CGFloat) -> CGFloat? {
        Self.hitExtent(fitting: width, sizes: Self.sizes(metrics, showsModes: showsShuffleRepeat), gap: metrics.transportGap)
    }

    private var spreads: Bool {
        if case .spread = fit { true } else { false }
    }

    /// The row, its hit targets reaching `extent` past their backings where
    /// it's closed up to fit, or their standard size with nil.
    private func row(extent: CGFloat?) -> some View {
        let capabilities = store.capabilities
        let closesUp = extent != nil
        return HStack(spacing: 0) {
            if showsShuffleRepeat {
                slot(capabilities.contains(.shuffle), metrics.tertiary, extent) { ShuffleButton() }
                gap(closesUp)
            }
            slot(capabilities.contains(.skipPrevious), metrics.skip, extent) { SkipButton(direction: .backward) }
            gap(closesUp)
            slot(capabilities.contains(.playPause), metrics.play, extent) { PlayPauseButton(family: playFamily) }
            gap(closesUp)
            slot(capabilities.contains(.skipNext), metrics.skip, extent) { SkipButton(direction: .forward) }
            if showsShuffleRepeat {
                gap(closesUp)
                slot(capabilities.supportsRepeat, metrics.tertiary, extent) { RepeatButton() }
            }
        }
        .frame(maxWidth: spreads ? .infinity : nil)
    }

    /// `transportGap`, fixed (DESIGN.md §3.8), or at least that when the row
    /// spreads. A row closed up to fit its room has none: the hit targets
    /// meet at the midpoints instead.
    @ViewBuilder
    private func gap(_ closesUp: Bool) -> some View {
        if closesUp {
            EmptyView()
        } else if spreads {
            Spacer(minLength: metrics.transportGap)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: metrics.transportGap, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// A control, or where the source can't do it, its space: as wide as the
    /// control would be.
    @ViewBuilder
    private func slot(
        _ isAvailable: Bool,
        _ size: ControlSizing,
        _ extent: CGFloat?,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if isAvailable {
            content()
        } else {
            Color.clear
                .frame(width: extent.map { size.backing + $0 * 2 } ?? size.hit, height: size.hit)
                .accessibilityHidden(true)
        }
    }

    /// The row's controls, in order.
    nonisolated static func sizes(_ metrics: PlayerMetrics, showsModes: Bool) -> [ControlSizing] {
        let core = [metrics.skip, metrics.play, metrics.skip]
        return showsModes ? [metrics.tertiary] + core + [metrics.tertiary] : core
    }

    /// How far each hit target reaches past its backing when the row must fit
    /// `width`, or nil when the standard row (`sizes`' hit targets with `gap`
    /// between them) already fits. Never below zero: the backings touch.
    nonisolated static func hitExtent(fitting width: CGFloat, sizes: [ControlSizing], gap: CGFloat) -> CGFloat? {
        guard !sizes.isEmpty else { return nil }
        let standard = sizes.reduce(0) { $0 + $1.hit } + gap * CGFloat(sizes.count - 1)
        guard width < standard else { return nil }
        let backings = sizes.reduce(0) { $0 + $1.backing }
        return max(0, (width - backings) / CGFloat(sizes.count * 2))
    }
}

private nonisolated struct TransportHitExtentKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// How far a glyph button's hit target reaches past its backing on each
    /// side, for a transport row fitted to a width (`TransportRow.Fit`). Nil
    /// keeps each button's own outset.
    nonisolated var transportHitExtent: CGFloat? {
        get { self[TransportHitExtentKey.self] }
        set { self[TransportHitExtentKey.self] = newValue }
    }
}

struct PlayPauseButton: View {
    var family: PlayerButtonStyle.Family

    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics

    var body: some View {
        let playing = store.isPlaying
        let size = metrics.play
        Button {
            store.send(.togglePlayPause)
        } label: {
            Image(systemName: playing ? HumIcon.pause : HumIcon.play)
                .contentTransition(.symbolEffect(.replace))
                // The triangle looks centered only when nudged toward its point.
                .offset(x: playing ? 0 : size.glyph * 0.06)
        }
        .buttonStyle(PlayerButtonStyle(family, size: size, isWaiting: store.isLaunching))
        .accessibilityLabel(playing ? "Pause" : "Play")
        .help(playing ? "Pause (Space)" : "Play (Space)")
    }
}

struct SkipButton: View {
    enum Direction {
        case backward
        case forward
    }

    var direction: Direction

    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics
    @State private var commits = 0

    var body: some View {
        let forward = direction == .forward
        Button {
            commits += 1
            store.send(forward ? .next : .previous)
        } label: {
            Image(systemName: forward ? HumIcon.next : HumIcon.previous)
                .commitBounce(value: commits)
        }
        .buttonStyle(PlayerButtonStyle(
            .transport,
            size: metrics.skip,
            isWaiting: store.isLaunching,
            hold: store.capabilities.contains(.scan) ? scan(forward: forward) : nil
        ))
        .accessibilityLabel(forward ? "Next Track" : "Previous Track")
        .accessibilityHint(store.capabilities.contains(.scan) ? "Hold to scan." : "")
        .help(forward ? "Next Track (⌘→)" : "Previous Track (⌘←)")
    }

    /// Holding scans through the song until release.
    private func scan(forward: Bool) -> PlayerButtonStyle.Hold {
        PlayerButtonStyle.Hold(
            begin: { store.send(.beginScan(forward: forward)) },
            end: { store.send(.endScan) }
        )
    }
}

struct ShuffleButton: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics

    var body: some View {
        let isOn = store.snapshot.shuffle ?? false
        Button {
            store.send(.setShuffle(!isOn))
        } label: {
            Image(systemName: HumIcon.shuffle)
        }
        .buttonStyle(PlayerButtonStyle(.toggle, size: metrics.tertiary, isOn: isOn))
        .accessibilityLabel("Shuffle")
        // A toggle button, on when selected (§9).
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
        .help(isOn ? "Turn Shuffle Off" : "Turn Shuffle On")
    }
}

/// Off → all → one, skipping modes the source lacks.
struct RepeatButton: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(\.playerMetrics) private var metrics
    @State private var isExplainingOne = false

    var body: some View {
        let mode = store.snapshot.repeatMode ?? .off
        let next = store.capabilities.nextRepeatMode(after: mode)
        Button {
            guard let next else { return }
            store.send(.setRepeat(next))
            // The first One for an app that can't show it says that Hum
            // repeats the song itself (§5.2).
            if let settings, RepeatOneNote.shows(
                choosing: next, capabilities: store.capabilities, alreadyShown: settings.playback.repeatOneNoteShown
            ) {
                settings.playback.repeatOneNoteShown = true
                isExplainingOne = true
            }
        } label: {
            // A quick cross-fade with the toggle's color and dot, not the
            // symbol's slower replace (§13.34).
            Image(systemName: mode == .one ? HumIcon.repeatOne : HumIcon.repeatAll)
                .contentTransition(.opacity)
        }
        .buttonStyle(PlayerButtonStyle(.toggle, size: metrics.tertiary, isOn: mode != .off, glyphState: mode))
        .accessibilityLabel("Repeat")
        // A toggle button whose three states are its value.
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Self.spoken(mode))
        .help("Repeat: \(Self.title(mode))")
        .repeatOneNote(isOpen: $isExplainingOne)
    }

    /// VoiceOver's value, read after the label: "Repeat, one song" (§5.2).
    nonisolated static func spoken(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "off"
        case .all: "all"
        case .one: "one song"
        }
    }

    /// The mode in the tooltip, as the menus name it.
    nonisolated static func title(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "Off"
        case .all: "All"
        case .one: "One Song"
        }
    }
}

/// Favorite, for sources that can save the playing song (DESIGN.md §1.3). The filled glyph in the accent is the on state; there's no
/// capsule.
struct SaveButton: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics
    @State private var saves = 0

    var body: some View {
        let isSaved = store.snapshot.isFavorite ?? false
        Button {
            if !isSaved { saves += 1 }
            store.send(.setFavorite(!isSaved))
        } label: {
            Image(systemName: SaveVocabulary.symbol(isSaved: isSaved))
                .contentTransition(.symbolEffect(.replace))
                .commitBounce(value: saves)
        }
        .buttonStyle(PlayerButtonStyle(.toggle, size: metrics.tertiary, isOn: isSaved, showsOnBacking: false))
        .accessibilityLabel(SaveVocabulary.title(isSaved: false))
        .accessibilityAddTraits(isSaved ? [.isToggle, .isSelected] : .isToggle)
        .help("\(SaveVocabulary.title(isSaved: isSaved)) (⌥⇧B)")
    }
}

/// Opens the same menu as right-clicking the player: the song's items, then
/// the player section (§4.4).
struct MoreButton: View {
    var menu: TrackMenu

    @Environment(NowPlayingStore.self) private var store
    @Environment(SettingsStore.self) private var settings: SettingsStore?
    @Environment(PlayerSizing.self) private var sizing: PlayerSizing?
    @Environment(SurfacePager.self) private var pager: SurfacePager?
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.playerActions) private var actions
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            let store = store
            let nsMenu = menu.nsMenu { TrackMenuPerformer.perform($0, store: store) }
            let player = PlayerMenu.current(settings: settings, sizing: sizing, pager: pager)
            let commands = PlayerMenuCommands(settings: settings, sizing: sizing, actions: actions)
            player.nsItems(commands, startsWithSeparator: !menu.isEmpty).forEach(nsMenu.addItem)
            actions.popUpMenu(nsMenu, frame)
        } label: {
            Image(systemName: HumIcon.more)
        }
        .buttonStyle(PlayerButtonStyle(.icon, size: metrics.tertiary))
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newFrame in
            frame = newFrame
        }
        .accessibilityLabel("More")
        .help("More")
    }
}

#if DEBUG
struct TransportRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery(backdrop: .artwork, isSquare: false) {
                TransportRow().padding(Spacing.m)
            }
            PreviewGallery(backdrop: .artwork, isSquare: false, isPlaying: false) {
                TransportRow(showsShuffleRepeat: false).padding(Spacing.m)
            }
        }
    }
}
#endif
