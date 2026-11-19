import HumCore
import SwiftUI

/// The Strip style (DESIGN.md §7): a bar 48 pt tall on `glassCard` at the
/// window level, with the cover, a short seek bar (the seek notch), then
/// shuffle · previous · play/pause · next · repeat. Everything always shows.
///
/// There's no title on screen: the help tag and VoiceOver label read
/// "Title — Artist". On hover the notch grows and shows its time tag, as any
/// seek bar does. The notch takes the width the cover and the transport leave,
/// at least `notchMinimum`; where that isn't enough the transport closes up
/// (`TransportRow.Fit.fitting`). A HUD takes the notch's and the transport's
/// place for its hold (`BarHUD`).
struct StripNowLayout: View {
    @Environment(NowPlayingStore.self) private var store

    /// The cover's side.
    nonisolated static let coverSide: CGFloat = 36
    /// From the bar's edges to the cover.
    nonisolated static let inset: CGFloat = 6
    /// Between the cover, the notch and the transport.
    nonisolated static let gap = Spacing.s
    /// From the transport to the bar's trailing edge.
    nonisolated static let trailingInset = Spacing.s
    /// The seek notch is never shorter.
    nonisolated static let notchMinimum: CGFloat = 56

    var body: some View {
        let status = NowStatus(store)
        let track = status == .ready ? store.track : nil
        let menu = TrackMenu.current(store)
        HStack(spacing: Self.gap) {
            ArtworkView(artwork: track == nil ? nil : store.artwork)
                .frame(width: Self.coverSide, height: Self.coverSide)
                .clipShape(RoundedRectangle(cornerRadius: Radius.artMedium, style: .continuous))
                .volumeSwipeArea()
                .accessibilityHidden(true)
            BarHUD {
                if track != nil {
                    StripControls()
                } else {
                    // "Nothing Playing" in the notch's place (§6.2).
                    BarStatus(status: status)
                }
            }
        }
        .padding([.leading, .vertical], Self.inset)
        .padding(.trailing, Self.trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .barMetrics()
        .windowMaterial(.glassCard)
        .environment(\.humColorContext, .material)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(track.map(BarText.titleAndArtist) ?? "")
        .help(track.map(BarText.titleAndArtist) ?? "")
        .nowContextMenu(menu)
    }

    /// The width the transport may take in a strip `side` wide, leaving the
    /// notch its minimum.
    nonisolated static func transportRoom(side: CGFloat) -> CGFloat {
        max(0, side - inset - coverSide - gap - notchMinimum - gap - trailingInset)
    }
}

/// The notch and the transport, which take the room after the cover.
private struct StripControls: View {
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.playerLook) private var look

    var body: some View {
        let shown = look.look.hoverControls
        HStack(spacing: StripNowLayout.gap) {
            if shown.contains(.seekBar) {
                SeekBar(updatesAtRest: true, showsTimes: false)
                    .frame(minWidth: StripNowLayout.notchMinimum, maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            TransportRow(
                showsShuffleRepeat: shown.contains(.shuffleRepeat),
                fit: .fitting(StripNowLayout.transportRoom(side: metrics.side))
            )
        }
    }
}

#if DEBUG
struct StripNowLayout_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery(style: .strip) { StripNowLayout() }
            PreviewGallery(style: .strip, revealsControls: true) { StripNowLayout() }
        }
    }
}
#endif
