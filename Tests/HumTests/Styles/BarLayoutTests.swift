import AppKit
import CoreGraphics
import Foundation
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// Title, Text and Strip (DESIGN.md §7): what fits in a bar, and the HUD that
/// takes its content's place (§5.8).
@Suite("Bar layouts")
struct BarLayoutTests {
    static func barMetrics(width: CGFloat, playsAtSecondarySize: Bool = false) -> PlayerMetrics {
        PlayerMetrics(side: width, controlClass: .small, playsAtSecondarySize: playsAtSecondarySize)
    }

    static func extent(fitting width: CGFloat, _ metrics: PlayerMetrics, showsModes: Bool = true) -> CGFloat? {
        TransportRow.hitExtent(
            fitting: width,
            sizes: TransportRow.sizes(metrics, showsModes: showsModes),
            gap: metrics.transportGap
        )
    }

    /// The cover is 56 pt, `Spacing.s` from the edges, and the column takes
    /// the rest less `Spacing.m` either side.
    @Test func titlesColumnIsWhatTheCoverLeaves() {
        #expect(TitleNowLayout.coverSide == 56)
        #expect(Double(TitleNowLayout.coverSide + TitleNowLayout.inset * 2) == PlayerStyleID.title.shape.size(width: 300).height)
        #expect(TitleNowLayout.columnWidth(side: 240) == 152)
        #expect(TitleNowLayout.columnWidth(side: 420) == 332)
        #expect(TitleNowLayout.columnWidth(side: 0) == 0)
    }

    /// Title's five glyphs, play at the secondary size, always fit its column:
    /// closed up at the narrowest bar, at their standard gaps when it's wide.
    @Test func titlesTransportFitsItsColumn() {
        let narrow = Self.barMetrics(width: 240, playsAtSecondarySize: true)
        let closed = Self.extent(fitting: TitleNowLayout.columnWidth(side: 240), narrow)
        #expect(closed != nil)
        #expect(closed! >= 0)
        let wide = Self.barMetrics(width: 420, playsAtSecondarySize: true)
        #expect(Self.extent(fitting: TitleNowLayout.columnWidth(side: 420), wide) == nil)
    }

    /// The times show beside the seek bar from 300 pt.
    @Test func titlesTimesNeedRoom() {
        #expect(TitleNowLayout.timesWidth == 300)
        #expect(PlayerStyleID.title.shape.widths.contains(Double(TitleNowLayout.timesWidth)))
    }

    /// The notch keeps 56 pt; the transport gets what's left after the cover.
    @Test func stripsTransportLeavesTheNotchItsMinimum() {
        #expect(Double(StripNowLayout.coverSide + StripNowLayout.inset * 2) == PlayerStyleID.strip.shape.size(width: 300).height)
        #expect(StripNowLayout.transportRoom(side: 260) == 138)
        #expect(StripNowLayout.transportRoom(side: 440) == 318)
        #expect(StripNowLayout.transportRoom(side: 0) == 0)
        let room = StripNowLayout.transportRoom(side: 260)
        let used = room + StripNowLayout.inset + StripNowLayout.coverSide + StripNowLayout.gap * 2
            + StripNowLayout.notchMinimum + StripNowLayout.trailingInset
        #expect(used == 260)
    }

    /// At its narrowest the strip keeps all five controls by closing them up;
    /// at its widest they sit at the standard gaps.
    @Test func stripsTransportClosesUpWhenNarrow() {
        let narrow = Self.barMetrics(width: 260)
        let extent = Self.extent(fitting: StripNowLayout.transportRoom(side: 260), narrow)
        #expect(extent != nil)
        let sizes = TransportRow.sizes(narrow, showsModes: true)
        let width = sizes.reduce(0) { $0 + $1.backing + extent! * 2 }
        #expect(abs(width - StripNowLayout.transportRoom(side: 260)) < 0.001)
        #expect(Self.extent(fitting: StripNowLayout.transportRoom(side: 440), Self.barMetrics(width: 440)) == nil)
    }

    /// Never past touching backings, however narrow.
    @Test func aFittedRowNeverOverlaps() {
        #expect(Self.extent(fitting: 10, Self.barMetrics(width: 260)) == 0)
        #expect(TransportRow.hitExtent(fitting: 100, sizes: [], gap: 4) == nil)
    }

    /// Text spreads its glyphs inside `glyphInset` of the capsule's ends. At
    /// its narrowest they close up a little, their hit targets still past
    /// their backings; at its widest they spread at more than the standard gap.
    @Test func textsGlyphsFitTheCapsule() {
        let narrowest = CGFloat(PlayerStyleID.text.shape.widths.lowerBound) - TextNowLayout.glyphInset * 2
        let narrow = Self.barMetrics(width: narrowest, playsAtSecondarySize: true)
        let extent = Self.extent(fitting: narrowest, narrow)
        #expect(extent != nil)
        #expect(extent! > 0)
        let widest = CGFloat(PlayerStyleID.text.shape.widths.upperBound) - TextNowLayout.glyphInset * 2
        #expect(Self.extent(fitting: widest, Self.barMetrics(width: widest, playsAtSecondarySize: true)) == nil)
    }

