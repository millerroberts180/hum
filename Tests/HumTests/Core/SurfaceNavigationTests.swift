import Foundation
import HumCore
import Testing

@Suite("Surface navigation")
struct SurfaceNavigationTests {
    @Test func surfacesAreInSwipeOrder() {
        #expect(Surface.allCases == [.now, .echo, .status])
        #expect(Surface.allCases.map(\.index) == [0, 1, 2])
        #expect(Surface(index: 3) == nil)
        #expect(Surface(index: -1) == nil)
    }

    @Test func statusHasItsTitleAndSymbol() {
        #expect(Surface.status.title == "Status")
        #expect(Surface.status.systemImage == "antenna.radiowaves.left.and.right")
        #expect(Surface.allCases.map(\.title) == ["Now", "History", "Status"])
    }

    /// The second page reads as History (§13.23) but is still stored as
    /// `echo`, so saved settings and widgets keep finding it.
    @Test func historyIsStillStoredAsEcho() throws {
        #expect(Surface.echo.title == "History")
        #expect(String(decoding: try JSONEncoder().encode(Surface.echo), as: UTF8.self) == "\"echo\"")
        #expect(Surface(storedValue: "echo") == .echo)
    }

    @Test func forwardAndBackStopAtTheEnds() {
        // `#expect` can't call a mutating method, so each step is taken first.
        var navigation = SurfaceNavigation()
        #expect(!navigation.canGoBack)
        let backAtStart = navigation.back()
        #expect(!backAtStart)
        let steps = (0..<2).map { _ in navigation.forward() }
        #expect(steps == [true, true])
        #expect(navigation.current == .status)
        #expect(!navigation.canGoForward)
        let forwardAtEnd = navigation.forward()
        #expect(!forwardAtEnd)
        let backFromEnd = navigation.back()
        #expect(backFromEnd)
        #expect(navigation.current == .echo)
    }

    @Test func goingToTheCurrentSurfaceIsNotAChange() {
        var navigation = SurfaceNavigation(current: .echo)
        let sameSurface = navigation.go(to: .echo)
        #expect(!sameSurface)
        let otherSurface = navigation.go(to: .now)
        #expect(otherSurface)
        #expect(navigation.current == .now)
    }

    /// Settings saved before the redesign remember surfaces that are gone:
    /// Play and Find open on Now, and Pulse is History's old name (§13.9).
    @Test(arguments: [("play", Surface.now), ("find", .now), ("pulse", .echo), ("echo", .echo), ("status", .status)])
    func oldSurfaceNamesDecode(stored: String, expected: Surface) throws {
        let decoded = try JSONDecoder().decode(Surface.self, from: Data("\"\(stored)\"".utf8))
        #expect(decoded == expected)
    }

    @Test func anUnknownSurfaceDoesNotDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Surface.self, from: Data("\"library\"".utf8))
        }
    }

    @Test func surfacesEncodeUnderTheirOwnNames() throws {
        let encoded = try JSONEncoder().encode([Surface.now, .echo, .status])
        #expect(String(decoding: encoded, as: UTF8.self) == #"["now","echo","status"]"#)
    }
}
