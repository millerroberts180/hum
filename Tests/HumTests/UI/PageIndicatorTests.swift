import AppKit
import HumCore
@testable import HumUI
import SwiftUI
import Testing

/// The pager reads as one adjustable control to VoiceOver (DESIGN.md §9).
@Suite("Page indicator")
struct PageIndicatorTests {
    @Test func itSaysWhereYouAreAndHowManyThereAre() {
        #expect(PageIndicator.spokenValue(.now) == "Now, 1 of 3")
        #expect(PageIndicator.spokenValue(.echo) == "History, 2 of 3")
        #expect(PageIndicator.spokenValue(.status) == "Status, 3 of 3")
    }

    @Test(arguments: [0.0, 0.5, 1, 1.25, 2])
    func theMarksShareOnePagesWorthOfEmphasis(position: Double) {
        let total = Surface.allCases.map { PageIndicator.emphasis(of: $0, at: position) }.reduce(0, +)
        #expect(abs(total - 1) < 0.0001)
    }
}

/// A clock a test moves by hand: each sleep ends once the clock has passed
/// its deadline, or throws once its task is cancelled.
@MainActor
final class SteppedClock {
    private(set) var now: Duration = .zero
    /// Every duration asked for, in order.
    private(set) var requested: [Duration] = []
    private var pending: [(id: Int, deadline: Duration, continuation: CheckedContinuation<Void, any Error>)] = []
    private var nextID = 0

    /// How many sleeps are waiting now.
    var waiting: Int { pending.count }

