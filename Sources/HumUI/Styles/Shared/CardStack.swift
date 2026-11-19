import HumCore
import SwiftUI

/// What Wide and Big Art share (DESIGN.md §7): the stack beside Wide's cover
/// and under Big Art's, `Spacing.s` between its rows. The title row (title
/// over artist, one line each, with Save and More at its trailing end), the
/// seek bar with its two times under it, the transport spread across the
/// width, and the volume row.
///
/// Everything always shows; on hover only the seek bar grows, as any seek bar
/// does. Each piece but the title follows the look's hover controls, as far as
/// the style offers them: Big Art has the album on the artist's line at M and
/// L, Wide doesn't.
struct CardStack: View {
    var track: Track
    var menu: TrackMenu?
    /// The stack's width, which the transport spreads across.
    var width: CGFloat

    @Environment(NowPlayingStore.self) private var store
    @Environment(\.playerLook) private var look

    /// Between the rows.
    nonisolated static let rowGap = Spacing.s

    var body: some View {
        let shown = look.look.hoverControls.intersection(look.style.hoverChoices)
        VStack(alignment: .leading, spacing: Self.rowGap) {
            TrackHeader(
                track: track,
                menu: menu,
                showsSave: shown.contains(.save),
                showsAlbum: shown.contains(.album),
                showsDevice: false
            )
            if shown.contains(.seekBar) {
                SeekBar(updatesAtRest: true, showsTimes: true)
            }
            TransportRow(showsShuffleRepeat: shown.contains(.shuffleRepeat), fit: .spread(width))
            if shown.contains(.volume), store.capabilities.contains(.volume) {
                VolumeControl()
            }
        }
        .frame(width: width)
    }
}
