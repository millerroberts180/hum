import HumCore

/// Decides when the player shows and hides itself, per the visibility setting.
///
/// - Always Visible: shown at launch, hidden only by the user.
/// - On Track Change: appears when the song changes, then tucks itself away after
///   a few seconds. The countdown waits while the pointer is over it, the keyboard
///   is in use, or a scrub is in progress.
/// - Only When Summoned: hidden until the shortcut or menu brings it up, and
///   hidden again once the user clicks elsewhere.
/// - Tucked: like Only When Summoned, but the player slides down from under the
///   menu bar and back up the same way.
@MainActor
final class PlayerVisibilityController {
    enum ShowReason: Equatable {
        case launch
        case trackChange
        case user
    }

    var mode: PlayerVisibility {
        didSet { if mode != oldValue { modeDidChange() } }
    }
    let displaySeconds: Double

    /// Hooks to the window. Set by the owner before `launch()`.
    var show: (ShowReason) -> Void = { _ in }
    var hide: () -> Void = {}
    var isVisible: () -> Bool = { false }
    var isEngaged: () -> Bool = { false }

    private var hideTask: Task<Void, Never>?
    private let sleep: @MainActor (Duration) async throws -> Void

    /// - Parameter sleep: How the countdown waits out `displaySeconds`; tests pass their own.
    init(
        mode: PlayerVisibility,
        displaySeconds: Double,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.mode = mode
        self.displaySeconds = displaySeconds
        self.sleep = sleep
    }

    func launch() {
        if mode == .pinned {
            show(.launch)
        }
    }

    func trackDidChange() {
        guard mode == .trackChanges else { return }
        show(.trackChange)
        scheduleHide()
    }

    /// The user showed the player from the menu or a shortcut.
    func userDidShow() {
        if mode == .trackChanges {
            scheduleHide()
        }
    }

    func userDidHide() {
        cancelHide()
    }

    func engagementDidChange() {
        guard mode == .trackChanges, isVisible() else { return }
        scheduleHide()
    }

    func playerDidResignKey() {
        switch mode {
        case .summoned, .tucked:
            if isVisible() { hide() }
        case .trackChanges:
            scheduleHide()
        case .pinned:
            break
        }
    }

    var hasPendingHide: Bool { hideTask != nil }

    private func modeDidChange() {
        cancelHide()
        switch mode {
        case .pinned:
            if !isVisible() { show(.user) }
        case .trackChanges:
            if isVisible() { scheduleHide() }
        case .summoned, .tucked:
            break
        }
    }

    private func scheduleHide() {
        cancelHide()
        guard !isEngaged() else { return }
        let delay = Duration.milliseconds(Int(displaySeconds * 1000))
        let sleep = sleep
        hideTask = Task { [weak self] in
            try? await sleep(delay)
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            if self.mode == .trackChanges, !self.isEngaged(), self.isVisible() {
                self.hide()
            }
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}