    func sleep(_ duration: Duration) async throws {
        requested.append(duration)
        let id = nextID
        nextID += 1
        let deadline = now + duration
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append((id, deadline, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    /// Moves the clock on, ending every sleep it passes.
    func advance(by duration: Duration) {
        now += duration
        let due = pending.filter { $0.deadline <= now }
        pending.removeAll { $0.deadline <= now }
        for sleep in due { sleep.continuation.resume() }
    }

    private func cancel(_ id: Int) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// Frames on demand, so a spring can be run to rest without a display.
@MainActor
private final class StepFrameDriver: FrameDriving {
    var onFrame: ((TimeInterval) -> Void)?
    private(set) var isRunning = false

    func start() { isRunning = true }
    func stop() { isRunning = false }

    /// Step at 60 fps until the driver stops or `limit` seconds pass.
    func run(from start: TimeInterval = 10, limit: TimeInterval = 5) {
        var time = start
        while isRunning, time - start < limit {
            onFrame?(time)
            time += 1.0 / 60
        }
    }
}

private func sample(_ phase: ScrollSample.Phase, x: Double = 0, at time: TimeInterval = 0) -> ScrollSample {
    ScrollSample(phase: phase, isMomentum: false, fingerDeltaX: x, deltaY: 0, isPrecise: true, timestamp: time)
}

/// The indicator shows only when the page changes: from the first movement
/// until 1.5 s after the page settles (DESIGN.md §6, §13.21). The clock is the
/// test's, so a busy machine can't end the hold early or late.
@MainActor
@Suite("Page indicator visibility")
struct PageIndicatorVisibilityTests {
    let clock = SteppedClock()

    private func pager(on surface: Surface = .now, springs: Bool = false) -> (SurfacePager, PageIndicatorVisibility, StepFrameDriver?) {
        let pager = SurfacePager(surface: surface)
        pager.pageWidth = 200
        var driver: StepFrameDriver?
        if springs {
            driver = StepFrameDriver()
            pager.frameDriver = driver
        }
        let clock = clock
        let visibility = PageIndicatorVisibility(following: pager) { try await clock.sleep($0) }
        return (pager, visibility, driver)
    }

    @Test func theHoldIsASecondAndAHalf() {
        #expect(PageIndicatorVisibility.hold == .milliseconds(1500))
    }

    /// Nothing at rest, on any surface, however long it's given.
    @Test(arguments: Surface.allCases)
    func itsHiddenAtRest(surface: Surface) async {
        let (_, visibility, _) = pager(on: surface)
        await waitUntil { visibility.isShown }
        #expect(!visibility.isShown)
        #expect(clock.requested.isEmpty)
    }

    /// From the moment a swipe starts tracking, and for as long as it does.
    @Test func itShowsDuringASwipe() async {
        let (pager, visibility, _) = pager(springs: true)
        _ = pager.handle(sample(.began))
        _ = pager.handle(sample(.changed, x: -8, at: 0.01))
        // Not yet: the axis hasn't locked, so the page hasn't moved.
        await waitUntil { visibility.isShown }
        #expect(!visibility.isShown)
        _ = pager.handle(sample(.changed, x: -8, at: 0.02))
        #expect(pager.isTracking)
        await waitUntil { visibility.isShown }
        #expect(visibility.isShown)
        // No hold while the fingers are on the page.
        _ = pager.handle(sample(.changed, x: -20, at: 0.03))
        await waitUntil { clock.waiting > 0 }
        #expect(clock.waiting == 0)
        #expect(visibility.isShown)
    }

    /// It stays while the page moves, 1.5 s once it settles, and goes.
    @Test func itGoesOneAndAHalfSecondsAfterThePageSettles() async {
        let (pager, visibility, driver) = pager(springs: true)
        pager.go(to: .echo, animated: true)
        #expect(pager.isSettling)
        await waitUntil { visibility.isShown }
        #expect(visibility.isShown)
        #expect(clock.waiting == 0)

        driver?.run()
        #expect(!pager.isMoving)
        #expect(pager.position == 1)
        await waitUntil { clock.waiting == 1 }
        #expect(clock.requested == [PageIndicatorVisibility.hold])

        clock.advance(by: .milliseconds(1490))
        // Give it every chance to go early.
        await waitUntil { !visibility.isShown }
        #expect(visibility.isShown)

        clock.advance(by: .milliseconds(10))
        await waitUntil { !visibility.isShown }
        #expect(!visibility.isShown)
    }

    /// A new change starts the hold over: the first one's end doesn't hide it.
    @Test func aSecondChangeRestartsTheHold() async {
        let (pager, visibility, _) = pager()
        pager.go(to: .echo, animated: true)
        await waitUntil { clock.waiting == 1 }
        #expect(visibility.isShown)

        clock.advance(by: .seconds(1))
        pager.go(to: .status, animated: true)
        await waitUntil { clock.requested.count == 2 && clock.waiting == 1 }
        #expect(clock.requested == [PageIndicatorVisibility.hold, PageIndicatorVisibility.hold])

        // 2 s after the first change, 1 s after the second.
        clock.advance(by: .seconds(1))
        await waitUntil { !visibility.isShown }
        #expect(visibility.isShown)

        clock.advance(by: .milliseconds(500))
        await waitUntil { !visibility.isShown }
        #expect(!visibility.isShown)
    }

    /// A swipe past the first page rubber-bands and settles back on Now: the
    /// page didn't change, but it moved, so the indicator shows.
    @Test func aRubberBandedSwipeShowsIt() async {
        let (pager, visibility, driver) = pager(springs: true)
        _ = pager.handle(sample(.began))
        _ = pager.handle(sample(.changed, x: 60, at: 0.01))
        _ = pager.handle(sample(.changed, x: 60, at: 0.02))
        #expect(pager.position < 0)
        await waitUntil { visibility.isShown }
        #expect(visibility.isShown)

        _ = pager.handle(sample(.ended, at: 0.03))
        driver?.run()
        #expect(pager.current == .now)
        #expect(pager.position == 0)
        await waitUntil { clock.waiting == 1 }
        #expect(visibility.isShown)

        clock.advance(by: PageIndicatorVisibility.hold)
        await waitUntil { !visibility.isShown }
        #expect(!visibility.isShown)
    }

    /// ⌘1–⌘3, Show ▸ and Esc all go through `go(to:)`.
    @Test(arguments: [Surface.echo, .status])
    func aProgrammaticChangeShowsIt(surface: Surface) async {
        let (pager, visibility, _) = pager()
        pager.go(to: surface, animated: true)
        await waitUntil { visibility.isShown }
        #expect(visibility.isShown)
        await waitUntil { clock.waiting == 1 }
        #expect(clock.requested == [PageIndicatorVisibility.hold])
    }

    /// Esc back to Now.
    @Test func goingBackToNowShowsIt() async {
        let (pager, visibility, _) = pager(on: .echo)
        pager.go(to: .now, animated: true)
        await waitUntil { visibility.isShown }
        #expect(visibility.isShown)
    }

    /// Under Reduce Motion the page crossfades rather than moving; it still
    /// changed.
    @Test func aCrossfadedChangeShowsIt() async {
        let (pager, visibility, _) = pager()
        pager.reduceMotion = true
        pager.go(to: .echo, animated: true)
        await waitUntil { visibility.isShown }
        #expect(visibility.isShown)
    }

    /// Asking for the page already in view changes nothing.
    @Test func stayingOnThePageDoesntShowIt() async {
        let (pager, visibility, _) = pager()
        pager.go(to: .now, animated: true)
        await waitUntil { visibility.isShown }
        #expect(!visibility.isShown)
    }
}

/// The root view shows the indicator from its visibility alone: revealing the
/// controls on hover doesn't bring it (DESIGN.md §6).
@MainActor
@Suite("Page indicator on the player")
struct PageIndicatorOnPlayerTests {
    typealias Pixels = MissingArtworkTests.Pixels

    static let side: CGFloat = 280

    func render(_ player: PreviewPlayer) throws -> Pixels {
        let metrics = PlayerMetrics(side: Self.side)
        let view = PlayerRootView()
            .frame(width: Self.side, height: Self.side)
            .environment(\.playerMetrics, metrics)
            .environment(\.playerLook, PlayerLook(
                style: .artOnly,
                look: player.settings.appearance.look(for: .artOnly, in: .dark),
                appearance: .dark,
                isBar: false
            ))
            .environment(\.colorScheme, .dark)
            .environment(player.store)
            .environment(player.settings)
            .environment(player.pager)
            .environment(player.interaction)
        let renderer = ImageRenderer(content: player.services.inject(view))
        renderer.scale = 1
        return try Pixels(try #require(renderer.cgImage))
    }

    /// The pixels where the indicator sits.
    func indicatorPixels(_ pixels: Pixels) -> [[UInt8]] {
        let frame = PageIndicator.frame(width: Self.side, metrics: PlayerMetrics(side: Self.side)).integral
        var result: [[UInt8]] = []
        for y in Int(frame.minY)..<Int(frame.maxY) {
            for x in Int(frame.minX)..<Int(frame.maxX) {
                result.append(pixels.pixel(x: x, y: y))
            }
        }
        return result
    }

    func differs(_ a: [[UInt8]], _ b: [[UInt8]]) -> Bool {
        zip(a, b).contains { zip($0, $1).contains { abs(Int($0) - Int($1)) > 8 } }
    }

    @Test func revealingTheControlsDoesntShowIt() async throws {
        let player = PreviewPlayer()
        for _ in 0..<500 where player.store.artwork == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(player.store.artwork != nil)
        let clock = SteppedClock()
        let visibility = PageIndicatorVisibility(following: player.pager) { try await clock.sleep($0) }
        player.pager.indicator = visibility

        let rest = indicatorPixels(try render(player))
        player.interaction.alwaysReveal = true
        #expect(player.interaction.isRevealed)
        let revealed = indicatorPixels(try render(player))
        #expect(!visibility.isShown)
        #expect(!differs(rest, revealed))

        // The same place shows the marks once the page changes.
        visibility.pageChanged(isMoving: true)
        let shown = indicatorPixels(try render(player))
        #expect(differs(rest, shown))
    }
}
