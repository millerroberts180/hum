import CoreGraphics
@testable import HumUI
import SwiftUI
import Testing

/// At S an empty state wraps rather than truncates (DESIGN.md §5.5).
@MainActor
@Suite("Empty state at S")
struct EmptyStateWrapTests {
    func height(title: String, message: String) throws -> Int {
        let state = EmptyState(symbol: HumIcon.permission, title: title, message: message)
            .environment(\.playerMetrics, PlayerMetrics(side: PlayerMetrics.minimumSide))
            .frame(width: PlayerMetrics.minimumSide)
        return try #require(ImageRenderer(content: state).cgImage).height
    }

    /// The permission explanation takes five lines in the smallest player:
    /// all five show, not three and an ellipsis.
    @Test func aLongExplanationShowsWhole() throws {
        let title = PermissionGuide.neededTitle(app: "Spotify")
        let short = try height(title: title, message: "macOS will ask once.")
        let long = try height(title: title, message: PermissionGuide.neededMessage(app: "Spotify"))
        // Four more lines of caption, at 12 pt or more each.
        #expect(long - short >= 44)
    }

    /// "Let Hum Control Spotify" takes two lines there.
    @Test func aTitleMayTakeTwoLines() throws {
        let one = try height(title: "Hum", message: "macOS will ask once.")
        let two = try height(title: PermissionGuide.neededTitle(app: "Spotify"), message: "macOS will ask once.")
        #expect(two - one >= 12)
    }
}
