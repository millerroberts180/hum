import HumCore
@testable import HumUI
import Testing

/// A window stand-in that records what the controller asks of it.
@MainActor
private final class FakeWindow {
    var isVisible = false
    var isEngaged = false
    private(set) var shows: [PlayerVisibilityController.ShowReason] = []
    private(set) var hides = 0

    func attach(to controller: PlayerVisibilityController) {
        controller.show = { [self] reason in
            shows.append(reason)
            isVisible = true
        }
        controller.hide = { [self] in
            hides += 1
            isVisible = false
        }
        controller.isVisible = { [self] in isVisible }
        controller.isEngaged = { [self] in isEngaged }
    }
}

@MainActor
@Suite("Player visibility")
struct PlayerVisibilityControllerTests {
    /// The countdown ends only when the test says so, so a busy machine can't
    /// make it run out early or late.
    private func make(_ mode: PlayerVisibility, seconds: Double = 3) -> (PlayerVisibilityController, FakeWindow, ManualSleeper) {
        let sleeper = ManualSleeper()
        let controller = PlayerVisibilityController(mode: mode, displaySeconds: seconds) { try await sleeper.sleep($0) }
        let window = FakeWindow()
        window.attach(to: controller)
        return (controller, window, sleeper)
    }

    /// Settings' Show the player choices (DESIGN.md §8), stored under the
    /// names from before so saved settings carry over.
    @Test func theModesReadAsSettingsNamesThem() {
        #expect(PlayerVisibility.allCases.map(\.title) == ["Always", "On Track Change", "Under Menu Bar", "On Request"])
        #expect(PlayerVisibility.allCases.map(\.rawValue) == ["pinned", "trackChanges", "tucked", "summoned"])
    }

    @Test func alwaysVisibleShowsAtLaunchAndOnlyThen() {
        let (controller, window, _) = make(.pinned)
        controller.launch()
        #expect(window.shows == [.launch])
        controller.trackDidChange()
        controller.playerDidResignKey()
        #expect(window.shows == [.launch])
        #expect(window.hides == 0)
        #expect(!controller.hasPendingHide)
    }

    @Test func theOtherModesStayHiddenAtLaunch() {
        for mode in [PlayerVisibility.trackChanges, .summoned, .tucked] {
            let (controller, window, _) = make(mode)
            controller.launch()
            #expect(window.shows.isEmpty)
        }
    }

    @Test func onTrackChangeItAppearsThenTucksItselfAway() async {
        let (controller, window, sleeper) = make(.trackChanges)
        controller.trackDidChange()
        #expect(window.shows == [.trackChange])
        #expect(controller.hasPendingHide)
        await waitUntil { sleeper.waiting == 1 }
        #expect(sleeper.requested == [.seconds(3)])
        #expect(window.hides == 0)

        sleeper.elapse()
        await waitUntil { window.hides == 1 }
        #expect(window.hides == 1)
        #expect(!controller.hasPendingHide)
    }

    @Test func theCountdownWaitsWhileTheUserIsUsingIt() async {
        let (controller, window, sleeper) = make(.trackChanges)
        window.isEngaged = true
        controller.trackDidChange()
        // No countdown at all while the user is in it.
        #expect(!controller.hasPendingHide)
        #expect(sleeper.requested.isEmpty)

        window.isEngaged = false
        controller.engagementDidChange()
        #expect(controller.hasPendingHide)
        await waitUntil { sleeper.waiting == 1 }
        #expect(window.hides == 0)
        sleeper.elapse()
        await waitUntil { window.hides == 1 }
        #expect(window.hides == 1)
    }

    @Test func engagingMidCountdownKeepsItUp() async {
        let (controller, window, sleeper) = make(.trackChanges)
        controller.trackDidChange()
        window.isEngaged = true
        await waitUntil { sleeper.waiting == 1 }
        sleeper.elapse()
        await waitUntil { !controller.hasPendingHide }
        #expect(!controller.hasPendingHide)
        #expect(window.hides == 0)
        #expect(window.isVisible)
    }

    @Test func hidingByHandCancelsTheCountdown() {
        let (controller, _, _) = make(.trackChanges)
        controller.trackDidChange()
        controller.userDidHide()
        #expect(!controller.hasPendingHide)
    }

    @Test func summonedAndTuckedHideWhenTheUserClicksElsewhere() {
        for mode in [PlayerVisibility.summoned, .tucked] {
            let (controller, window, _) = make(mode)
            window.isVisible = true
            controller.playerDidResignKey()
            #expect(window.hides == 1)
            controller.playerDidResignKey()
            #expect(window.hides == 1)
        }
    }

    @Test func switchingToAlwaysVisibleShowsAHiddenPlayer() {
        let (controller, window, _) = make(.summoned)
        controller.mode = .pinned
        #expect(window.shows == [.user])
        controller.mode = .pinned
        #expect(window.shows == [.user])
    }

    @Test func switchingToOnTrackChangeStartsTheCountdownIfShowing() {
        let (controller, window, _) = make(.pinned)
        window.isVisible = true
        controller.mode = .trackChanges
        #expect(controller.hasPendingHide)
        controller.mode = .summoned
        #expect(!controller.hasPendingHide)
    }
}
