import Observation

/// When the page indicator shows (DESIGN.md §6, §13.21): only when the page
/// changes, as a sign of the change rather than a fixture.
///
/// It's hidden at rest and on hover. It shows from the moment the page starts
/// to move (a swipe tracking, a spring from ⌘1–⌘3, Show ▸ or Esc) or lands
/// somewhere new without moving (Reduce Motion's crossfade, a jump), stays for
/// as long as the page moves, and goes `hold` after it comes to rest. A swipe
/// that rubber-bands at an end and settles back where it was counts too. A new
/// change restarts the hold.
///
/// It follows the pager's position and movement, and nothing else: revealing
/// the controls doesn't bring it.
@MainActor
@Observable
final class PageIndicatorVisibility {
    private(set) var isShown = false

    /// How long it stays once the page settles.
    static let hold: Duration = .milliseconds(1500)

    @ObservationIgnored private weak var pager: SurfacePager?
    /// Where the page was last seen, and whether it was moving.
    @ObservationIgnored private var position: Double
    @ObservationIgnored private var isMoving: Bool
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    /// - Parameter sleep: How the hold is waited out; tests pass their own.
    init(
        following pager: SurfacePager,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.pager = pager
        self.sleep = sleep
        position = pager.position
        isMoving = pager.isMoving
        observe(pager)
    }

    /// The page moved, or came to rest somewhere: show, and while it's still,
    /// start the hold over.
    func pageChanged(isMoving: Bool) {
        if !isShown { isShown = true }
        holdTask?.cancel()
        holdTask = nil
        guard !isMoving else { return }
        let sleep = sleep
        holdTask = Task { [weak self] in
            try? await sleep(Self.hold)
            guard !Task.isCancelled, let self else { return }
            self.isShown = false
        }
    }

    /// A change to where the page is, or to whether it's moving, is a change
    /// of page. The pager also sets values it already has (a vertical swipe
    /// ends "tracking" it never started), which aren't.
    private func observe(_ pager: SurfacePager) {
        withObservationTracking {
            _ = pager.position
            _ = pager.isMoving
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let pager = self.pager else { return }
                if pager.position != self.position || pager.isMoving != self.isMoving {
                    self.position = pager.position
                    self.isMoving = pager.isMoving
                    self.pageChanged(isMoving: pager.isMoving)
                }
                self.observe(pager)
            }
        }
    }
}
