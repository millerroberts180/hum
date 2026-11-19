import HumCore
import SwiftUI
import WidgetKit

// MARK: - Cover

/// The cover, filling its frame, or the missing-artwork tile (DESIGN.md §3.4).
struct CoverView: View {
    var cover: HumEntry.Cover
    var cornerRadius: CGFloat = 0

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch cover {
        case .image(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .aspectRatio(contentMode: .fill)
        case .demo:
            DemoCover()
        case .none:
            // A flat `fillTertiary` tile with `music.note` at 0.55 of its side.
            GeometryReader { proxy in
                ZStack {
                    Rectangle().fill(.fill.tertiary)
                    Image(systemName: "music.note")
                        .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.55 * 0.6, weight: .regular))
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }
}

/// A square cover of a fixed side with artwork corners.
struct SquareCover: View {
    var cover: HumEntry.Cover
    var side: CGFloat
    var cornerRadius = WidgetRadius.artMedium

    var body: some View {
        CoverView(cover: cover, cornerRadius: cornerRadius)
            .frame(width: side, height: side)
    }
}

// MARK: - Text

/// Title over artist (DESIGN.md §5.3 `TrackHeader`), one line each.
struct TrackText: View {
    var song: WidgetSnapshot.Song
    /// The title's size (`WidgetType`); the artist line is the same in every
    /// widget.
    var title: Font.TextStyle
    /// Over the cover's scrim: white roles (§3.5.2), one weight heavier.
    var onArt = false
    var showsAlbum = false
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: WidgetSpacing.xxs) {
            Text(song.title)
                .font(.system(title))
                .fontWeight(onArt ? .bold : .semibold)
                .foregroundStyle(onArt ? AnyShapeStyle(OnArt.label) : AnyShapeStyle(.primary))
                .widgetAccentable()
            Text(secondLine)
                .font(.body)
                .fontWeight(onArt ? .medium : .regular)
                .foregroundStyle(onArt ? AnyShapeStyle(OnArt.secondary) : AnyShapeStyle(.secondary))
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// "Artist — Album" where the album shows, the artist alone otherwise.
    private var secondLine: String {
        showsAlbum && !song.album.isEmpty ? song.artist + " — " + song.album : song.artist
    }
}

// MARK: - Progress

/// The white seek bar (DESIGN.md §5.2), as a widget can show it: it runs on its
/// own while playing and stands still while paused.
struct ProgressBar: View {
    var playback: WidgetPlayback
    var colors: SeekColors

    var body: some View {
        Group {
            switch playback {
            case .playing(let start, let end?, _):
                ProgressView(timerInterval: start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            case .paused(let position, let duration?):
                ProgressView(value: min(position, duration), total: duration)
            default:
                ProgressView(value: 0, total: 1)
            }
        }
        .progressViewStyle(.linear)
        .labelsHidden()
        .tint(colors.fill)
        .widgetAccentable(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
    }
}

// MARK: - Transport

/// shuffle · previous · play/pause · next · repeat, as links to Hum (DESIGN.md
/// §7.3), each hidden where the source can't do it. Shuffle and repeat show
/// their active state: the accent and a 4-pt dot under the glyph (§5.2).
struct TransportRow: View {
    var entry: HumEntry
    var metrics: TransportMetrics
    /// Over the cover or its scrim, where glyphs take white and a soft shadow.
    var onArt = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            if entry.snapshot.supports(.shuffle) {
                toggle(.shuffle, symbol: "shuffle", isOn: entry.snapshot.shuffle == true, label: "Shuffle")
            }
            if entry.snapshot.supports(.previous) {
                button(.previous, symbol: "backward.fill", size: metrics.skip, hit: metrics.skipHit, label: "Previous Track")
            }
            if entry.snapshot.supports(.playPause) {
                let playing = entry.playback.isPlaying
                button(
                    .playPause,
                    symbol: playing ? "pause.fill" : "play.fill",
                    size: metrics.play,
                    hit: metrics.playHit,
                    label: playing ? "Pause" : "Play",
                    // The triangle looks centered only when nudged toward its point (§3.8).
                    nudge: playing ? 0 : metrics.play * 0.06
                )
            }
            if entry.snapshot.supports(.next) {
                button(.next, symbol: "forward.fill", size: metrics.skip, hit: metrics.skipHit, label: "Next Track")
            }
            if entry.snapshot.supports(.repeat) {
                let mode = entry.snapshot.repeatMode ?? .off
                toggle(.repeat, symbol: mode == .one ? "repeat.1" : "repeat", isOn: mode != .off, label: "Repeat")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var glyphColor: Color {
        onArt ? OnArt.label : .primary
    }

    private var accent: Color {
        onArt || colorScheme == .dark ? entry.accentOnDark : entry.accentOnLight
    }

    private func button(
        _ action: HumURLAction,
        symbol: String,
        size: CGFloat,
        hit: CGFloat,
        label: String,
        nudge: CGFloat = 0
    ) -> some View {
        Link(destination: action.url) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .offset(x: nudge)
                .foregroundStyle(glyphColor)
                .modifier(OnArtShadow(isOn: onArt))
                .widgetAccentable()
                .frame(maxWidth: .infinity, minHeight: hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: hit * 0.75, maxWidth: hit)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
    }

    private func toggle(_ action: HumURLAction, symbol: String, isOn: Bool, label: String) -> some View {
        Link(destination: action.url) {
            Image(systemName: symbol)
                .font(.system(size: metrics.tertiary, weight: .semibold))
                .foregroundStyle(isOn ? accent : (onArt ? OnArt.secondary : Color.secondary))
                .modifier(OnArtShadow(isOn: onArt))
                .widgetAccentable(isOn)
                // The dot sits under the glyph without moving it off center.
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(accent)
                        .frame(width: 4, height: 4)
                        .widgetAccentable()
                        .offset(y: metrics.tertiary * 0.5 + 4)
                        .opacity(isOn ? 1 : 0)
                }
                .frame(maxWidth: .infinity, minHeight: metrics.tertiaryHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: metrics.tertiaryHit * 0.75, maxWidth: metrics.tertiaryHit)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
        .accessibilityValue(value(for: action, isOn: isOn))
    }

    private func value(for action: HumURLAction, isOn: Bool) -> String {
        guard action == .repeat else { return isOn ? "On" : "Off" }
        switch entry.snapshot.repeatMode ?? .off {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One song"
        }
    }
}

private struct OnArtShadow: ViewModifier {
    var isOn: Bool

    func body(content: Content) -> some View {
        if isOn { content.glyphOnArtShadow() } else { content }
    }
}

// MARK: - Nothing Playing

/// Hum's mark and "Nothing Playing" (DESIGN.md §7.3).
struct NothingPlayingView: View {
    var markWidth: CGFloat = 56
    var showsTitle = true

    var body: some View {
        VStack(spacing: WidgetSpacing.s) {
            HumMarkView(width: markWidth)
                .foregroundStyle(.secondary)
                .widgetAccentable()
            if showsTitle {
                Text("Nothing Playing")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nothing Playing")
    }
}
