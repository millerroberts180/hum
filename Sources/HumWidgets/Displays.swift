import HumCore
import SwiftUI
import WidgetKit

// A widget for Art Only, Title and Text (DESIGN.md §7.3). Each draws the song,
// or Nothing Playing, and a click anywhere outside a button shows the player.

/// A widget's size and margins. WidgetKit gives them to the widget (see
/// `DisplayView`); a render outside a widget gives its own.
struct WidgetLayout {
    var family: WidgetFamily
    var margins: EdgeInsets

    var isSmall: Bool { family == .systemSmall }
}

/// What a widget draws behind its content.
enum WidgetBackground {
    /// The system's widget background, for the material styles.
    case system
    /// The cover's own color, under a cover that fills the widget.
    case cover
}

/// The background itself, as `containerBackground` draws it.
struct WidgetBackgroundView: View {
    var kind: WidgetBackground
    var entry: HumEntry

    var body: some View {
        switch kind {
        case .system: Rectangle().fill(.fill.tertiary)
        case .cover: Color(entry.palette.background)
        }
    }
}

/// One display's widget content for an entry, at the size WidgetKit asks for.
struct DisplayView: View {
    var display: WidgetDisplay
    var entry: HumEntry
    /// Given for a render outside a widget; `nil` reads WidgetKit's.
    var layout: WidgetLayout?

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        let layout = layout ?? WidgetLayout(family: family, margins: margins)
        switch display {
        case .artOnly: ArtOnlyView(entry: entry, layout: layout)
        case .title: TitleView(entry: entry, layout: layout)
        case .text: TextView(entry: entry, layout: layout)
        }
    }

    /// What each display draws behind its song.
    static func background(_ display: WidgetDisplay) -> WidgetBackground {
        switch display {
        case .artOnly: .cover
        case .title, .text: .system
        }
    }
}

/// What every widget shares: Nothing Playing, the click that shows the player,
/// and the background.
struct WidgetFrame<Content: View>: View {
    var entry: HumEntry
    var layout: WidgetLayout
    var background: WidgetBackground
    /// Pad the content by the system's margins. Widgets whose cover runs to the
    /// edge draw their own.
    var padded = true
    @ViewBuilder var content: (WidgetSnapshot.Song) -> Content

    var body: some View {
        if let song = entry.song {
            content(song)
                .padding(padded ? layout.margins : EdgeInsets())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(HumURLAction.show.url)
                .containerBackground(for: .widget) { WidgetBackgroundView(kind: background, entry: entry) }
        } else {
            NothingPlayingView(markWidth: layout.isSmall ? 48 : 64, showsTitle: true)
                .padding(layout.margins)
                .widgetURL(HumURLAction.show.url)
                .containerBackground(for: .widget) { WidgetBackgroundView(kind: .system, entry: entry) }
        }
    }
}

// MARK: - Art Only

/// The cover, full bleed. Large adds the `controlsScrim` band with the title,
/// artist, the progress bar and the transport.
struct ArtOnlyView: View {
    var entry: HumEntry
    var layout: WidgetLayout

    var body: some View {
        WidgetFrame(entry: entry, layout: layout, background: DisplayView.background(.artOnly), padded: false) { song in
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    CoverView(cover: entry.cover)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    if !layout.isSmall {
                        controls(song)
                            .background(alignment: .bottom) {
                                WidgetScrim(side: min(proxy.size.width, proxy.size.height))
                            }
                    }
                }
            }
        }
    }

    private func controls(_ song: WidgetSnapshot.Song) -> some View {
        VStack(alignment: .leading, spacing: WidgetSpacing.s) {
            TrackText(song: song, title: WidgetType.trackTitle(layout.family), onArt: true)
            ProgressBar(playback: entry.playback, colors: .overArt)
            TransportRow(entry: entry, metrics: .large, onArt: true)
        }
        .padding(.horizontal, layout.margins.leading)
        .padding(.bottom, layout.margins.bottom * 0.75)
        .padding(.top, WidgetSpacing.s)
        .environment(\.colorScheme, .dark)
    }
}

