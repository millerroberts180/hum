import HumCore
import SwiftUI

/// The Art Only style (DESIGN.md §7): the cover fills the player edge to edge at
/// every size, alone at rest unless the look asks for a resting line or ring.
/// On hover or focus everything appears at once (`ControlsOverlay`).
struct ArtFirstNowLayout: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(PlayerInteraction.self) private var interaction
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.playerLook) private var look

    var body: some View {
        let status = NowStatus(store)
        let isRevealed = interaction.isRevealed
        let menu = TrackMenu.current(store)
        ZStack {
            if status == .ready {
                ArtworkView(artwork: store.artwork)
                    .volumeSwipeArea()
                RestingIndicator(kind: look.look.progress, isHidden: isRevealed)
                    .environment(\.humColorContext, .artwork)
                    .animation(isRevealed ? Motion.reveal : Motion.conceal, value: isRevealed)
                // Crossing a size class swaps the layout; crossfade rather than jump.
                ControlsOverlay(isRevealed: isRevealed, menu: menu)
                    .id(metrics.sizeClass)
                    .transition(.opacity)
            } else {
                NowEmptyState(status: status)
            }
        }
        .animation(Motion.smooth, value: metrics.sizeClass)
        .nowContextMenu(menu)
    }
}

#if DEBUG
struct ArtFirstNowLayout_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery(style: .artOnly) { ArtFirstNowLayout() }
            PreviewGallery(style: .artOnly, revealsControls: true) { ArtFirstNowLayout() }
        }
    }
}
#endif
