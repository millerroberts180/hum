import HumCore
import SwiftUI

/// The title, with the explicit badge after it, then one secondary line,
/// "Artist — Album", at M and L (DESIGN.md §5.3). At S, or with the album off
/// or empty, the line is the artist alone. Save and More sit at the trailing
/// end of the title row. While the music plays on another device, "Playing on
/// …" is the last line.
///
/// The title may marquee on hover; the secondary line only truncates, the album
/// first (§3.3). On a track change the text slides in from the side the music
/// moved toward and fades; under Reduce Motion it only fades.
struct TrackHeader: View {
    var track: Track
    var menu: TrackMenu?
    /// The look can leave out Save and More, and the album (DESIGN.md §8).
    var showsSave = true
    var showsAlbum = true
    /// "Playing on …" under the artist. Wide's and Big Art's title row is
    /// the title over the artist and nothing more, so their stack keeps its
    /// height (§7).
    var showsDevice = true

    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Text leading sets the gap between the lines.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.xxs) {
                changing {
                    // The explicit badge follows the title inline (§5.3); the
                    // title truncates before it does.
                    HStack(spacing: Spacing.xs) {
                        MarqueeText(track.title, fillsWidth: !track.isExplicit).humText(.trackTitle)
                        if track.isExplicit {
                            ExplicitBadge()
                                .fixedSize()
                        }
                    }
                }
                .accessibilityAddTraits(.isHeader)
                HStack(spacing: Spacing.xxs) {
                    if showsSave, store.capabilities.contains(.favorite) {
                        SaveButton()
                    }
                    if showsSave, let menu {
                        MoreButton(menu: menu)
                    }
                }
            }
            // The buttons' hit targets overhang the text; pull the row in so the
            // text lines stay flush with the seek bar's edge.
            .padding(.trailing, -metrics.tertiary.outset)
            .padding(.vertical, -metrics.tertiary.outset)
            let showsAlbum = showsAlbum && metrics.sizeClass != .small && !track.album.isEmpty
            if !track.artist.isEmpty || showsAlbum {
                changing { secondaryLine(showsAlbum: showsAlbum) }
            }
            if showsDevice, metrics.sizeClass != .small {
                DeviceStatusRow()
                    .padding(.top, Spacing.xxs)
            }
        }
        .animation(reduceMotion ? Motion.crossfade : Motion.trackChangeText, value: track.id)
    }

    /// The artist keeps its room and the album truncates first
    /// (`SecondaryLineLayout`).
    private func secondaryLine(showsAlbum: Bool) -> some View {
        SecondaryLineLayout {
            if !track.artist.isEmpty {
                Text(track.artist)
                    .humText(.trackArtist)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if showsAlbum {
                if !track.artist.isEmpty {
                    Text(" — ")
                        .humText(.trackAlbum)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                Text(track.album)
                    .humText(.trackAlbum)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// A line that is replaced, not edited, when the track changes.
    private func changing(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack(alignment: .leading) {
            content()
                .id(track.id)
                .transition(transition)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let travel = Motion.trackChangeTravel * (store.trackChangeDirection == .forward ? 1 : -1)
        return .asymmetric(
            insertion: .offset(x: travel).combined(with: .opacity),
            removal: .offset(x: -travel).combined(with: .opacity)
        )
    }
}

/// "Artist — Album" on one line, on the first baseline. The album truncates
/// first, but only down to `albumFloor`, so it still ends in its ellipsis
/// (§3.3); past that the artist truncates. With the artist or the album
/// alone, it's that one line.
struct SecondaryLineLayout: Layout {
    /// Room for the album's first letters and its ellipsis.
    nonisolated static let albumFloor: CGFloat = 32

    /// The artist's and the album's widths in `available`, from what each
    /// would take and the dash between them.
    nonisolated static func widths(
        artist: CGFloat,
        dash: CGFloat,
        album: CGFloat,
        available: CGFloat
    ) -> (artist: CGFloat, album: CGFloat) {
        if artist + dash + album <= available { return (artist, album) }
        let albumWidth = min(max(min(album, albumFloor), available - artist - dash), max(0, available - dash))
        return (max(0, available - dash - albumWidth), albumWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = sizes(for: proposal, subviews)
        let tops = tops(of: subviews, sizes)
        let height = zip(tops, sizes).map { $0 + $1.height }.max() ?? 0
        return CGSize(width: sizes.reduce(0) { $0 + $1.width }, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = sizes(for: ProposedViewSize(bounds.size), subviews)
        let tops = tops(of: subviews, sizes)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: x, y: bounds.minY + tops[index]), proposal: ProposedViewSize(sizes[index]))
            x += sizes[index].width
        }
    }

    /// Each line's size: the artist, dash and album by `widths`, or the one
    /// line in what's offered.
    private func sizes(for proposal: ProposedViewSize, _ subviews: Subviews) -> [CGSize] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let available = proposal.width ?? ideal.reduce(0) { $0 + $1.width }
        guard ideal.count == 3 else {
            return subviews.map { $0.sizeThatFits(ProposedViewSize(width: available, height: proposal.height)) }
        }
        let widths = Self.widths(artist: ideal[0].width, dash: ideal[1].width, album: ideal[2].width, available: available)
        return [
            subviews[0].sizeThatFits(ProposedViewSize(width: widths.artist, height: proposal.height)),
            ideal[1],
            subviews[2].sizeThatFits(ProposedViewSize(width: widths.album, height: proposal.height)),
        ]
    }

    /// How far down each line starts so their first baselines meet.
    private func tops(of subviews: Subviews, _ sizes: [CGSize]) -> [CGFloat] {
        let baselines = zip(subviews, sizes).map { subview, size in
            subview.dimensions(in: ProposedViewSize(size))[VerticalAlignment.firstTextBaseline]
        }
        let baseline = baselines.max() ?? 0
        return baselines.map { baseline - $0 }
    }
}

#if DEBUG
struct TrackHeader_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery(backdrop: .artwork, isSquare: false) { TrackHeaderPreview() }
            PreviewGallery(isSquare: false) { TrackHeaderPreview(showsAlbum: false) }
        }
    }
}

/// The header with the demo song's menu, as Now builds it.
private struct TrackHeaderPreview: View {
    var showsAlbum = true

    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        TrackHeader(track: PreviewSource.track, menu: TrackMenu.current(store), showsAlbum: showsAlbum)
            .padding(Spacing.m)
    }
}
#endif
