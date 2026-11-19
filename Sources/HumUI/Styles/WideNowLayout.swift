import HumCore
import SwiftUI

/// The Wide style (DESIGN.md §7): a landscape card, half as tall as it is
/// wide, on `glassCard` at the window level with its 1-pt edge, as Title.
///
/// The cover is a square at the leading edge, inset `Spacing.m` on three
/// sides, with nothing on it. The column to its right, `Spacing.m` from the
/// cover and from the trailing edge, is the card's stack (`CardStack`),
/// centered on the card's height. Everything always shows. There's no page
/// indicator, and History and Status grow the window to a square (§7.2).
struct WideNowLayout: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.surfaceIsActive) private var surfaceIsActive

    /// From the card's edges to the cover, between the cover and the column,
    /// and from the column to the trailing edge.
    nonisolated static let inset = Spacing.m

    var body: some View {
        let status = NowStatus(store)
        let track = status == .ready ? store.track : nil
        let menu = TrackMenu.current(store)
        GeometryReader { proxy in
            let cover = Self.coverSide(height: proxy.size.height)
            let column = Self.columnWidth(size: proxy.size)
            HStack(spacing: Self.inset) {
                ArtworkView(artwork: track == nil ? nil : store.artwork)
                    .frame(width: cover, height: cover)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .volumeSwipeArea()
                    // A HUD goes on the cover, clear of the controls (§5.8).
                    .background {
                        if surfaceIsActive {
                            Color.clear.hudBand()
                        }
                    }
                    .accessibilityHidden(true)
                Group {
                    if let track {
                        CardStack(track: track, menu: menu, width: column)
                    } else {
                        // The column is short whatever the width: the
                        // compact state, as at S.
                        NowEmptyState(status: status, drawsBackdrop: false)
                            .environment(\.playerMetrics, PlayerMetrics(side: PlayerMetrics.minimumSide))
                    }
                }
                .frame(width: column)
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, Self.inset)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .barMetrics(playsAtSecondarySize: true)
        .windowMaterial(.glassCard)
        .environment(\.humColorContext, .material)
        .accessibilityElement(children: .contain)
        .nowContextMenu(menu)
    }

    /// The cover's side in a card `height` tall: the height less the insets.
    nonisolated static func coverSide(height: CGFloat) -> CGFloat {
        max(0, height - 2 * inset)
    }

    /// The column beside the cover in a card of `size`.
    nonisolated static func columnWidth(size: CGSize) -> CGFloat {
        max(0, size.width - inset - coverSide(height: size.height) - inset - inset)
    }
}

#if DEBUG
struct WideNowLayout_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery(style: .wide) { WideNowLayout() }
            PreviewGallery(isPlaying: false, style: .wide) { WideNowLayout() }
        }
    }
}
#endif