    @Test func barsSayTitleThenArtist() {
        let track = Track(id: TrackID("a"), title: "Glide", artist: "Mira Okafor")
        #expect(BarText.titleAndArtist(track) == "Glide — Mira Okafor")
        let untitled = Track(id: TrackID("b"), title: "Glide", artist: "")
        #expect(BarText.titleAndArtist(untitled) == "Glide")
    }
}

/// The larger title (§13.20) still fits each bar's height (§7) at every
/// width: Title's title and artist beside its 56 pt cover, Text's in its
/// 44 pt capsule, and Strip's status line beside its 36 pt cover.
@MainActor
@Suite("Bar titles")
struct BarTitleFitTests {
    static let track = Track(
        id: TrackID("long"),
        title: "A Song Whose Title Runs Well Past the Width of Any Bar",
        artist: "Mira Okafor and the Long Names Ensemble"
    )

    static func widths(_ style: PlayerStyleID) -> [CGFloat] {
        let range = style.shape.widths
        // 380 is where L, and the 17 pt title, starts.
        return [range.lowerBound, 380, range.upperBound].filter(range.contains).map { CGFloat($0) }
    }

    func height(of content: some View, width: CGFloat) -> CGFloat {
        NSHostingView(rootView: content
            .frame(width: 120)
            .environment(\.playerMetrics, BarLayoutTests.barMetrics(width: width))
        ).fittingSize.height
    }

    @Test func titlesTitleAndArtistFitBesideTheCover() {
        for width in Self.widths(.title) {
            let stack = height(of: BarTitleStack(track: Self.track, titleRole: .trackTitle, artistRole: .trackArtist), width: width)
            #expect(stack > 0)
            #expect(stack <= TitleNowLayout.coverSide, "\(width): \(stack)")
        }
        // And L's title is the larger one.
        let large = height(of: Text("Glide").humText(.trackTitle), width: 420)
        let medium = height(of: Text("Glide").humText(.trackTitle), width: 300)
        #expect(large > medium)
    }

    @Test func textsTitleAndArtistFitTheCapsule() {
        let capsule = CGFloat(PlayerStyleID.text.shape.size(width: 300).height)
        #expect(capsule == 44)
        for width in Self.widths(.text) {
            let stack = height(of: BarTitleStack(track: Self.track, titleRole: .textTitle, artistRole: .textArtist), width: width)
            #expect(stack > 0)
            #expect(stack <= capsule, "\(width): \(stack)")
        }
    }

    @Test func stripsStatusFitsBesideTheCover() {
        for width in Self.widths(.strip) {
            let line = height(of: BarStatus(status: .nothingPlaying(app: "Music")), width: width)
            #expect(line > 0)
            #expect(line <= StripNowLayout.coverSide, "\(width): \(line)")
        }
    }
}

@Suite("Bar HUD")
struct BarHUDItemTests {
    @Test func nothingShowsWithoutAVolumeOrNotice() {
        #expect(BarHUDItem.current(volume: nil, notice: nil, superseded: nil) == nil)
    }

    /// The volume takes over from a notice, and clamps to 0...1.
    @Test func theVolumeWins() {
        let notice = LibraryNotice(.saved, source: nil)
        #expect(BarHUDItem.current(volume: 0.4, notice: notice, superseded: nil) == .volume(0.4))
        #expect(BarHUDItem.current(volume: 1.5, notice: nil, superseded: nil) == .volume(1))
        #expect(BarHUDItem.current(volume: -1, notice: nil, superseded: nil) == .volume(0))
    }

    /// A notice the volume put away doesn't come back after it.
    @Test func aSupersededNoticeStaysAway() {
        let notice = LibraryNotice(.saved, source: nil)
        #expect(BarHUDItem.current(volume: nil, notice: notice, superseded: nil) == .notice(notice))
        #expect(BarHUDItem.current(volume: nil, notice: notice, superseded: notice.id) == nil)
        let newer = LibraryNotice(.unsaved, source: nil)
        #expect(BarHUDItem.current(volume: nil, notice: newer, superseded: notice.id) == .notice(newer))
    }

    /// The label is replaced only when a different HUD takes over.
    @Test func identityIgnoresTheLevel() {
        #expect(BarHUDItem.volume(0.2).identity == BarHUDItem.volume(0.9).identity)
        let a = LibraryNotice(.saved, source: nil)
        let b = LibraryNotice(.saved, source: nil)
        #expect(BarHUDItem.notice(a).identity != BarHUDItem.notice(b).identity)
    }
}
