import HumCore
import SwiftUI

/// What Title, Text and Strip share (DESIGN.md §7): they're bars, so their
/// width decides what fits while their height sizes their glyphs.
extension View {
    /// The bar's own metrics: its width as the side, so the size class (the
    /// seek bar's times, the type) follows the width, with the controls sized
    /// for a short bar (S). `playsAtSecondarySize` sets play/pause at the
    /// previous/next size, as Title's and Text's rows have it. Wide's and Big
    /// Art's cards take it too: their type follows their width and their
    /// controls stay one size.
    func barMetrics(playsAtSecondarySize: Bool = false) -> some View {
        modifier(BarMetrics(playsAtSecondarySize: playsAtSecondarySize))
    }
}

private struct BarMetrics: ViewModifier {
    var playsAtSecondarySize: Bool

    @Environment(\.playerMetrics) private var metrics
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        // Measured on a frame that takes the window's width whatever the
        // content asks for: a row fitted to a first, wrong width would
        // otherwise hold the content at that width.
        Color.clear
            .overlay {
                content
                    .environment(\.playerMetrics, Self.metrics(
                        width: width ?? metrics.side,
                        cornerRadiusScale: metrics.cornerRadiusScale,
                        playsAtSecondarySize: playsAtSecondarySize
                    ))
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }

    nonisolated static func metrics(width: CGFloat, cornerRadiusScale: CGFloat, playsAtSecondarySize: Bool) -> PlayerMetrics {
        PlayerMetrics(
            side: width,
            cornerRadiusScale: cornerRadiusScale,
            controlClass: .small,
            playsAtSecondarySize: playsAtSecondarySize
        )
    }
}

nonisolated enum BarText {
    /// The help tag and VoiceOver label of a bar: "Title — Artist", or the
    /// title alone (§7).
    static func titleAndArtist(_ track: Track) -> String {
        track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)"
    }
}

/// A bar without a track says why in the title's place, in one line: "Nothing
/// Playing" (§6.2). There's no room for a button.
struct BarStatus: View {
    var status: NowStatus
    var titleRole: HumType = .trackTitle
    var showsMessage = false

    var body: some View {
        let content = EmptyStateContent(status)
        VStack(alignment: .leading, spacing: 0) {
            Text(content.title)
                .humText(titleRole)
                .lineLimit(1)
                .truncationMode(.tail)
            if showsMessage, let message = content.message {
                Text(message)
                    .humText(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Title over artist, one line each, tail-truncated, crossfading on a track
/// change (Title and Text).
struct BarTitleStack: View {
    var track: Track
    var titleRole: HumType
    var artistRole: HumType

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(track.title)
                .humText(titleRole)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
            if !track.artist.isEmpty {
                Text(track.artist)
                    .humText(artistRole)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(track.id)
        .transition(.opacity)
        .animation(reduceMotion ? Motion.crossfade : Motion.trackChangeText, value: track.id)
    }
}
