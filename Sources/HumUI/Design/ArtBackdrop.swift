import HumCore
import SwiftUI

/// `artBackdrop` (DESIGN.md §3.6): under the wash of History and Status.
/// The cover blurred and saturated, washed toward the appearance. Reduce
/// Transparency replaces it with the album accent at 20% over the window
/// background.
struct ArtBackdrop: View {
    var artwork: ArtworkImage?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if reduceTransparency {
                if let tint = artwork.map(Self.reducedTransparencyTint) {
                    Color(tint).opacity(Self.reducedTransparencyOpacity)
                }
            } else if let artwork {
                // Filled over a clear view, so the backdrop takes the room
                // it's offered: a portrait card's page isn't laid out as wide
                // as the cover's fill.
                Color.clear
                    .overlay {
                        Image(decorative: artwork.cgImage, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 60, opaque: true)
                            .saturation(1.6)
                    }
                    .id(artwork.key)
                    .transition(.opacity)
                Rectangle()
                    .fill(colorScheme == .dark ? Color.black.opacity(Self.darkOverlay) : Color.white.opacity(Self.lightOverlay))
            }
        }
        .clipped()
        .animation(Motion.trackChangeArtwork, value: artwork?.key)
        .accessibilityHidden(true)
    }

    nonisolated static let darkOverlay = 0.25
    nonisolated static let lightOverlay = 0.35
    nonisolated static let reducedTransparencyOpacity = 0.2

    nonisolated static func reducedTransparencyTint(_ artwork: ArtworkImage) -> PaletteColor {
        artwork.palette.accent ?? artwork.palette.background
    }
}
