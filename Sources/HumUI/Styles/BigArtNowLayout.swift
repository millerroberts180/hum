import HumCore
import SwiftUI

/// The Big Art style (DESIGN.md §7): a portrait card on `glassCard` at the
/// window level with its 1-pt edge, as Title.
///
/// The cover is a square inset `Spacing.m` from the top and sides, with
/// nothing on it. Under it, `Spacing.m` from it and from the bottom, is the
/// card's stack (`CardStack`), the same as Wide's column. The room under the
/// cover is the same at every width (`StyleGeometry.bigArtControlsHeight`),
/// so the window is the width plus it.
struct BigArtNowLayout: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.surfaceIsActive) private var surfaceIsActive

    /// From the card's edges to the cover and the stack, and between them.
    nonisolated static let inset = Spacing.m

    var body: some View {
        let status = NowStatus(store)
        Group {
            if status == .ready, let track = store.track {
                let menu = TrackMenu.current(store)
                GeometryReader { proxy in
                    let cover = Self.coverSide(width: proxy.size.width)
                    VStack(spacing: Self.inset) {
                        ArtworkView(artwork: store.artwork)
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
                        CardStack(track: track, menu: menu, width: cover)
                            .frame(maxHeight: .infinity)
                    }
                    .padding(Self.inset)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
                .nowContextMenu(menu)
            } else {
                NowEmptyState(status: status, drawsBackdrop: false)
                    .nowContextMenu(nil)
            }
        }
        .barMetrics(playsAtSecondarySize: true)
        .windowMaterial(.glassCard)
        .environment(\.humColorContext, .material)
        .accessibilityElement(children: .contain)
    }

    /// The cover's side, and the stack's width, in a card `width` wide.
    nonisolated static func coverSide(width: CGFloat) -> CGFloat {
        max(0, width - 2 * inset)
    }

    /// The room the stack has under the cover: the controls' height less the
    /// cover's gap and the inset below.
    nonisolated static var stackRoom: CGFloat {
        CGFloat(StyleGeometry.bigArtControlsHeight) - inset
    }
}

#if DEBUG
struct BigArtNowLayout_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery(style: .bigArt) { BigArtNowLayout() }
            PreviewGallery(isPlaying: false, style: .bigArt) { BigArtNowLayout() }
        }
    }
}
#endif
