import HumCore
import SwiftUI

/// The cover, filling its frame. A new cover crossfades in over the old one
/// while settling from 1.02 to 1; under Reduce Motion it only crossfades.
struct ArtworkView: View {
    var artwork: ArtworkImage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ArtworkPlaceholder()
            if let artwork {
                Image(decorative: artwork.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .id(artwork.key)
                    .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: Motion.trackChangeScale)),
                            removal: .opacity
                        ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(reduceMotion ? Motion.crossfade : Motion.trackChangeArtwork, value: artwork?.key)
        .accessibilityHidden(true)
    }
}

/// Shown while a cover loads, or when a track has none: the one missing-artwork
/// tile, sized to the cover rather than the player. The window background under
/// it keeps the translucent fill from showing the desktop through the player.
struct ArtworkPlaceholder: View {
    var body: some View {
        GeometryReader { proxy in
            MissingArtwork(side: min(proxy.size.width, proxy.size.height))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
