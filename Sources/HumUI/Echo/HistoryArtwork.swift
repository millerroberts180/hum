import HumCore
import SwiftUI

/// A small cover from the artwork cache, for trails and lists, cropped to
/// fill its square under a hairline edge. Shows `MissingArtwork` when the
/// cache has nothing for the track.
struct HistoryArtwork: View {
    var key: String
    var side: CGFloat
    var radius: CGFloat = Radius.artSmall

    @Environment(ListeningHistory.self) private var history: ListeningHistory?
    @Environment(NowPlayingStore.self) private var store: NowPlayingStore?
    @State private var image: ArtworkImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        cover
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(HumColor.glassStroke, lineWidth: 0.5)
            }
        // Asked again as history changes while there's no cover, since one can
        // land in the cache after this view first asked.
        .task(id: ArtworkRequest(key: key, revision: image == nil ? history?.revision ?? 0 : 0)) {
            guard let cache = history?.artworkCache else { return }
            let found = await cache.image(forKey: key)
            if found != image { image = found }
        }
        .accessibilityHidden(true)
    }

    /// The cover over the placeholder, cropped to fill the square.
    private var cover: some View {
        ZStack {
            MissingArtwork(side: side)
            if let shown = image ?? liveArtwork {
                Image(decorative: shown.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            }
        }
        .frame(width: side, height: side)
    }

    /// The playing track's cover, which can arrive after the cache was asked.
    private var liveArtwork: ArtworkImage? {
        guard let artwork = store?.artwork, artwork.key == key else { return nil }
        return artwork
    }
}

private struct ArtworkRequest: Hashable {
    var key: String
    var revision: Int
}
