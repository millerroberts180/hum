import HumCore
import SwiftUI

/// The session so far: its chapter name, duration · songs · artists, and a trail
/// of 20-pt covers from the oldest album at the leading edge to the one playing
/// now (DESIGN.md §5.7). The trail's end marks the current track; no ring or
/// other marker is drawn. The trail grows as the session goes on; when it runs out
/// of room the oldest covers slide off the leading edge. A cover from Spotify is
/// never cut off or faded (§3.6.1), so a trail holding one keeps only the newest
/// covers that fit whole. Each cover has its album's menu (§4.4).
struct SessionRibbon: View {
    /// Leave out the chapter name, for tight spaces.
    var showsChapter = true

    @Environment(ListeningHistory.self) private var history: ListeningHistory?
    @Environment(LibraryStore.self) private var library: LibraryStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trailWidth: CGFloat = 0

    /// A cover on the trail (DESIGN.md §5.7).
    static let thumbnail: CGFloat = 20
    static let thumbnailGap = Spacing.xs

    var body: some View {
        if let session = history?.echo.session {
            content(session)
        } else {
            emptyState
        }
    }

    private func content(_ session: ListeningSession) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if showsChapter {
                Text(session.chapterName)
                    .humText(.cardTitle)
                    .lineLimit(1)
            }
            stats(session)
            trail(session)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsChapter ? session.chapterName : "This session")
        .accessibilityValue(spokenValue(session))
    }

    private func stats(_ session: ListeningSession) -> some View {
        HStack(spacing: Spacing.xs) {
            stat(HistoryFormat.sessionLength(session.listened, isOngoing: session.isOngoing))
            separator
            stat(HistoryFormat.count(session.songCount, "song"))
            separator
            stat(HistoryFormat.count(session.artistCount, "artist"))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private func stat(_ text: String) -> some View {
        Text(text)
            .humText(.statLabel, color: .secondaryLabel)
            .monospacedDigit()
    }

    private var separator: some View {
        Text("·")
            .humText(.statLabel, color: .tertiaryLabel)
    }

    private func trail(_ session: ListeningSession) -> some View {
        let stops = session.trail
        return TrailStack(gap: Self.thumbnailGap) {
            ForEach(stops) { stop in
                HistoryArtwork(key: stop.artworkKey, side: Self.thumbnail)
                    .help(stop.album + " — " + stop.artist)
                    .contextMenu { TrailStopMenu(stop: stop, library: library) }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.thumbnail)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trailWidth = $0 }
        .clipped()
        .mask {
            if TrailStack.overflows(count: stops.count, width: trailWidth, side: Self.thumbnail, gap: Self.thumbnailGap) {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Spacing.l)
                    Rectangle()
                }
            } else {
                Rectangle()
            }
        }
        .animation(Motion.spatial(Motion.smooth, reduceMotion: reduceMotion), value: stops.count)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(showsChapter ? "No Session Yet" : "This Session")
                .humText(.cardTitle)
            Text(history?.isCollecting == false
                ? "Listening history is paused."
                : "The trail starts with the next song you play.")
                .humText(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func spokenValue(_ session: ListeningSession) -> String {
        var parts = [
            session.listened < 60
                ? HistoryFormat.sessionLength(session.listened, isOngoing: session.isOngoing)
                : TimeFormatting.spoken(session.listened),
            HistoryFormat.count(session.songCount, "song"),
            HistoryFormat.count(session.artistCount, "artist"),
        ]
        let albums = session.trail.suffix(5).map(\.album)
        if !albums.isEmpty {
            parts.append("Recent albums: " + albums.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}

/// Lays covers out in a row from the leading edge. When they don't fit, the row
/// ends at the trailing edge instead and the oldest fall off the leading side,
/// under a short fade. With `wholeOnly`, nothing is cut off: the newest covers
/// that fit whole start the row, and the rest wait outside the clip.
struct TrailStack: Layout {
    var gap: CGFloat
    var wholeOnly = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).max() ?? 0
        let natural = sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, sizes.count - 1))
        return CGSize(width: proposal.width ?? natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, sizes.count - 1))
        if wholeOnly, natural > bounds.width {
            placeWhole(in: bounds, subviews: subviews, sizes: sizes)
            return
        }
        var x = natural > bounds.width ? bounds.maxX - natural : bounds.minX
        for (subview, size) in zip(subviews, sizes) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
            x += size.width + gap
        }
    }

    /// The newest covers that fit whole from the leading edge, and the older ones
    /// a full width past it, so no part of them reaches the clip.
    private func placeWhole(in bounds: CGRect, subviews: Subviews, sizes: [CGSize]) {
        let hidden = sizes.count - Self.wholeCount(sizes.map(\.width), width: bounds.width, gap: gap)
        var x = bounds.minX - bounds.width - sizes.prefix(hidden).reduce(0) { $0 + $1.width + gap }
        for (index, (subview, size)) in zip(subviews, sizes).enumerated() {
            if index == hidden { x = bounds.minX }
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
            x += size.width + gap
        }
    }
}

extension TrailStack {
    /// Whether `count` covers overflow `width`.
    nonisolated static func overflows(count: Int, width: CGFloat, side: CGFloat, gap: CGFloat) -> Bool {
        CGFloat(count) * side + CGFloat(max(0, count - 1)) * gap > width
    }

    /// How many of the newest covers, the last of `widths`, fit `width` whole.
    nonisolated static func wholeCount(_ widths: [CGFloat], width: CGFloat, gap: CGFloat) -> Int {
        var used: CGFloat = 0
        var count = 0
        for cover in widths.reversed() {
            used += (count == 0 ? 0 : gap) + cover
            guard used <= width else { break }
            count += 1
        }
        return count
    }
}

#if DEBUG
struct SessionRibbon_Previews: PreviewProvider {
    static var previews: some View {
        PreviewGallery(isSquare: false) {
            VStack(spacing: Spacing.s) {
                SessionRibbon()
                SessionCard(insight: .previewSession, isExpanded: .constant(true))
            }
            .padding(Spacing.m)
            .environment(PreviewHistory.shared)
        }
    }
}
#endif
