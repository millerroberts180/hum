import Foundation
@testable import HumUI
import Testing

/// Play and Find show one HUD at a time: the volume HUD and the library's
/// notice center in the same place (DESIGN.md §5.8).
@Suite("One HUD at a time on Play and Find")
struct LibraryNoticeLayerTests {
    let notice = UUID()

    @Test func aNoticeShowsWhileTheVolumeHUDDoesnt() {
        #expect(LibraryNoticeLayer.showsNotice(notice, isVolumeShowing: false, superseded: nil))
    }

    @Test func theVolumeHUDHidesTheNotice() {
        #expect(!LibraryNoticeLayer.showsNotice(notice, isVolumeShowing: true, superseded: nil))
    }

    /// Once the volume HUD has replaced a notice, that notice stays hidden
    /// after the volume HUD goes; only a newer one shows.
    @Test func aReplacedNoticeDoesntComeBack() {
        #expect(!LibraryNoticeLayer.showsNotice(notice, isVolumeShowing: false, superseded: notice))
        #expect(LibraryNoticeLayer.showsNotice(UUID(), isVolumeShowing: false, superseded: notice))
    }
}
