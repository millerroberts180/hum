import SwiftUI

/// The one placeholder for missing artwork, at every size (DESIGN.md §3.4): a
/// flat `fillTertiary` tile, no gradient, with the symbol centered at 0.55 of
/// the side in `quaternaryLabel`. Static while a cover loads, never a shimmer.
///
/// Lists pass their symbol per kind: `music.mic` for artists and podcasts,
/// `music.note.list` for playlists.
struct MissingArtwork: View {
    var side: CGFloat
    var symbol: String = HumIcon.musicNote

    var body: some View {
        ZStack {
            Rectangle().fill(HumColor.fillTertiary)
            Image(systemName: symbol)
                .font(.system(size: Self.symbolSize(side: side), weight: .regular))
                .foregroundStyle(HumColor.quaternaryLabel)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    nonisolated static func symbolSize(side: CGFloat) -> CGFloat {
        side * 0.55
    }
}
