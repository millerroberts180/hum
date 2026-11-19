import CoreGraphics
import HumCore
@testable import HumUI
import Testing

/// The artwork corners (DESIGN.md §3.2).
@Suite("Corner radii")
struct RadiusTests {
    @Test func coversTakeTheTokenCorners() {
        #expect(Radius.artSmall == 4)
        #expect(Radius.artMedium == 6)
        #expect(Radius.card == 12)
    }
}