/// DESIGN.md §3.6 `controlsScrim`, as the player draws it: black rising from 0%
/// to 55% over the lower 45% of the cover (or the controls plus 32 pt), with a
/// feather above of 16% of the cover (at least 32 pt), on a curve with no slope
/// at either end so no line shows where it starts. Increase Contrast deepens it
/// to 75%; Reduce Transparency makes it a solid 70% band. Drawn behind the
/// controls, it measures them and reaches up over the cover.
struct WidgetScrim: View {
    /// The cover's side.
    var side: CGFloat

    static let coverage = 0.45
    static let peak = 0.55
    static let increasedContrastPeak = 0.75
    static let reducedTransparencyOpacity = 0.7
    static let featherShare = 0.16
    /// `Spacing.xxl`: the least ramp above the controls, and the least feather.
    static let minimumRamp: CGFloat = 32

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            let content = proxy.size.height
            let band = Self.bandHeight(side: side, contentHeight: content)
            Group {
                if reduceTransparency {
                    Rectangle()
                        .fill(.black.opacity(Self.reducedTransparencyOpacity))
                        .frame(height: band)
                } else {
                    let height = Self.featheredHeight(side: side, contentHeight: content)
                    LinearGradient(
                        stops: Self.stops(
                            peak: contrast == .increased ? Self.increasedContrastPeak : Self.peak,
                            ramp: height > 0 ? Double(max(0, height - content) / height) : 1
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height)
                }
            }
            .frame(width: proxy.size.width, height: content, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    static func bandHeight(side: CGFloat, contentHeight: CGFloat) -> CGFloat {
        min(side, max(side * coverage, contentHeight + minimumRamp))
    }

    static func featheredHeight(side: CGFloat, contentHeight: CGFloat) -> CGFloat {
        min(side, bandHeight(side: side, contentHeight: contentHeight) + max(minimumRamp, side * featherShare))
    }

    /// A rise over the first `ramp` of the scrim that starts and ends flat (a
    /// smootherstep), then the peak; with no room to rise, the peak throughout.
    static func stops(peak: Double, ramp: Double) -> [Gradient.Stop] {
        let count = 16
        let rise = (0...count).map { step in
            let t = Double(step) / Double(count)
            let opacity = ramp > 0 ? peak * t * t * t * (t * (t * 6 - 15) + 10) : peak
            return Gradient.Stop(color: .black.opacity(opacity), location: ramp * t)
        }
        return ramp < 1 ? rise + [Gradient.Stop(color: .black.opacity(peak), location: 1)] : rise
    }
}

// MARK: - Title

/// The cover at the leading edge, the title and artist, the transport, and the
/// progress bar.
struct TitleView: View {
    var entry: HumEntry
    var layout: WidgetLayout
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WidgetFrame(entry: entry, layout: layout, background: DisplayView.background(.title)) { song in
            GeometryReader { proxy in
                HStack(spacing: WidgetSpacing.m) {
                    SquareCover(cover: entry.cover, side: proxy.size.height)
                    VStack(alignment: .leading, spacing: 0) {
                        TrackText(song: song, title: WidgetType.trackTitle(layout.family))
                        Spacer(minLength: WidgetSpacing.xs)
                        TransportRow(entry: entry, metrics: .medium)
                        ProgressBar(playback: entry.playback, colors: .forScheme(scheme))
                    }
                }
            }
        }
    }
}

// MARK: - Text

/// The title and artist, in words alone.
struct TextView: View {
    var entry: HumEntry
    var layout: WidgetLayout

    var body: some View {
        WidgetFrame(entry: entry, layout: layout, background: DisplayView.background(.text)) { song in
            VStack(alignment: .leading, spacing: WidgetSpacing.xs) {
                Text(song.title)
                    .font(.system(WidgetType.trackTitle(layout.family)))
                    .fontWeight(.semibold)
                    .lineLimit(3)
                    .widgetAccentable()
                Text(song.artist)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
