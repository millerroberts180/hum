import HumCore
import SwiftUI

/// The Menu Bar style's Now Playing popover content (DESIGN.md §7.1), like
/// Control Center's: the cover, the title and artist with Pop Out Player at the
/// end of their row, the white seek bar with times, and the transport: all
/// five controls, or three when the look's Shuffle and Repeat switch is off
/// (§8). The system popover draws the material around it.
///
/// Needs `NowPlayingStore`, `PlayerInteraction` (with its controls revealed)
/// and the player look in the environment, as the player window has them;
/// `SettingsStore` and `playerActions` when there are any.
public struct MenuBarNowView: View {
    private let popOut: @MainActor () -> Void

    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerLook) private var look

    /// The popover's width.
    nonisolated static let width: CGFloat = 300
    /// The cover's inset from the popover's edges.
    nonisolated static let inset = Spacing.l
    /// The cover's side: the width less its insets, 268 pt.
    nonisolated static var coverSide: CGFloat { width - inset * 2 }

    public init(popOut: @escaping @MainActor () -> Void) {
        self.popOut = popOut
    }

    public var body: some View {
        let metrics = PlayerMetrics(side: Self.width)
        let track = NowStatus(store) == .ready ? store.track : nil
        VStack(alignment: .leading, spacing: Spacing.m) {
            ArtworkView(artwork: track == nil ? nil : store.artwork)
                .frame(width: Self.coverSide, height: Self.coverSide)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            VStack(alignment: .leading, spacing: Spacing.s) {
                titleRow(track: track, metrics: metrics)
                if track != nil {
                    SeekBar(updatesAtRest: true)
                    TransportRow(showsShuffleRepeat: look.hoverControls(at: metrics.sizeClass).contains(.shuffleRepeat))
                }
            }
        }
        .padding(Self.inset)
        .frame(width: Self.width)
        .environment(\.playerMetrics, metrics)
        .environment(\.humColorContext, .material)
    }

    private func titleRow(track: Track?, metrics: PlayerMetrics) -> some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(track?.title ?? "Nothing Playing")
                    .humText(.trackTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
                if let artist = track?.artist, !artist.isEmpty {
                    Text(artist)
                        .humText(.trackArtist)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                popOut()
            } label: {
                Image(systemName: Self.popOutSymbol)
            }
            .buttonStyle(PlayerButtonStyle(.icon, size: metrics.tertiary))
            // The hit target overhangs the glyph; keep the glyph on the edge.
            .padding(.trailing, -metrics.tertiary.outset)
            .accessibilityLabel(Self.popOutTitle)
            .help(Self.popOutTitle)
        }
    }

    nonisolated static let popOutTitle = "Pop Out Player"
    nonisolated static let popOutSymbol = "menubar.arrow.down.rectangle"
}

#if DEBUG
struct MenuBarNowView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewGallery(cases: [.largeLight, .largeDark], isSquare: false) {
            MenuBarNowView(popOut: {})
        }
    }
}
#endif
