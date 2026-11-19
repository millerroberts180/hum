import HumCore
import SwiftUI

/// The Title style (DESIGN.md §7): a bar 72 pt tall on `glassCard` at the
/// window level, with the cover at the leading edge and the title over the
/// artist beside it.
///
/// On hover or focus the words fade out and the controls fade in in the same
/// column: the transport row on top, and under it the seek bar between its two
/// times, or the bar alone below 300 pt wide. There's no page indicator
/// (§7.2), and a HUD takes the column's place for its hold (`BarHUD`).
struct TitleNowLayout: View {
    @Environment(NowPlayingStore.self) private var store
    @Environment(PlayerInteraction.self) private var interaction
    @Environment(\.playerLook) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cover's side and corner (`Radius.artMedium`).
    nonisolated static let coverSide: CGFloat = 56
    /// From the bar's edges to the cover.
    nonisolated static let inset = Spacing.s
    /// Between the cover and the column.
    nonisolated static let columnGap = Spacing.m
    /// From the column to the bar's trailing edge.
    nonisolated static let trailingInset = Spacing.m
    /// The width from which the seek bar shows its times.
    nonisolated static let timesWidth: CGFloat = 300

    var body: some View {
        let status = NowStatus(store)
        let track = status == .ready ? store.track : nil
        let isRevealed = interaction.isRevealed && track != nil
        let menu = TrackMenu.current(store)
        HStack(spacing: Self.columnGap) {
            ArtworkView(artwork: track == nil ? nil : store.artwork)
                .frame(width: Self.coverSide, height: Self.coverSide)
                .clipShape(RoundedRectangle(cornerRadius: Radius.artMedium, style: .continuous))
                .volumeSwipeArea()
            BarHUD {
                ZStack(alignment: .leading) {
                    Group {
                        if let track {
                            BarTitleStack(track: track, titleRole: .trackTitle, artistRole: .trackArtist)
                        } else {
                            BarStatus(status: status)
                        }
                    }
                    .opacity(isRevealed ? 0 : 1)
                    .accessibilityHidden(isRevealed)
                    if track != nil {
                        TitleControls()
                            .offset(y: isRevealed || reduceMotion ? 0 : Motion.revealTravel)
                            .opacity(isRevealed ? 1 : 0)
                            .allowsHitTesting(isRevealed)
                            .accessibilityHidden(!isRevealed)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding([.leading, .vertical], Self.inset)
        .padding(.trailing, Self.trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(isRevealed ? Motion.reveal : Motion.conceal, value: isRevealed)
        .barMetrics(playsAtSecondarySize: true)
        .windowMaterial(.glassCard)
        .environment(\.humColorContext, .material)
        .help(track.map(BarText.titleAndArtist) ?? "")
        .nowContextMenu(menu)
    }

    /// The column beside the cover in a bar `side` wide.
    nonisolated static func columnWidth(side: CGFloat) -> CGFloat {
        max(0, side - inset - coverSide - columnGap - trailingInset)
    }
}

/// The transport, top-aligned in the column, and the seek row under it.
private struct TitleControls: View {
    @Environment(\.playerMetrics) private var metrics
    @Environment(\.playerLook) private var look

    var body: some View {
        let shown = look.look.hoverControls
        let column = TitleNowLayout.columnWidth(side: metrics.side)
        VStack(spacing: 0) {
            TransportRow(showsShuffleRepeat: shown.contains(.shuffleRepeat), fit: .fitting(column))
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            if shown.contains(.seekBar) {
                SeekBar(timesBeside: true, showsTimes: metrics.side >= TitleNowLayout.timesWidth)
            }
        }
        .frame(height: TitleNowLayout.coverSide)
    }
}

#if DEBUG
struct TitleNowLayout_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewGallery(style: .title) { TitleNowLayout() }
            PreviewGallery(style: .title, revealsControls: true) { TitleNowLayout() }
        }
    }
}
#endif
